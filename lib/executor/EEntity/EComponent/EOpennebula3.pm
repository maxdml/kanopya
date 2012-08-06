#    Copyright © 2011 Hedera Technology SAS
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU Affero General Public License as
#    published by the Free Software Foundation, either version 3 of the
#    License, or (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU Affero General Public License for more details.
#
#    You should have received a copy of the GNU Affero General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
package EEntity::EComponent::EOpennebula3;
use base "EEntity::EComponent";
use base "EManager::EHostManager";

use strict;
use warnings;
use Entity;
use EFactory;
use General;
use CapacityManagement;
use XML::Simple;
use Log::Log4perl "get_logger";
use Data::Dumper;
use NetAddr::IP;
use File::Copy;
use Hash::Merge qw(merge);

my $log = get_logger("executor");
my $errmsg;

###############################
# component interface methods #
###############################

sub addNode {
    my ($self, %args) = @_;
    General::checkParams(
        args     => \%args, 
        required => [ 'host', 'mount_point', 'cluster' ]
    );

    $self->configureNode(%args);
}

# generate configuration files on node
sub configureNode {
    my ($self, %args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['cluster', 'host', 'mount_point']
    );

    my $masternodeip = $args{cluster}->getMasterNodeIp();
    my $hypervisor_type = $self->getHypervisorType();

    if(not $masternodeip) {
        # we start the first node so we start opennebula services
        $log->info('opennebula frontend configuration');
        $log->debug('generate /etc/one/oned.conf');

        $self->_generateOnedConf(%args);

        $self->addInitScripts(
                mountpoint => $args{mount_point},
                scriptname => 'opennebula',
        );

        $self->addInitScripts(
                mountpoint => $args{mount_point},
                scriptname => 'nfs-kernel-server',
        );

        my $admin = $args{host}->getAdminIface();
        my $network = NetAddr::IP->new(
            $admin->getIPAddr(),
            $admin->getPoolip()->poolip_netmask,
        )->network();

        my $exports = "/var/lib/one $network(rw,no_root_squash,no_subtree_check)\n";
        my $cmd = "echo '$exports' > " .$args{mount_point}."/etc/exports";
        $self->getExecutorEContext->execute(command => $cmd);

    } else {
        my $mount = $masternodeip.":/var/lib/one /var/lib/one nfs rw,sync,vers=3 0 0\n";
        my $cmd = "echo '$mount' >> ".$args{mount_point}."/etc/fstab";
        $self->getExecutorEContext->execute(command => $cmd);
    }

    # configure kvm hypervisor
    if($hypervisor_type eq 'kvm') {
        $log->debug('generate /etc/default/libvirt-bin');
        $self->_generateLibvirtbin(%args);

        $log->debug('generate /etc/libvirt/libvirtd.conf');
        $self->_generateLibvirtdconf(%args);

        $log->debug('generate /etc/libvirt/qemu.conf');
        $self->_generateQemuconf(%args);
        
        $self->addInitScripts(
          mountpoint => $args{mount_point},
          scriptname => 'libvirt-bin',
        );

        $self->addInitScripts(
              mountpoint => $args{mount_point},
              scriptname => 'qemu-kvm',
        );
    # configure xen hypervisor
    } elsif($hypervisor_type eq 'xen') {
        $log->debug('generate /etc/xen/xend-config.sxp');
        $self->_generateXenconf(%args);

        $self->addInitScripts(
              mountpoint => $args{mount_point},
              scriptname => 'xend',
        );

        $self->addInitScripts(
              mountpoint => $args{mount_point},
              scriptname => 'xendomains',
        );
    }
}

sub postStartNode {
    my ($self, %args) = @_;
    General::checkParams(
        args     => \%args, 
        required => [ 'cluster', 'host' ]
    );
    
    # if the host is the opennebula master, we register datastores
    #if($args{cluster}->getMasterNodeIp() eq $args{host}->getAdminIp()) {
    #    my $conf = $self->getConf();
    #    my $repositories = $conf->{opennebula3_repositories};
    #    for my $repo (@$repositories) {
        
    #        my $datastore_name;
    #        my $datastore_template = $self->generateDatastoreTemplate(ds_name => $datastore_name);
    #        my $datastoreid = $self->onedatastore_create(file => $datastore_template);
    #    }
    #}
    
 
 
    # hypervisor declaration
    my $hostname = $args{host}->getAttr(name => 'host_hostname');
    my $hostid = $self->onehost_create(hostname => $hostname);

    # Delete the hypervisor from opennebula if the operation fail later.
    if (exists $args{erollback} and defined $args{erollback}){
        $args{erollback}->add(
            function   => $self->can('onehost_delete'),
            parameters => [ $self, 'host_nameorid', $hostid ]
        );
    }

    $log->info('Hypervisor id returned by opennebula: ' . $hostid);
    my $hypervisor = $self->addHypervisor(
        host => $args{host}->_getEntity, 
        id   => $hostid
    );

    $self->onehost_enable(host_nameorid => $hostname);
    
}

sub preStopNode {
    my ($self, %args) = @_;
    General::checkParams(
        args     => \%args, 
        required => [ 'cluster', 'host' ]
    );

     $self->onehost_delete(host_nameorid => $args{host}->onehost_id);
     # TODO verifier le succes de la commande

     $self->_getEntity->removeHypervisor(host => $args{host});
}

sub getVmResources {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => [ 'vm' ]);
    my $hypervisor = EFactory::newEEntity(data => $args{vm}->hypervisor);
    my $all_capa = $self->getVmsResources(hypervisor => $hypervisor);
    return $all_capa->{$args{vm}->getId()}; #ram/cpu
};

sub getVmsResources {
    my ($self, %args) = @_;
    General::checkParams(args     => \%args, required => [ 'hypervisor' ]);
    $log->info(ref $args{hypervisor});
    my $cpu_resources = $self->getCpuResources(hypervisor => $args{hypervisor});
    my $mem_resources = $self-> getMemResources(hypervisor => $args{hypervisor});

    return merge($cpu_resources, $mem_resources);

}
sub getMemResources {
    my ($self, %args) = @_;

    General::checkParams(args     => \%args, required => [ 'hypervisor' ]);

    my $command = 'xentop -b -i 1 ';
    my $result  = $args{hypervisor}->getEContext->execute(command => $command);
    my $res = $result->{stdout};

    my @lines = split('\n',$res);
    shift @lines; #remove first line (titles)
    shift @lines; #remove second line (Dom0)

    my %hash;
    for my $line (@lines) {
        $line =~ s/^\s+//;
        my @splited_line = split('\s+',$line);
        my ($foo,$vm_id) = split '-',$splited_line[0];
        my $one3vm = Entity::Host::VirtualMachine::Opennebula3Vm->find(hash => {onevm_id => $vm_id});
        $hash{$one3vm->getId()}->{ram} = $splited_line[4] * 1024;
    }
    return \%hash;
}

sub getCpuResources {
    my ($self, %args) = @_;

    General::checkParams(args     => \%args, required => [ 'hypervisor' ]);

    my $command = 'xm list';
    my $result  = $args{hypervisor}->getEContext->execute(command => $command);
    my $res = $result->{stdout};

    my @lines = split('\n',$res);
    shift @lines; #remove first line (titles)
    shift @lines; #remove second line (Dom0)

    my %hash;
    for my $line (@lines) {
        my @splited_line = split('\s+',$line);
        my ($foo,$vm_id) = split '-',$splited_line[0];
        my $one3vm = Entity::Host::VirtualMachine::Opennebula3Vm->find(hash => {onevm_id => $vm_id});

        $hash{$one3vm->getId()}->{cpu} = $splited_line[3];
    }
    return \%hash;
}



sub getHostsMemAvailable {
    my ($self, %args) = @_;
    my $hypervisors = $self->getHypervisors();
    my $hash;

    for my $hypervisor (@$hypervisors) {
        $hash->{$hypervisor->getId()} = $self->getHostMemAvailable(host => $hypervisor);
    }
    return $hash;
}

#return host mem in bytes
sub getHostMemAvailable {
    my ($self, %args) = @_;

    General::checkParams(args     => \%args,
                         required => [ 'host' ]);

    my $e_host  = EFactory::newEEntity(data => $args{host});
    my $command = 'xm info';
    my $result  = $e_host->getEContext->execute(command => $command);
    my $res = $result->{stdout};

    my @lines = split('\n',$res);
    for my $line (@lines) {
        my ($key,$value) = split(':',$line);
        $key =~ s/\s+//; #Remove spaces before and after
        $value =~ s/\s+//;
        if($key eq 'free_memory') { return $value * 1024 * 1024} #in bytes
    }
}

# Execute host migration to a new hypervisor
sub migrateHost {
    my $self = shift;
    my %args = @_;

    General::checkParams(args     => \%args,
                         required => [ 'host', 'hypervisor_dst', 'hypervisor_cluster']);

    # instanciate opennebula master node econtext
    my $masternodeip = $args{hypervisor_cluster}->getMasterNodeIp();
    my $masternode_econtext = EFactory::newEContext(ip_source      => $self->getExecutorEContext->getLocalIp,
                                                    ip_destination => $masternodeip);

    # Get the source hypervisor
    my $src_hypervisor = $args{host}->hypervisor;
    $log->debug("The VM <" . $args{host}->getId . "> is on the <" . $src_hypervisor->getId . "> host");

    my $hypervisor_id = $args{hypervisor_dst}->onehost_id;
    my $hypervisor_host_name = $args{hypervisor_dst}->getAttr(name=>'host_hostname');

    my $host_id = $args{host}->onevm_id;

    $log->debug("Apply VLAN on the destination hypervisor");
    $self->propagateVLAN(host       => $args{host},
                         hypervisor => $args{hypervisor_dst});

    my $command_to_exec = "onevm livemigrate $host_id $hypervisor_id" ;
    my $command = $self->_oneadmin_command(command => $command_to_exec);
    my $result = $masternode_econtext->execute(command => $command);
    $log->debug('Migration command: '.$command_to_exec);

    return $src_hypervisor;
}


sub getVMState {
    my ($self,%args) = @_;
    General::checkParams(args     => \%args, required => ['host']);

    my $host_id = $args{host}->onevm_id;

    my $command = $self->_oneadmin_command(command => "onevm show $host_id --xml");
    my $result  = $self->getEContext->execute(command => $command);
    my $hxml = XMLin($result->{stdout});

    my $history = $hxml->{HISTORY_RECORDS}->{HISTORY};
    my $hypervisor_migr;

    if (ref $history eq 'HASH') {
        $hypervisor_migr = $history->{HOSTNAME};
    }
    elsif (ref $history eq 'ARRAY')  {
        $hypervisor_migr =  $history->[-1]->{HOSTNAME};
    }
    # Else $hypervisor_migr stay undef

    my $state_id     = $hxml->{STATE};
    my $lcm_state_id = $hxml->{LCM_STATE};

    my $state = {
         0 => { 0 => 'init' },
         1 => { 0 => 'pend' },
         2 => { 0 => 'hold' },
         3 => { 1 => 'prog', 2 => 'boot', 3 => 'runn', 4 => 'migr', 5 => 'save',
                6 => 'save', 7 => 'save', 8 => 'migr', 9 => '',    10 => 'epil',
               11 => 'epil', 12 => 'shut', 13 => 'shut'},
         4 => { 0 => 'stop' },
         5 => { 0 => 'suspended' },
         6 => { 0 => 'done' },
         7 => { 0 => 'fail' },
    };

    $log->info("<$state_id> <$lcm_state_id> => <".($state->{$state_id}->{$lcm_state_id}).'>');
    return { state => $state->{$state_id}->{$lcm_state_id}, hypervisor => $hypervisor_migr };

}

# execute memory scale in
sub scale_memory {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ 'host', 'memory' ]);

    my $memory = $args{memory};

    my $host_id = $args{host}->onevm_id;
    my $command = $self->_oneadmin_command(command => "onevm memset $host_id $memory");

    $self->getEContext->execute(command => $command);

    # Memroy scale checked in post requisite before saving in DB
    # return $self->_getEntity()->updateMemory(%args);
}



sub restoreHost {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'hypervisor' ]);
    # Option  resources, hypervisor, resubmit


    my $host_name = $args{hypervisor}->host_hostname;
    my $vms       = $args{hypervisor}->getVms();



    if (defined $args{check_resubmit} || defined $args{check_hypervisor}) {
        for my $vm (@{$vms}) {
            my $state = $self->getVMState(host => $vm );

            $log->info('vm <'.($vm->getId).'> hv '.$state->{hypervisor}.' state '.$state->{state});
            if($state->{state} eq 'runn') {
                if (defined $args{hypervisor}) {
                    if(!($args{hypervisor}->host_hostname eq $state->{hypervisor})){
                        $log->info('VM running on a wrong hypervisor');
                        $vm->setAttr(name => 'hypervisor_id', value => Entity::Host->find(hash => {host_hostname => $state->{hypervisor}})->getId());
                        $vm->save();
                    }
                }
            }
            else{
                if(defined $args{check_resubmit}){
                    my $command = $self->_oneadmin_command(command => 'onevm resubmit '.$vm->onevm_id);
                    my $result  = $self->getEContext->execute(command => $command);
                }
            }
        }
    }

    if (defined $args{check_resources}) {
        my $host_vm_capacities = $self->getVmsResources(hypervisor => $args{hypervisor});
        $log->info(Dumper $host_vm_capacities);

        for my $vm (@{$vms}) {
            $log->info('VM <'.($vm->getId()).'> <'.($vm->host_hostname).'>');

            if(defined $host_vm_capacities->{$vm->getId()}->{ram}) {

                if ( (not defined $vm->host_ram)
                     || $host_vm_capacities->{$vm->getId()}->{ram} != $vm->host_ram) {
                        $log->info('Memory one = '.($host_vm_capacities->{$vm->getId()}->{ram}).' VS db = '.($vm->host_ram));
                        $vm->setAttr(name => 'host_ram', value => $host_vm_capacities->{$vm->getId()}->{ram});
                        $vm->save();
                }
            }
            else {
                $log->info('No RAM value from opennebula for this VM, try to check hypervisor or resubmit it');
            }

            if(defined $host_vm_capacities->{$vm->getId()}->{ram}) {
                if( (not defined $vm->host_core)
                    || $host_vm_capacities->{$vm->getId()}->{cpu} != $vm->host_core){
                    $log->info('Cpu one = '.(($host_vm_capacities->{$vm->getId()}->{cpu})).' VS db = '.($vm->host_core));
                    $vm->setAttr(name => 'host_core', value => $host_vm_capacities->{$vm->getId()}->{cpu});
                    $vm->save();
                }
            }
            else {
                $log->info('No CPU value from opennebula for this VM, try to check hypervisor or resubmit it');
            }
       }
    }
}

#execute cpu scale in
sub scale_cpu {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ 'host', 'cpu_number' ]);

    my $cpu_number = $args{cpu_number};

    my $host_id = $args{host}->onevm_id;
    my $command = $self->_oneadmin_command(command => "onevm vcpuset $host_id $cpu_number");

    $self->getEContext->execute(command => $command);

    #return $self->_getEntity()->updateCPU(%args);
}



sub retrieveOpennebulaHypervisorStatus {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host' ] );

    my $command = $self->_oneadmin_command(command => 'onehost show '.$args{host}->host_hostname.' --xml');
    my $result  = $self->getEContext->execute(command => $command);
    my $hxml    = XMLin($result->{stdout});
    if($hxml->{STATE} != 2) {
        $log->info('hypervisor <'.$args{host}->host_hostname.'> error for opennebula');
        return 0;
    }

    $log->info('hypervisor <'.$args{host}->host_hostname.'> running for opennebula');
    return 1;
}

sub isUp {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ 'cluster', 'host' ] );
    my $ip = $args{host}->getAdminIp;

    my $hypervisor_status = 1;
    eval {
        # Skip ths test if the cluster has no master node yet.
        $self->getEContext;

        $hypervisor_status = $self->retrieveOpennebulaHypervisorStatus(host => $args{host});
    };

    if ($hypervisor_status == 0) {
        return 0;
    }

    if(defined $args{cluster}->getMasterNodeIp() and $args{cluster}->getMasterNodeIp() eq $ip) {
        # host is the opennebula frontend
        # we must test opennebula port reachability
        my $net_conf = $self->{_entity}->getNetConf();
        my ($port, $protocols) = each %$net_conf;
        my $cmd = "nmap -n -sT -p $port $ip | grep $port | cut -d\" \" -f2";
        my $port_state = `$cmd`;
        chomp($port_state);
        $log->debug("Check host <$ip> on port $port ($protocols->[0]) is <$port_state>");
        if ($port_state eq "closed"){
            return 0;
        }
    } else {
        # host is an hypervisor node
        # we must test libvirtd port reachability
        my $port = 16509;
        my $proto = 'tcp';
        my $cmd = "nmap -n -sT -p $port $ip | grep $port | cut -d\" \" -f2";
        my $port_state = `$cmd`;
        chomp($port_state);
        $log->debug("Check host <$ip> on port $port ($proto) is <$port_state>");
        if ($port_state eq "closed"){
            return 0;
        }
    }

    return 1;
}

# generate vm template and start a vm from the template
sub startHost {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ 'host' ]);

    if( !defined $args{hypervisor}){
        my $errmsg = "Cannot add node in cluster ".$args{host}->getClusterId().", no hypervisor available";
        throw Kanopya::Exception::Internal(error => $errmsg);
    }

    # Pick up an hypervisor

    my $hypervisor = $args{hypervisor};
    $log->info("Picked up hypervisor " . $hypervisor->getId());

    # generate template in opennebula master node
    my $vm_template = $self->_generateVmTemplate(
                          host       => $args{host},
                          hypervisor => $hypervisor,
                      );

    # Apply the VLAN's on the hypervisor interface dedicated to virtual machines
    $self->propagateVLAN(host       => $args{host},
                         hypervisor => $hypervisor);

    # create the vm from template
    my $command = $self->_oneadmin_command(command => "onevm create $vm_template");
    my $result = $self->getEContext->execute(command => $command);

    # declare vm in database
    my $id = substr($result->{stdout}, 4);
    $log->info('vm id returned by opennebula: '.$id);

    # $command = $self->_oneadmin_command(command => "onevm hold $id");
    # $result = $masternode_econtext->execute(command => $command);

    $self->_getEntity()->addVM(
        host       => $args{host},
        id         => $id,
        hypervisor => $hypervisor
    );

}

# delete a vm from opennebula
sub stopHost {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ 'host' ]);

    # retrieve vm info from opennebula

    my $id = $args{host}->onevm_id;
    my $command = $self->_oneadmin_command(command => "onevm delete $id");
    my $result = $self->getEContext->execute(command => $command);

    # In the case of OpenNebula, we delete the host once it's stopped
    $args{host}->setAttr(name  => 'active',
                         value => '0');
    $args{host}->save;
    $args{host}->remove;
}

# update a vm information (hypervisor host and vnc port)
sub postStart {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ 'host' ]);

    my $id = $args{host}->onevm_id;
    my $command = $self->_oneadmin_command(command => "onevm show $id --xml");
    my $result = $self->getEContext->execute(command => $command);
    my $hxml = XMLin($result->{stdout});

    my $vnc_port = $hxml->{TEMPLATE}->{GRAPHICS}->{PORT};

     # Check final RAM and CPU and store
    my $vm_capacities = $self->getVmResources(vm  => $args{host});

    $args{host}->setAttr(name => 'vnc_port', value => $vnc_port);
    $args{host}->setAttr(name => 'host_ram', value => $vm_capacities->{ram});
    $args{host}->setAttr(name => 'host_core', value => $vm_capacities->{cpu});
     # Check final RAM and CPU and store

    $log->info('Set Ram and Cpu from real info : ram <'.($vm_capacities->{ram}).'> cpu <'.($vm_capacities->{cpu}).'>');

    $args{host}->save();
}

sub getFreeHost {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ "ram", "core", "ifaces" ]);

    if ($args{ram_unit}) {
        $args{ram} = General::convertToBytes(value => $args{ram}, units => $args{ram_unit});
        delete $args{ram_unit};
    }

    $log->info("Looking for a virtual host");
    my $host = eval{
        return $self->_getEntity->createVirtualHost(
                   core   => $args{core},
                   ram    => $args{ram},
                   ifaces => $args{ifaces},
               );
    };
    if ($@) {
        $errmsg = "Component OpenNebula3 <" . $self->_getEntity->getAttr(name => 'component_id') .
                  "> No capabilities to host this vm core <$args{core}> and ram <$args{ram}>:\n" . $@;
        # We can't create virtual host for some reasons (e.g can't meet constraints)
        throw Kanopya::Exception::Internal(error => $errmsg);
    }

    return $host;
}

# generate vm template and push it on opennebula master node
sub _generateVmTemplate {
    my ($self, %args) = @_;
    General::checkParams(
        args     => \%args, 
        required => [ 'hypervisor','host']
    );
    
    my $hypervisor_type = $self->getHypervisorType();
    
    # generate image template and register it
    my $image_templatefile = $self->generateImageTemplate(
    
    );
    my $imageid = $self->oneimage_create(
    
    );
    # generate vnet templates for each ifaces and register them
    
    
    # generate vm template and create it
    my $vm_templatefile;
    if($hypervisor_type eq 'kvm') {
        $vm_templatefile = $self->generateKvmVmTemplate(
        
        )
    } elsif($hypervisor_type eq 'xen') {
        $vm_templatefile = $self->generateXenVmTemplate(
        
        )
    }
    my $vmid = $self->onevm_create(file => $vm_templatefile);
    
}

sub applyVLAN {
    my ($self, %args) = @_;
    General::checkParams(
        args     => \%args, 
        required => [ 'iface', 'vlan' ]
    );

    # In the case of OpenNebula, we need to apply the VLAN on the
    # bridge interface of the hypervisor the VM is running on.
}

# Apply the VLAN's on the hypervisor interface dedicated to virtual machines

sub propagateVLAN {
    my ($self, %args) = @_;
    General::checkParams(
        args     => \%args, 
        required => [ 'host', 'hypervisor' ]
    );

    my $bridge = ($args{hypervisor}->getIfaces(role => 'vms'))[0];
    for my $iface (@{$args{host}->getIfaces}) {
        for my $network ($iface->getInterface->getNetworks) {
            if ($network->isa("Entity::Network::Vlan")) {
                $log->info("Applying vlan " . $network->getAttr(name => "network_name") .
                           " on the bridge interface " . $iface->getAttr(name => "iface_name"));
                my $ehost_manager = EFactory::newEEntity(data => $args{hypervisor}->getHostManager);
                $ehost_manager->applyVLAN(iface => $bridge,
                                          vlan  => $network,
                                          delete => (defined ($args{delete}) && $args{delete}) ? 1 : 0);
            }
        }
    }
}

sub vmLoggedErrorMessage {
    my ($self,%args) = @_;
    General::checkParams(
        args     => \%args, 
        required => [ 'opennebula3_vm' ]
    );

    my $command = one_command('tail -n 50 /var/log/one/oned.log |grep "LOG I '.($args{opennebula3_vm}->onevm_id).' Error"');

    $log->debug("commande = $command");
    my $result  = $self->getEContext->execute(command => $command);
    my $output  = $result->{stdout};
    $log->debug($output);

    my @lastmessage =  split '\n',$output;

    $log->debug(@lastmessage);
    return $lastmessage[-1];

}

sub forceDeploy {
    my ($self, %args) = @_;
    General::checkParams(
        args     => \%args, 
        required => [ 'vm', 'hypervisor' ]
    );
    $self->onevm_deploy(
        vmid   => $args{vm}->onevm_id, 
        hostid => $args{hypervisor}->getId()->onehost_id
    );
}

#########################################
# configuration files generation methods #
#########################################

# generate /etc/oned.conf configuration file
sub _generateOnedConf {
    my ($self, %args) = @_;
    General::checkParams(
        args     => \%args, 
        required => [ 'host', 'mount_point']
    );

    my $cluster = $self->_getEntity->getServiceProvider;
    my $data = $self->_getEntity()->getTemplateDataOned();
    my $file = $self->generateNodeFile(
        cluster       => $cluster,
        host          => $args{host},
        file          => '/etc/one/oned.conf',
        template_dir  => '/templates/components/opennebula',
        template_file => 'oned.conf.tt',
        data          => $data
    );

    $self->getExecutorEContext->send(
        src  => $file,
        dest => $args{mount_point}.'/etc/one'
    );
}

# generate /etc/default/libvirt-bin configuration file
sub _generateLibvirtbin {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host', 'mount_point', 'cluster' ]);

    my $cluster = $self->_getEntity->getServiceProvider;
    my $data = $self->_getEntity()->getTemplateDataLibvirtbin();
    my $file = $self->generateNodeFile(
        cluster       => $cluster,
        host          => $args{host},
        file          => '/etc/default/libvirt-bin',
        template_dir  => "/templates/components/opennebula",
        template_file => 'libvirt-bin.tt',
        data          => $data
    );

    $self->getExecutorEContext->send(
        src  => $file,
        dest => $args{mount_point}.'/etc/default'
    );
}

# generate /etc/libvirt/libvirtd.conf configuration file
sub _generateLibvirtdconf {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host', 'mount_point', 'cluster' ]);

    my $data = $self->_getEntity()->getTemplateDataLibvirtd();
    $data->{listen_ip_address} = $args{host}->getAdminIp;
    my $file = $self->generateNodeFile(
        cluster       => $args{cluster},
        host          => $args{host},
        file          => '/etc/libvirt/libvirtd.conf',
        template_dir  => '/templates/components/opennebula',
        template_file => 'libvirtd.conf.tt',
        data          => $data
    );

    $self->getExecutorEContext->send(
        src  => $file,
        dest => $args{mount_point}.'/etc/libvirt'
    );
}

# generate /etc/libvirt/qemu.conf configuration file
sub _generateQemuconf {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host', 'mount_point', 'cluster' ]);

    my $data = {};
    my $file = $self->generateNodeFile(
        cluster       => $args{cluster},
        host          => $args{host},
        file          => '/etc/libvirt/qemu.conf',
        template_dir  => '/templates/components/opennebula',
        template_file => 'qemu.conf.tt',
        data          => $data
    );

    $self->getExecutorEContext->send(
        src  => $file,
        dest => $args{mount_point}.'/etc/libvirt'
    );
}

# generate /etc/xen/xend-config.sxp configuration file
sub _generateXenconf {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host', 'mount_point', 'cluster' ]);

    # TODO recup de l'interface pour les vms
    my $data = {
             vmiface => 'eth1',
        min_mem_dom0 => '1024'
    };

    my $file = $self->generateNodeFile(
        cluster       => $args{cluster},
        host          => $args{host},
        file          => '/etc/xen/xend-config.sxp',
        template_dir  => '/templates/components/opennebula',
        template_file => 'xend-config.sxp.tt',
        data          => $data
    );

    $self->getExecutorEContext->send(
        src  => $file,
        dest => $args{mount_point}.'/etc/xen'
    );
}

###########################################
# opennebula templates generation methods #
###########################################

# generate datastore template and push it on opennebula master node
sub generateDatastoreTemplate {
    my ($self, %args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['ds_name']
    );
    
    my $data = {
        datastore_name   => $args{ds_name},
        datastore_ds_mad => 'fs',
        datastore_tm_mad => 'shared',
    };
    
    my $template_file = 'datastore-' . $args{ds_name} . '.tt';
    my $file = $self->generateNodeFile(
        cluster       => $self->_getEntity->getServiceProvider,
        host          => $args{hypervisor},
        file          => $template_file,
        template_dir  => '/templates/components/opennebula',
        template_file => 'datastore.tt',
        data         => $data,
    );

    $self->getEContext->send(
        src  => $file,
        dest => '/tmp'
    );
    return '/tmp/' . $template_file;
}

# generate image template and push it on opennebula master node
# image_source is $datastore_id/$image_file.img
sub generateImageTemplate {
    my ($self, %args) = @_;
    General::checkParams(
        args     => \%args, 
        required => [ 'image_name','image_source','image_desc', 'hypervisor_type']
    );
       
    my $data = {
        image_name        => $args{name},
        image_source      => $args{image_source},
        image_type        => 'OS',
        image_description => $args{image_desc},
        image_persistent  => 'YES', 
    };
    
    if($args{hypervisor_type} eq 'xen') {
        $data->{image_driver} = '"file:"';
        $data->{image_target} = 'xvda';
    } elsif($args{hypervisor_type} eq 'kvm') {
        $data->{image_driver} = 'raw';
        $data->{image_target} = 'sd';
    }
    
    my $template_file = 'image-' . $args{name} . '.tt';
    my $file = $self->generateNodeFile(
        cluster       => $self->_getEntity->getServiceProvider,
        host          => $args{hypervisor},
        file          => $template_file,
        template_dir  => '/templates/components/opennebula',
        template_file => 'image.tt',
        data         => $data,
    );

    $self->getEContext->send(
        src  => $file,
        dest => '/tmp'
    );
    return '/tmp/' . $template_file;
}

# generate vnet template and push it on opennebula master node
# name 
sub generateVnetTemplate {
    my ($self, %args) = @_;
    General::checkParams(
        args     => \%args, 
        required => [ 'name','']
    );
    
    my $data = {
        vnet_name       => $args{name},
        vnet_type       => 'RANGED',
        vnet_bridge     => ,
        vnet_vlanid     => ,
        vnet_phydev     => ,
        vnet_netaddress => '10.0.0.0/24',
    };
    
    my $template_file = 'vnet-' . $args{name} . '.tt';
    my $file = $self->generateNodeFile(
        cluster       => $self->_getEntity->getServiceProvider,
        host          => $args{hypervisor},
        file          => $template_file,
        template_dir  => '/templates/components/opennebula',
        template_file => 'vnet.tt',
        data         => $data,
    );

    $self->getEContext->send(
        src  => $file,
        dest => '/tmp'
    );
    return '/tmp/' . $template_file;
    
}

# generate xen vm template and push it on opennebula master node
sub generateXenVmTemplate {
    my ($self, %args) = @_;
    General::checkParams(
        args     => \%args, 
        required => [ 'hypervisor','host']
    );

    # host_ram is stored in octect, so we convert it to megaoctect
    my $ram = General::convertFromBytes(
        value => $args{host}->getAttr(name => 'host_ram'),
        units => 'M'
    );

    my $tftp_conf = $self->{config}->{tftp}->{directory};
    my $cluster = Entity->get(id => $args{host}->getClusterId());

    my $kernel = Entity->get(id => $cluster->getAttr(name => "kernel_id"));
    my $kernel_version = $kernel->getAttr(name => "kernel_version");

    my $disk_params = $cluster->getManagerParameters(manager_type => 'disk_manager');
    my $image = $args{host}->getNodeSystemimage();
    my $image_name = $image->getAttr(name => 'systemimage_name') . '.img';
    my $hostname = $args{host}->getAttr(name => 'host_hostname');

    my %repo = $self->_getEntity()->getImageRepository(
                   container_access_id => $disk_params->{container_access_id}
               );

    my $repository_path = $self->_getEntity()->getAttr(name => 'image_repository_path') .
                          '/' . $repo{repository_name};

    my $interfaces = [];
    my $bridge = ($args{hypervisor}->getIfaces(role => 'vms'))[0];
    for my $iface ($args{host}->getIfaces()) {
        for my $network ($iface->getInterface->getNetworks) {
            my $vlan = $network->isa("Entity::Network::Vlan") ?
                           $network->getAttr(name => "vlan_number") : undef;

            my $data = {
                mac => $iface->getAttr(name => 'iface_mac_addr'),
                bridge  => "br-" . ($vlan || "default"),
                phydev  => "p" . $bridge->getAttr(name => "iface_name"),
                vlan    => $vlan
            };
            push @{$interfaces}, $data;
        };
    }

    my $kernel_filename = 'vmlinuz-' . $kernel_version;
    my $initrd_filename = 'initrd_' . $kernel_version;

    my $data = {
        name            => $hostname,
        memory          => $ram,
        cpu             => $args{host}->host_core,
        kernelpath      => $repository_path . '/' . $kernel_filename,
        initrdpath      => $repository_path . '/' . $initrd_filename,
        imagepath       => $repository_path . '/' . $image_name,
        bridge_iface    => ($args{hypervisor}->getIfaces(role => "vms"))[0]->iface_name,
        hypervisor_type => $self->_getEntity->hypervisor,
        hypervisor_name => $args{hypervisor}->host_hostname,
        interfaces      => $interfaces,
    };

    my $template_file = 'vm-' . $hostname . '.tt';
    my $file = $self->generateNodeFile(
        cluster       => $self->_getEntity->getServiceProvider,
        host          => $args{hypervisor},
        file          => $template_file,
        template_dir  => '/templates/components/opennebula',
        template_file => 'xen-vm.tt',
        data         => $data,
    );

    $self->getEContext->send(
        src  => $file,
        dest => '/tmp'
    );

    # If the kernel and the initramfs are not present in the
    # image repository, copy them into it

    my $container_access = Entity->get(id => $disk_params->{container_access_id});
    my $econtainer_access = EFactory::newEEntity(data => $container_access);
    my $mountpoint = $container_access->getContainer->getMountPoint . "_copy_kernel_$kernel_version";

    $econtainer_access->mount(mountpoint => $mountpoint,
                              econtext    => $self->getExecutorEContext);

    if (not -e "$mountpoint/$kernel_filename") {
        $log->info("Copying " . $tftp_conf . "/vmlinuz-" . $kernel_version . " to " . $mountpoint);
        copy($tftp_conf . "/vmlinuz-" . $kernel_version,
             $mountpoint);
    }

    if (not -e "$mountpoint/$initrd_filename") {
        $log->info("Copying " . $tftp_conf . "/initrd_" . $kernel_version . " to " . $mountpoint);
        copy($tftp_conf . "/initrd_" . $kernel_version,
             $mountpoint);
    }

    $econtainer_access->umount(mountpoint => $mountpoint,
                               econtext    => $self->getExecutorEContext);

    return '/tmp/' . $template_file;
    
}

# generate kvm vm template and push it on opennebula master node
sub generateKvmVmTemplate {
    my ($self, %args) = @_;
    General::checkParams(
        args     => \%args, 
        required => [ '','']
    );
}


########################################################
# methods to execute opennebula commands on masternode #
########################################################

sub one_command {
    my $command = @_;
    return "su oneadmin -c '" . $command . "'";
}

# declare a datastore from a template file and return the ID
sub onedatastore_create {
    my ($self,%args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['file']
    );
    
    my $cmd = one_command("onedatastore create $args{file}");
    my $result = $self->getEContext->execute(command => $cmd);
    if($result->{exitcode} != 0) {
        throw Kanopya::Exception::Execution(error => $result->{stdout});
    }
    
    if($result->{stdout} =~ /(\d+)/) {
        return $1;
    }
}

sub onedatastore_delete {
    my ($self,%args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['datastore_nameorid']
    );
    
    my $cmd = one_command("onedatastore delete $args{datastore_nameorid}");
    my $result = $self->getEContext->execute(command => $cmd);
}

sub onedatastore_list {
    my ($self) = @_;
   
    my $cmd = one_command("onedatastore list --xml");
    my $result = $self->getEContext->execute(command => $cmd);
    # TODO parse xml output and return hash structure
}

sub onedatastore_show {
    my ($self,%args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['datastore_nameorid']
    );
    
    my $cmd = one_command("onedatastore show $args{datastore_nameorid} --xml");
    my $result = $self->getEContext->execute(command => $cmd);
    # TODO parse xml output and return hash structure
}

sub oneimage_create {
    my ($self,%args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['datastore_nameorid','file']
    );
    
    my $cmd = one_command("oneimage create $args{datastore_nameorid} $args{file}");
    my $result = $self->getEContext->execute(command => $cmd);
    if($result->{exitcode} != 0) {
        throw Kanopya::Exception::Execution(error => $result->{stdout});
    }
    # TODO parse command output and return image id
}

sub oneimage_delete {
    my ($self,%args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['image_nameorid']
    );
    
    my $cmd = one_command("oneimage create $args{image_nameorid}");
    my $result = $self->getEContext->execute(command => $cmd);
}

sub oneimage_list {
    my ($self) = @_;
    
    my $cmd = one_command("oneimage list --xml");
    my $result = $self->getEContext->execute(command => $cmd);
    # TODO parse xml output and return hash structure
}

sub oneimage_show {
    my ($self,%args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['image_nameorid']
    );
    
    my $cmd = one_command("oneimage show $args{image_nameorid} --xml");
    my $result = $self->getEContext->execute(command => $cmd);
    # TODO parse xml output and return hash structure
}

sub onevnet_create {
    my ($self,%args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['file']
    );
    
    my $cmd = one_command("onevnet create $args{file}");
    my $result = $self->getEContext->execute(command => $cmd);
    if($result->{exitcode} != 0) {
        throw Kanopya::Exception::Execution(error => $result->{stdout});
    }
    if($result->{stdout} =~ /(\d+)/) {
        return $1;
    }
}

sub onevnet_delete {
    my ($self,%args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['vnet_nameorid']
    );
    
    my $cmd = one_command("onevnet delete $args{vnet_nameorid}");
    my $result = $self->getEContext->execute(command => $cmd);
}

sub onevnet_list {
    my ($self) = @_;

    
    my $cmd = one_command("onevnet list --xml");
    my $result = $self->getEContext->execute(command => $cmd);
    # TODO parse xml output and return hash structure
}

sub onevnet_show {
    my ($self,%args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['vnet_nameorid']
    );
    
    my $cmd = one_command("onevnet show $args{vnet_nameorid} --xml");
    my $result = $self->getEContext->execute(command => $cmd);
    # TODO parse xml output and return hash structure
}

sub onehost_create {
    my ($self,%args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['hostname']
    );
    
    my $hypervisor_type = $self->getHypervisorType();
    
    my $cmd = "onehost create $args{hostname} ";
    if($hypervisor_type eq 'xen') {
        $cmd .= 'im_xen vmm_xen 802.1Q none';
    } elsif($hypervisor_type eq 'kvm') {
        $cmd .= 'im_kvm vmm_kvm 802.1Q none';
    }
    
    $cmd = one_command($cmd);
    my $result = $self->getEContext->execute(command => $cmd);
    if($result->{exitcode} != 0) {
        throw Kanopya::Exception::Execution(error => $result->{stdout});
    }
    if($result->{stdout} =~ /(\d+)/) {
        return $1;
    }
}

sub onehost_delete {
    my ($self,%args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['host_nameorid']
    );
    
    my $cmd = one_command("onehost delete $args{host_nameorid}");
    my $result = $self->getEContext->execute(command => $cmd);
}

sub onehost_list {
    my ($self) = @_;
    
    my $cmd = one_command("onehost list --xml");
    my $result = $self->getEContext->execute(command => $cmd);
    # TODO parse xml output and return hash structure
}

sub onehost_show {
    my ($self,%args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['host_nameorid']
    );
    
    my $cmd = one_command("onehost show $args{host_nameorid} --xml");
    my $result = $self->getEContext->execute(command => $cmd);
    # TODO parse xml output and return hash structure
}

sub onehost_enable {
    my ($self,%args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['host_nameorid']
    );
    
    my $cmd = one_command("onehost enable $args{host_nameorid}");
    my $result = $self->getEContext->execute(command => $cmd);
}

sub onevm_create {
    my ($self,%args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['file']
    );
    
    my $cmd = one_command("onevm create $args{file}");
    my $result = $self->getEContext->execute(command => $cmd);
    if($result->{exitcode} != 0) {
        throw Kanopya::Exception::Execution(error => $result->{stdout});
    }
    if($result->{stdout} =~ /(\d+)/) {
        return $1;
    }
}

sub onevm_delete {
    my ($self,%args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['vm_nameorid']
    );
    
    my $cmd = one_command("onevm delete $args{vm_nameorid}");
    my $result = $self->getEContext->execute(command => $cmd);
}

sub onevm_deploy {
    my ($self,%args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['vm_nameorid', 'host_nameorid']
    );
    
    my $cmd = one_command("onevm deploy $args{vm_nameorid} $args{host_nameorid}");
    my $result = $self->getEContext->execute(command => $cmd);
}

sub onevm_hold {
    my ($self,%args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['vm_nameorid']
    );
    
    my $cmd = one_command("onevm hold $args{vm_nameorid}");
    my $result = $self->getEContext->execute(command => $cmd);
}

sub onevm_show {
    my ($self,%args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['vm_nameorid']
    );
    
    my $cmd = one_command("onevm show $args{vm_nameorid} --xml");
    my $result = $self->getEContext->execute(command => $cmd);
    # TODO parse xml output and return hash structure
}

sub onevm_livemigrate {
    my ($self,%args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['vm_nameorid','host_nameorid']
    );
    
    my $cmd = one_command("onevm livemigrate $args{vm_nameorid} $args{host_nameorid}");
    my $result = $self->getEContext->execute(command => $cmd);
}

sub onevm_memset {
    my ($self,%args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['vm_nameorid','ram']
    );
    
    my $cmd = one_command("onevm memset $args{vm_nameorid} $args{ram}");
    my $result = $self->getEContext->execute(command => $cmd);
}

sub onevm_vcpuset {
    my ($self,%args) = @_;
    General::checkParams(
        args     => \%args, 
        required => ['vm_nameorid','cpu']
    );
    
    my $cmd = one_command("onevm vcpuset $args{vm_nameorid} $args{cpu}");
    my $result = $self->getEContext->execute(command => $cmd);
}

sub onevm_list {
    my ($self) = @_;

    my $cmd = one_command("onevm list --xml");
    my $result = $self->getEContext->execute(command => $cmd);
    # TODO parse xml output and return hash structure
}



1;

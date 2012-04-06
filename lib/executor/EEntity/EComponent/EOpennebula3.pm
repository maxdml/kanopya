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
use base "EEntity::EHostManager";

use strict;
use warnings;
use Entity;
use EFactory;
use General;

use XML::Simple;
use Log::Log4perl "get_logger";
use Data::Dumper;

my $log = get_logger("executor");
my $errmsg;

# generate configuration files on node
sub configureNode {
    my $self = shift;
    my %args = @_;
    
    General::checkParams(args => \%args, required => [ 'econtext', 'host', 'mount_point', 'cluster' ]);

    my $masternodeip = $args{cluster}->getMasterNodeIp();
     
    if(not $masternodeip) {
        # we start the first node so we start opennebula services
        $log->info('opennebula frontend configuration');
        $log->debug('generate /etc/one/oned.conf');    
       
        $self->generateOnedConf(
               econtext => $args{econtext}, 
            mount_point => $args{mount_point}.'/etc'
        );
              
        $self->addInitScripts(
                mountpoint => $args{mount_point}, 
                  econtext => $args{econtext}, 
                scriptname => 'opennebula', 
        );
    } 
     
    $log->info("Opennebula cluster's node configuration");
    $log->debug('generate /etc/default/libvirt-bin');    
    $self->generateLibvirtbin( econtext    => $args{econtext}, 
                               mount_point => $args{mount_point}.'/etc');
    
    $log->debug('generate /etc/libvirt/libvirtd.conf');    
    $self->generateLibvirtdconf(
        econtext    => $args{econtext}, 
        mount_point => $args{mount_point}.'/etc', 
        host => $args{host}
    );

    $log->debug('generate /etc/libvirt/qemu.conf');    
    $self->generateQemuconf(
           econtext => $args{econtext}, 
        mount_point => $args{mount_point}.'/etc', 
               host => $args{host}
    );

    $self->generateXenconf(
           econtext => $args{econtext}, 
        mount_point => $args{mount_point}.'/etc', 
               host => $args{host}
    );

    $self->addInitScripts(
          mountpoint => $args{mount_point}, 
            econtext => $args{econtext}, 
          scriptname => 'xend', 
    );
   
   $self->addInitScripts(
          mountpoint => $args{mount_point}, 
            econtext => $args{econtext}, 
          scriptname => 'xendomains', 
   );
    
    $self->addInitScripts(
          mountpoint => $args{mount_point}, 
            econtext => $args{econtext}, 
          scriptname => 'libvirt-bin', 
   );
   
   $self->addInitScripts(
          mountpoint => $args{mount_point}, 
            econtext => $args{econtext}, 
          scriptname => 'qemu-kvm', 
   );
       
}

# Execute host migration to a new hypervisor
sub migrateHost {
    my $self = shift;
    my %args = @_;

    General::checkParams(args     => \%args,
                         required => [ 'host', 'hypervisor_dst',
                                       'hypervisor_cluster', 'econtext']);

    # instanciate opennebula master node econtext 
    my $masternodeip = $args{hypervisor_cluster}->getMasterNodeIp();


    my $masternode_econtext = EFactory::newEContext(ip_source      => $args{econtext}->getLocalIp,
                                                    ip_destination => $masternodeip);


    my $hypervisor_id = $self->_getEntity()->getHypervisorIdFromHostId(host_id => $args{hypervisor_dst}->getAttr(name => "host_id"));
    
    my $host_id = $self->_getEntity()->getVmIdFromHostId(host_id => $args{host}->getAttr(name => "host_id"));
    
    my $command = $self->_oneadmin_command(command => "onevm livemigrate $host_id $hypervisor_id");
    my $result = $masternode_econtext->execute(command => $command);
    
    return $self->_getEntity()->migrateHost(%args);
}

# execute memory scale in
sub scale_memory {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ 'host', 'memory_quantity', 'hypervisor_cluster' ]);

    my $memory_quantity = $args{memory_quantity};
    # instanciate opennebula master node econtext 
    my $masternodeip = $args{hypervisor_cluster}->getMasterNodeIp();
    my $masternode_econtext = EFactory::newEContext(ip_source => '127.0.0.1', ip_destination => $masternodeip);
    my $host_id = $self->_getEntity()->getVmIdFromHostId(host_id => $args{host}->getAttr(name => "host_id")); 
    my $command = $self->_oneadmin_command(command => "onevm memset $host_id $memory_quantity");
    my $result = $masternode_econtext->execute(command => $command);
    return $self->_getEntity()->scale_memory(%args);
       
}

#execute cpu scale in
sub scale_cpu {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ 'host', 'cpu_number', 'hypervisor_cluster' ]);
    my $cpu_number= $args{cpu_number};
    # instanciate opennebula master node econtext 
    my $masternodeip = $args{hypervisor_cluster}->getMasterNodeIp();
    my $masternode_econtext = EFactory::newEContext(ip_source => '127.0.0.1', ip_destination => $masternodeip);
    my $host_id = $self->_getEntity()->getVmIdFromHostId(host_id => $args{host}->getAttr(name => "host_id"));
    my $command = $self->_oneadmin_command(command => "onevm cpuset $host_id $cpu_number");
    my $result = $masternode_econtext->execute(command => $command);
    
    return $self->_getEntity()->scale_cpu(%args);
}

# generate $ONE_LOCATION/etc/oned.conf configuration file
sub generateOnedConf {
     my $self = shift;
    my %args = @_;
    
    General::checkParams(args => \%args, required => [ 'econtext', 'mount_point' ]);
    
    my $data = $self->_getEntity()->getTemplateDataOned();
    $self->generateFile(
            econtext => $args{econtext},
         mount_point => $args{mount_point},
        template_dir => "/templates/components/opennebula",
          input_file => "oned.conf.tt",
              output => "/one/oned.conf", 
                data => $data
    );          
}

# generate /etc/default/libvirt-bin configuration file
sub generateLibvirtbin {
    my $self = shift;
    my %args = @_;
    
    General::checkParams(args => \%args, required => ['econtext', 'mount_point']);
    
    my $data = $self->_getEntity()->getTemplateDataLibvirtbin();
    $self->generateFile(
            econtext => $args{econtext}, 
         mount_point => $args{mount_point},
        template_dir => "/templates/components/opennebula",
          input_file => "libvirt-bin.tt", 
              output => "/default/libvirt-bin", 
                data => $data
    );            
}

# generate /etc/libvirt/libvirtd.conf configuration file
sub generateLibvirtdconf {
    my $self = shift;
    my %args = @_;
    
    General::checkParams(args => \%args, required => ['econtext', 'mount_point', 'host']);
    
    my $data = $self->_getEntity()->getTemplateDataLibvirtd();
    $data->{listen_ip_address} = $args{host}->getInternalIP()->{ipv4_internal_address};
    $self->generateFile(
            econtext => $args{econtext},
         mount_point => $args{mount_point},
        template_dir => "/templates/components/opennebula",
          input_file => "libvirtd.conf.tt", 
              output => "/libvirt/libvirtd.conf",
                data => $data
    );            
}

# generate /etc/libvirt/qemu.conf configuration file
sub generateQemuconf {
    my $self = shift;
    my %args = @_;
    
    General::checkParams(args => \%args, required => ['econtext', 'mount_point', 'host']);
    
    my $data = {};
    $self->generateFile(
            econtext => $args{econtext}, 
         mount_point => $args{mount_point},
        template_dir => "/templates/components/opennebula",
          input_file => "qemu.conf.tt", 
              output => "/libvirt/qemu.conf", 
                data => $data
    ); 
}

# generate /etc/xen/xend-config.sxp configuration file
sub generateXenconf {
    my $self = shift;
    my %args = @_;
    
    General::checkParams(args => \%args, required => ['econtext', 'mount_point', 'host']);
    
    # TODO recup de l'interface pour les vms
    my $data = {
             vmiface => 'eth1', 
        min_mem_dom0 => '1024'
    };
    
    $self->generateFile( 
            econtext => $args{econtext}, 
         mount_point => $args{mount_point},
        template_dir => "/templates/components/opennebula",
          input_file => "xend-config.sxp.tt",
              output => "/xen/xend-config.sxp",
                data => $data
    ); 
}

sub generatemultivlanconf {
    my $self = shift;
    my %args = @_;
    
    General::checkParams(args => \%args, required => ['econtext', 'mount_point', 'host']);
    
    my $data = {};
    $self->generateFile( 
            econtext => $args{econtext}, 
         mount_point => $args{mount_point},
        template_dir => "/templates/components/opennebula",
          input_file => "network-multi-vlan.tt", 
              output => "/etc/xen/scripts/network-multi-vlan", 
                data => $data
    ); 
}

sub generatevlanconf {
    my $self = shift;
    my %args = @_;
    
    General::checkParams(args => \%args, required => ['econtext', 'mount_point', 'host' ]);
    
    my $data = {};
    $self->generateFile(
            econtext => $args{econtext}, 
         mount_point => $args{mount_point},
        template_dir => "/templates/components/opennebula",
          input_file => "network-bridge-vlan.tt", 
              output => "/etc/xen/scripts/network-bridge-vlan", 
                data => $data
    ); 
}

sub addNode {
    my $self = shift;
    my %args = @_;
    
    General::checkParams(args => \%args, required => ['econtext', 'host', 'mount_point', 'cluster' ]);
    $self->configureNode(%args);    
}

sub postStartNode {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ 'cluster', 'host', 'econtext' ]);

    my $masternodeip = $args{cluster}->getMasterNodeIp();
    my $nodeip = $args{host}->getInternalIP()->{ipv4_internal_address};

    #if(not $masternodeip eq $nodeip) {
        # this host is a new hypervisor node so we declare it to opennebula
        my $hostname = $args{host}->getAttr(name => 'host_hostname');
        my $command = $self->_oneadmin_command(command => "onehost create $hostname im_xen vmm_xen tm_shared dummy");
        my $masternode_econtext = EFactory::newEContext(ip_source      => $args{econtext}->getLocalIp,
                                                        ip_destination => $masternodeip);

        sleep(10);
        my $result = $masternode_econtext->execute(command => $command);
        my $id = substr($result->{stdout}, 4);

        $log->info('hypervisor id returned by opennebula: '.$id);
        $self->_getEntity()->addHypervisor(
            host_id => $args{host}->getAttr(name => 'host_id'),
            id		=> $id,
        );
    #}
}

sub preStopNode {
     my $self = shift;
     my %args = @_;

     General::checkParams(args => \%args, required => ['cluster', 'host', 'econtext']);

     my $masternodeip = $args{cluster}->getMasterNodeIp();

     my $id = $self->_getEntity()->getHypervisorIdFromHostId(host_id => $args{host}->getAttr(name => 'host_id'));
     my $command = $self->_oneadmin_command(command => "onehost delete $id");

     my $masternode_econtext = EFactory::newEContext(ip_source      => $args{econtext}->getLocalIp,
                                                     ip_destination => $masternodeip);

     sleep(10);
     my $result = $masternode_econtext->execute(command => $command);
     # TODO verifier le succes de la commande
     $self->_getEntity()->removeHypervisor(host_id => $args{host}->getAttr(name => 'host_id'));
     
}

sub isUp {
    my $self = shift;
    my %args = @_;
    
    General::checkParams( args => \%args, required => ['cluster', 'host', 'host_econtext'] );
    my $ip = $args{host}->getInternalIP()->{ipv4_internal_address};
    
    if($args{cluster}->getMasterNodeIp() eq $ip) {
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
        return 1;          
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
        return 1;
    }   
}

# generate vm template and start a vm from the template
sub startHost {
	my $self = shift;
	my %args = @_;

	General::checkParams(args => \%args, required => [ 'host', 'econtext' ]);

	# instanciate opennebula master node econtext 
    my $masternodeip = $args{host}->getServiceProvider->getMasterNodeIp();
    my $masternode_econtext = EFactory::newEContext(ip_source      => $args{econtext}->getLocalIp,
                                                    ip_destination => $masternodeip);

	# generate template in opennebula master node
	my $template = $self->_generateVmTemplate(
		econtext => $masternode_econtext,
		host	 => $args{host},
	);

	# create the vm from template
	my $command = $self->_oneadmin_command(command => "onevm create $template");
	my $result = $masternode_econtext->execute(command => $command);

	# declare vm in database
	my $id = substr($result->{stdout}, 4);
    $log->info('vm id returned by opennebula: '.$id);
    $self->_getEntity()->addVm(
		host_id => $args{host}->getAttr(name => 'host_id'),
		id		=> $id,
	);
}

# delete a vm from opennebula
sub stopHost {
	my $self = shift;
	my %args = @_;

	General::checkParams(args => \%args, required => [ 'host', 'econtext' ]);
	
	# instanciate opennebula master node econtext 
    my $masternodeip = $args{host}->getServiceProvider->getMasterNodeIp();
    my $masternode_econtext = EFactory::newEContext(ip_source => $args{econtext}->getLocalIp,
                                                    ip_destination => $masternodeip);
	
	# retrieve vm info from opennebula
	
	my $id = $self->_getEntity()->getVmIdFromHostId(host_id => $args{host}->getAttr(name => 'host_id'));
	my $command = $self->_oneadmin_command(command => "onevm delete $id");
	my $result = $masternode_econtext->execute(command => $command);

    # In the case of OpenNebula, we delete the host once it's stopped
    $args{host}->remove;
}

# update a vm information (hypervisor host and vnc port)
sub postStart {
	my $self = shift;
	my %args = @_;

	General::checkParams(args => \%args, required => [ 'host', 'econtext' ]);

	# instanciate opennebula master node econtext 
	my $masternodeip = $args{host}->getServiceProvider->getMasterNodeIp();

	my $masternode_econtext = EFactory::newEContext(ip_source      => $args{econtext}->getLocalIp,
                                                    ip_destination => $masternodeip);
	
	# retrieve hypervisor hostname for the vm from opennebula
	my $id = $self->_getEntity()->getVmIdFromHostId(host_id => $args{host}->getAttr(name => 'host_id'));
	my $command = $self->_oneadmin_command(command => "onevm show $id --xml");
	my $result = $masternode_econtext->execute(command => $command);
	my $hxml = XMLin($result->{stdout});
	my $hypervisor_hostname = $hxml->{HISTORY_RECORDS}->{HISTORY}->{HOSTNAME};
	my $vnc_port = $hxml->{TEMPLATE}->{GRAPHICS}->{PORT};
	
	# retrieve hypervisor id from his hostname
	$command = $self->_oneadmin_command(command => "onehost show $hypervisor_hostname --xml");
	$result = $masternode_econtext->execute(command => $command);
	$hxml = XMLin($result->{stdout});
	
	$self->_getEntity()->updateVm( 
		vm_host_id    => $args{host}->getAttr(name => 'host_id'),
		hypervisor_id => $hxml->{ID},
		vnc_port      => $vnc_port,
	);
	
}

sub getFreeHost {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ "ram", "cpu" ]);

    if ($args{ram_unit}) {
        $args{ram} = General::convertToBytes(value => $args{ram}, units => $args{ram_unit});
        delete $args{ram_unit};
    }

    $log->info("Looking for a virtual host");
    my $host = eval{ 
        return $self->_getEntity->createVirtualHost(
                   core => $args{cpu},
                   ram  => $args{ram},
               );
    };
    if ($@) {
        my $error =$@;
        # We can't create virtual host for some reasons (e.g can't meet constraints)
        $log->debug("Component OpenNebula3 <" . $self->_getEntity->getAttr(name => 'component_id') .
                    "> No capabilities to host this vm core <$args{cpu}> and ram <$args{ram}>:\n" . $error);
    }
    return $host;
}

# generate vm template and push it on opennebula master node
sub _generateVmTemplate {
	my $self = shift;
	my %args = @_;
	General::checkParams(args => \%args, required => ['econtext', 'host']);
	
	# host_ram is stored in octect, so we convert it to megaoctect
	my $ram = General::convertFromBytes(
		value => $args{host}->getAttr(name => 'host_ram'),
		units => 'M'
	);

    my $cluster = Entity->get(id => $args{host}->getClusterId());
    my $tmp = $cluster->getManagerParameters(manager_type => 'disk_manager');
    my %repo = $self->_getEntity()->getImageRepository(container_access_id => $tmp->{container_access_id});
	my $repository_name = $repo{repository_name};
    my $repository_path = $self->_getEntity()->getAttr(name => 'image_repository_path');
    $repository_path .= '/'.$repository_name;
    
    my $image = $args{host}->getNodeSystemimage();
    my $image_name = $image->getAttr(name => 'systemimage_name').'.img';
    
    $log->debug("IMAGE PATH FOR VM TEMPLATE:$repository_path");
    
    my $data = {
              name => $args{host}->getAttr(name => 'host_hostname'),
            memory => $ram,
               cpu => $args{host}->getAttr(name => 'host_core'),
		kernelpath => $repository_path.'/vmlinuz-3.2.6-xenvm',
        initrdpath => $repository_path.'/initrd.img-3.2.6-xenvm',
         imagepath => $repository_path.'/'.$image_name,
        interfaces => []
	};
    
    for my $iface ($args{host}->getIfaces()) {
        my $tmp = {
            mac => $iface->{iface_mac_addr}
        };
        push @{$data->{interfaces}}, $tmp;
    }

	$self->generateFile( econtext     => $args{econtext}, 
						 mount_point  => '',
                         template_dir => "/templates/components/opennebula",
                         input_file   => "vm.tt", 
                         output       => "/tmp/vm.template", 
                         data         => $data
    );
    return "/tmp/vm.template";
}

# prefix commands to use oneadmin account with its environment variables
sub _oneadmin_command {
	my $self = shift;
	my %args = @_;
	General::checkParams(args => \%args, required => ['command']);
	
	my $config = $self->_getEntity()->getConf();
	my $command = "su oneadmin -c '";
    #$command .= "export ONE_XMLRPC=http://localhost:$config->{port}/RPC2 ; ";
	#$command .= "export ONE_LOCATION=$config->{install_dir} ; ";
	#$command .= "export ONE_AUTH=\$ONE_LOCATION/one_auth ; ";
	#$command .= "PATH=\$ONE_LOCATION/bin:\$PATH ; ";
	$command .= $args{command} ."'";
	return $command;
}

1;

#    Copyright © 2013 Hedera Technology SAS
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

=pod

=begin classdoc

EEntity for the OpenStack host manager

=end classdoc

=cut

package EEntity::EComponent::EVirtualization::ENovaController;

use base "EEntity::EComponent";
use base "EManager::EHostManager::EVirtualMachineManager";

use strict;
use warnings;

use JSON;
use General;
use OpenStack::API;
use NetAddr::IP;
use Data::Dumper;
use IO::Handle;
use File::Temp qw/ tempfile /;

use Log::Log4perl "get_logger";
my $log = get_logger("");

sub api {
    my $self = shift;

    my $credentials = {
        auth => {
            passwordCredentials => {
                username    => "admin",
                password    => "keystone"
            },
            tenantName      => "openstack"
        }
    };

    my $keystone = $self->keystone;
    my $config = {
        verify_ssl => 0,
        identity => {
            url     => 'http://' . $keystone->getMasterNode->fqdn . ':5000/v2.0'
        },
    };

    return OpenStack::API->new(credentials => $credentials,
                               config      => $config);
}

sub addNode {
    my ($self, %args) = @_;

    General::checkParams(
        args     => \%args,
        required => [ 'host', 'mount_point', 'cluster' ]
    );
}

sub postStartNode {
    my ($self, %args) = @_;
    
    General::checkParams(args => \%args, required => [ 'cluster', 'host' ]);

    eval {
        my $api = $self->api;
        my $route = 'os-security-groups';
        my $resp = $api->compute->$route->get();
        my $group = $resp->{security_groups}->[0]->{id};

        $route = 'os-security-group-rules';
        $api->compute->$route->post(
            content => {
                security_group_rule => {
                    from_port       => 1,
                    to_port         => 65535,
                    ip_protocol     => "tcp",
                    cidr            => "0.0.0.0/0",
                    parent_group_id => $group,
                    group_id        => undef
                }
            }
        );

        $api->compute->$route->post(
            content => {
                security_group_rule => {
                    from_port       => 1,
                    to_port         => 65535,
                    ip_protocol     => "udp",
                    cidr            => "0.0.0.0/0",
                    parent_group_id => $group,
                    group_id        => undef
                }
            }
        );

        $api->compute->$route->post(
            content => {
                security_group_rule => {
                    from_port       => -1,
                    to_port         => -1,
                    ip_protocol     => "icmp",
                    cidr            => "0.0.0.0/0",
                    parent_group_id => $group,
                    group_id        => undef
                }
            }
        );
    };
}

sub registerHypervisor {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host' ]);

    return $self->addHypervisor(host => $args{host}->_entity);
}

sub unregisterHypervisor {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host' ]);

    return $self->removeHypervisor(host => $args{host}->_entity);
}

=pod

=begin classdoc

Migrate an openstack vm from one hypervisor to another

@params host the vm to migrate
@params hypervisor_dst the destination hypervisor

=end classdoc

=cut

sub migrateHost {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host', 'hypervisor_dst' ]);

    my $host = $args{host};
    my $hv   = $args{hypervisor_dst};
    my $uuid = $host->openstack_vm_uuid;
    my $api  = $self->api;

    $log->info('migrating host <' . $host->id . '> on hypervisor < ' . $hv->id . '>');

    $api->compute->servers(id => $uuid)->action->post(
        content => {
            'os-migrateLive'  => {
                disk_over_commit => JSON::false,
                block_migration  => JSON::false,
                host             => $hv->node->node_hostname,
            }
        }
    );
}


=pod

=begin classdoc

Get all the vms of an hypervisor

@param host hypervisor

=end classdoc

=cut

sub getHypervisorVMs {
    my ($self, %args) = @_;

    if (! defined $args{host_id}) {
        General::checkParams(args => \%args, required => [ 'host' ]);
    }
    else {
        $args{host} = Entity::Host->get(id => $args{host_id});
        delete $args{host_id};
    }

    my $host = $args{host};

    my $route = 'os-hypervisors';
    my $hostname = $host->node->node_hostname;
    my $details = $self->api->compute->$route->$hostname
                       ->servers->get->{hypervisors};

    my @vms;
    my @vm_ids;
    my @unk_vm_uuids;

    my @uuids = (defined $details->[0]->{servers}) ? @{$details->[0]->{servers}} : ();

    for my $uuid (@uuids){
        eval {
            my $e = Entity::Host::VirtualMachine::OpenstackVm->find(hash => {openstack_vm_uuid => $uuid->{uuid}});
            push @vms, $e;
            push @vm_ids, $e->id;
        };
        if ($@) {
            my $error = $@;
            $log->info($uuid->{uuid}." => ".$error);
            push @unk_vm_uuids, $uuid->{uuid};
        }
    }

    return {
        vm_ids       => \@vm_ids,
        vms          => \@vms,
        unk_vm_uuids => \@unk_vm_uuids,
    };
}


=pod

=begin classdoc

Get the detail of a vm

@params host vm

=end classdoc

=cut

sub getVMDetails {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host' ]);

    my $host = $args{host};
    my $uuid = $host->openstack_vm_uuid;

    my $details =  $self->api->compute->servers(id => $uuid)->get;

    if (defined $details->{'itemNotFound'}) {
        throw Kanopya::Exception(error => "VM <".$args{host}->id."> not found in infrastructure");
    }

    return {
        state      => $details->{server}->{status},
        hypervisor => $details->{server}->{'OS-EXT-SRV-ATTR:host'},
    };
}


=pod

=begin classdoc

Retrieve the state of a given VM

@return state

=end classdoc

=cut

sub getVMState {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host' ]);

    eval {
        my $details =  $self->getVMDetails(%args);

        my $state_map = {
            'MIGRATING' => 'migr',
            'BUILD'     => 'pend',
            'REBUILD'   => 'pend',
            'ACTIVE'    => 'runn',
            'ERROR'     => 'fail',
            'SHUTOFF'   => 'shut'
        };
    
        return {
            state      => $state_map->{$details->{state}} || 'fail',
            hypervisor => $details->{hypervisor},
        };
    }
}

=pod

=begin clasddoc

Scale up or down the RAM of a given host

=end classdoc

=cut

sub scaleMemory {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host', 'memory' ]);

    $self->_scaleHost(host => $args{host}, memory => $args{memory});
}

=pod

=begin classdoc

Scale up or down the number of CPU of a given host

=end classdoc

=cut

sub scaleCpu {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host', 'cpu_number' ]);

    $self->_scaleHost(host => $args{host}, cpu_number => $args{cpu_number});
}

=pod

=begin classdoc

Terminate a host

=end classdoc

=cut

sub halt {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host' ]);
    my $uuid = $args{host}->openstack_vm_uuid;
    my $api = $self->api;

    $api->compute->servers(id => $uuid)->action->post(
        content => { 'os-stop' => undef }
    );
}

=pod

=begin classdoc

Determine whether a host is up or down

=end classdoc

=cut

sub isUp {
    my ($self, %args) = @_;

    General::checkParams(
        args     => \%args,
        required => [ 'cluster', 'host' ]
    );

    return 1;
}

=pod

=begin classdoc

Start a new server on an OpenStack compute service, and register it into Kanopya

@return

=end classdoc

=cut

sub startHost {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ 'host', 'cluster' ]);

    if (! defined $args{hypervisor}) {
        throw Kanopya::Exception::Internal(error => "No hypervisor available");
    }

    my $api = $self->api;
    my $image_id;
    my $diskless = $args{cluster}->cluster_boot_policy ne Manager::HostManager->BOOT_POLICIES->{virtual_disk};

    if (not $diskless) {
        # Register system image
        $image_id = $self->registerSystemImage(host    => $args{host},
                                               cluster => $args{cluster});
    }
    else {
        $image_id = $self->registerPXEImage();
    }

    my $flavor = $api->compute->flavors(id => $args{cluster}->id)
                     ->get->{flavor};

    if ($flavor->{id}) {
        $api->compute->flavors(id => $flavor->{id})->delete;
    }

    $flavor = $api->compute->flavors->post(
        content => {
            flavor => {
                'name'                        => 'flavor_' . $args{host}->node->node_hostname,
                'ram'                         => $args{host}->host_ram / 1024 / 1024,
                'vcpus'                       => $args{host}->host_core,
                'id'                          => $args{cluster}->id,
                'swap'                        => 0,
                'os-flavor-access:is_public'  => JSON::true,
                'rxtx_factor'                 => 1,
                'OS-FLV-EXT-DATA:ephemeral'   => 0,
                'disk'                        => $diskless ?
                                                 0 : $args{host}->getNodeSystemimage
                                                                ->getContainer->container_size / 1024 / 1024
            },
        }
    );

    $log->debug("Nova returned " . (Dumper $flavor));

    # register network
    my $interfaces = $self->registerNetwork(host => $args{host});
    my $ports;
    for my $interface (@$interfaces) {
        push @$ports, {
            port => $interface->{port}
        };
    }

    my $disk_manager = $args{cluster}->getManager(manager_type => 'DiskManager');
    my $isCinder     = 0;
    my $volume       = undef;
    my $apiRoute     = $api->compute->servers;
    if ($disk_manager->isa('Entity::Component::Openstack::Cinder')) {
        $isCinder    = 1;
        my $volumeId = $disk_manager->getVolumeId(container => $args{host}->getNodeSystemimage->getContainer);
        $volume      = [
            {
                volume_size           => '',
                volume_id             => $volumeId,
                delete_on_termination => 0,
                device_name           => 'vda'
            }
        ];
        my $route    = 'os-volumes_boot';
        $apiRoute    = $api->compute->$route;
    }
    # create VM
    my $response = $apiRoute->post(
        content => {
            server => {
                availability_zone => 'nova:' . $args{hypervisor}->node->node_hostname,
                flavorRef         => $flavor->{flavor}->{id},
                name              => $args{host}->node->node_hostname,
                networks          => $ports,
                imageRef          => $image_id,
                $isCinder ? ('block_device_mapping', $volume) : ()
            }
        }
    );

    $log->debug("Nova returned : " . (Dumper $response));

    $args{host} = Entity::Host::VirtualMachine::OpenstackVm->promote(
                      promoted           => $args{host}->_entity,
                      nova_controller_id => $self->id,
                      openstack_vm_uuid  => $response->{server}->{id},
                      hypervisor_id      => $args{hypervisor}->id
                  );

    $args{host}->hypervisor_id($args{hypervisor}->id);
}

=pod

=begin classdoc

Upload a system image to Glance

@return $response->{image}->{id}  the id of the uploaded image

=end classdoc

=cut

sub registerSystemImage {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host', 'cluster' ]);

    my $image = $args{host}->getNodeSystemimage();
    my $disk_params = $args{cluster}->getManagerParameters(manager_type => 'DiskManager');
    my $image_name = $image->systemimage_name;
    my $image_type = $disk_params->{image_type};

    my $econtext = $self->_host->getEContext;
    my $container_access = $image->getContainer->container_access;
    my $mount_point = EEntity->new(entity => $container_access)->mount(econtext => $econtext);

    my $image_source = $mount_point . '/' . $image->getContainer->container_device;
    my $image_container_format = 'bare'; # bare => no container or metadata envelope for the image
    my $image_is_public = 'True'; # accessible by all tenants

    my $response = $self->api->glance->images->post(
        headers         => {
            'x-image-meta-name'             => $image_name,
            'x-image-meta-disk_format'      => $image_type,
            'x-image-meta-container_format' => $image_container_format,
            'x-image-meta-is_public'        => $image_is_public
        },
        content         => $image_source,
        content_type    => 'application/octet-stream'
    );

    $log->debug("Glance returned : " . (Dumper $response));

    EEntity->new(entity => $container_access)->umount(econtext => $econtext);

    return $response->{image}->{id};
}

=pod

=begin classdoc

Return the image to use for PXE boot.
If the PXE boot does not exist in Glance, register an empty one

@return $response->{image}->{id}  the id of the uploaded image

=end classdoc

=cut

sub registerPXEImage {
    my ($self, %args) = @_;

    my $images = $self->api->glance->images->get->{images};
    my ($pxe_image) = grep { $_->{name} eq "__PXE__" } @{$images};

    if (!$pxe_image) {
        my ($fh, $filename) = tempfile(UNLINK => 1);
        print $fh " " x 512;
        $fh->autoflush();

        my $response = $self->api->glance->images->post(
            headers         => {
                'x-image-meta-name'             => '__PXE__',
                'x-image-meta-disk_format'      => 'raw',
                'x-image-meta-container_format' => 'bare',
                'x-image-meta-is_public'        => 'True'
            },
            content         => $filename,
            content_type    => 'application/octet-stream'
        );

        $log->debug("Glance returned : " . (Dumper $response));
        $pxe_image = $response->{image};
    }

    return $pxe_image->{id};
}

=pod

=begin classdoc

Register a network to Quantum

@param $host host whose netconf to be registered

@returnlist list of created networks

=end classdoc

=cut

sub registerNetwork {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host' ]);

    my $host = $args{host};
    my $api = $self->api;

    my $interfaces = [];
    IFACE:
    for my $iface ($args{host}->getIfaces()) {
        # skip ifaces with no ip address
        eval{
            $iface->getIPAddr();
        };
        next IFACE if ($@);

        # get iface vlan
        my $vlan = undef;
        my @vlans = $iface->getVlans();
        if (scalar @vlans) {
            $vlan = pop @vlans;
        }

        my $network_id = $self->_getOrRegisterNetwork(vlan => $vlan);
        my $subnet_id = $self->_getOrRegisterSubnet(
            host        => $host,
            iface       => $iface,
            network_id  => $network_id
        );
        # create port to assign IP address
        my $port_id = $self->_registerPort(
            host        => $host,
            iface       => $iface,
            network_id  => $network_id,
            subnet_id   => $subnet_id
        );

        push @$interfaces, {
            mac     => $iface->iface_mac_addr,
            network => $host->node->node_hostname . '-' . $iface->iface_name,
            port    => $port_id
        };
    }

    return $interfaces;
}

sub stopHost {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ 'host' ]);

    my $host = $args{host};
    my $api = $self->api;
    my $uuid = $host->openstack_vm_uuid;

    # get image id from openstack
    my $image_id = $api->compute->servers(id => $uuid)->get->{server}->{image}->{id};

    # delete image : set 'protected' attribute to false, then delete image
    $api->glance->images(id => $image_id)->put(
        headers => { 'x-image-meta-protected' => 'False' }
    );
    $api->glance->images(id => $image_id)->delete;

    # delete vm
    $api->compute->servers(id => $uuid)->delete;
}


sub releaseHost {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ "host" ]);

    # In the case of OpenNebula, we delete the host once it's stopped
    $args{host}->setAttr(name => 'active', value => '0', save => 1);
    $args{host}->remove;
}


sub postStart {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host' ]);
}

=pod

=begin classdoc

Resubmit a node in an OpenStack IAAS : set vm's state to active, then rebuild vm

@param $vm virtual machine to resubmit
@param $hypervisor hypervisor on which vm will be placed

=end classdoc

=cut

sub resubmitNode {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => ['vm', 'hypervisor']);

    my $vm = $args{vm};
    my $uuid = $vm->openstack_vm_uuid;
    my $vm_name = $vm->node->node_hostname;
    my $api = $self->api;

    # NOTE
    #   - resubmit => state to active
    #   - deploy => rebuild
    #   - hypervisor is not used since rebuild is done on same host
    #   - nova evacuate has not been used for vm because it requires an hypervisor down

    # set vm's state to active (state required prior a rebuild)
    $api->compute->servers(id => $uuid)->action->post(
        content => {
            'os-resetState' => {
                'state' => 'active'
            }
        }
    );

    # rebuild vm (host expected to be up)
    my $image_id = $api->compute->servers(id => $uuid)->get->{server}->{image}->{id};

    my $response = $api->compute->servers(id => $uuid)->action->post(
        content => {
            'rebuild' => {
                'name'     => $vm_name,
                'imageRef' => $image_id,
            }
        }
    );

    $log->debug('Rebuild VM <' . $vm_name . '>. Compute response : '
        . (Dumper $response));
}

=pod

=begin classdoc

Get last message logged by a vm

@param $vm virtual machine whose logs are wanted

@return $lastmessage last message logged by vm

=end classdoc

=cut

sub vmLoggedErrorMessage {
    my ($self,%args) = @_;

    General::checkParams(args => \%args, required => [ 'vm' ]);

    my $vm = $args{vm};
    my $instance_name = $self->_getInstanceName(vm => $vm);
    my $e_hypervisor = EEntity->new(entity => $vm->hypervisor);
    my $command = 'tail -n 10 /var/log/libvirt/qemu/'. $instance_name . '.log';

    $log->debug("commande = $command");

    my $result  = $e_hypervisor->getEContext->execute(command => $command);
    my $output  = $result->{stdout};
    $log->debug($output);

    my @lastmessage = split '\n', $output;

    $log->debug(@lastmessage);

    return $lastmessage[-1];
}

sub applyVLAN {
    my ($self, %args) = @_;

    General::checkParams(
        args     => \%args,
        required => [ 'iface', 'vlan' ]
    );
}

=pod

=begin classdoc

Get name of an instance (vm) from nova compute's view

@param $vm virtual machine's name

@return $instance_name instance's name

=end classdoc

=cut

sub _getInstanceName {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'vm' ]);

    my $uuid = $args{vm}->openstack_vm_uuid;
    my $api = $self->api;

    my $instance_name = $api->compute->servers(id => $uuid)->get
                            ->{server}->{'OS-EXT-SRV-ATTR:instance_name'};

    return $instance_name;
}

=pod

=begin classdoc

Search for an openstack network registered (for a flat or a specific vlan network) and create it not found

@param $hostname name of node whose netconf must be registered
@optional $vlan vlan of iface

@return ID of openstack network found/created

=end classdoc

=cut

sub _getOrRegisterNetwork {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, optional => { vlan => undef });
    my $vlan = $args{vlan};

    my $api = $self->api;
    my $network_id = undef;
    my $networks = $api->quantum->networks->get;
    if (defined $vlan) { # check if a network has already been created for physical vlan interface
        VLAN:
        for my $network (@{ $networks->{networks} }) {
            if ($network->{'provider:segmentation_id'} == $vlan->vlan_number) {
                $network_id = $network->{id};
                last VLAN;
            }
        }
    }
    else { # check if a network has already been created for physical flat (no vlan) interface
        NETWORK:
        for my $network (@{ $networks->{networks} }) {
            if ( not defined $network->{'provider:segmentation_id'} ) { # no vlan network
                $network_id = $network->{id};
                last NETWORK;
            }
        }
    }

    # create a network if no network found
    if (not defined $network_id) {
         my $network_conf = {
            'network' => {
                'name' => defined $vlan ? 'network-vlan' . $vlan->vlan_number : 'network-flat',
                'admin_state_up' => JSON::true,
                'provider:network_type' => defined $vlan ? 'vlan' : 'flat',
                'provider:physical_network' => defined $vlan ? 'physnetvlan' : 'physnetflat',# mappings for bridge interfaces
            }
        };
        $network_conf->{network}->{'provider:segmentation_id'} = $vlan->vlan_number if (defined $vlan);
        $network_id = $api->quantum->networks->post(
            content => $network_conf
        )->{network}->{id};
    }

    return $network_id;
}

=pod

=begin classdoc

Search for an openstack subnet registered (for a flat or a specific vlan network) and create it not found

@param $hostname name of node whose netconf must be registered
@param $iface iface to be registered
@param $network_id ID of network on which subnet will be created

@return ID of openstack subnet found/created

=end classdoc

=cut

sub _getOrRegisterSubnet {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host', 'iface', 'network_id' ]);
    my $cluster_name = $args{host}->node->service_provider->cluster_name;
    my $iface = $args{iface};
    my $network_id = $args{network_id};

    my $api = $self->api;
    my $poolip = $iface->getPoolip();
    my $network_addr = NetAddr::IP->new($poolip->network->network_addr,
                                        $poolip->network->network_netmask);

    # check if kanopya.network already registered in openstack.subnet (for openstack.network previously created)
    my $subnet_id = undef;
    my $subnets = $api->quantum->subnets(filter => "network-id=$network_id")->get;
    SUBNET:
    for my $subnet ( @{$subnets->{subnets}} ) {
        if ( $subnet->{'cidr'} eq $network_addr->cidr() ) { # network already registered
            $subnet_id = $subnet->{id};
            last SUBNET;
        }
    }

    # create a new subnet if no subnet found
    # one allocation_pool is created with all ip usable
    if (not defined $subnet_id) {
        $subnet_id = $api->quantum->subnets->post(
            content => {
                'subnet' => {
                    'name'              => $cluster_name . '-subnet',
                    'network_id'        => $network_id,
                    'ip_version'        => 4,
                    'cidr'              => $network_addr->cidr(),
                    'allocation_pools'  => [
                        {
                            start   => ($network_addr->first() + 1)->addr(),
                            end     => $network_addr->last()->addr()
                        },
                    ]
                }
            }
        )->{subnet}->{id};
    }

    return $subnet_id;
}

=pod

=begin classdoc

Register a port in OpenStack

@param $hostname name of node whose netconf must be registered
@param $iface iface to be registered
@param $network_id ID of network on which subnet will be created
@param $subnet_id ID of subnet on which port will be created

@return ID of port created

=end classdoc

=cut

sub _registerPort {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host', 'iface', 'network_id', 'subnet_id' ]);
    my $hostname    = $args{host}->node->node_hostname;
    my $iface       = $args{iface};
    my $network_id  = $args{network_id};
    my $subnet_id   = $args{subnet_id};

    my $api = $self->api;

    my $port_id = $api->quantum->ports->post(
        content => {
            'port' => {
                'name'          => $hostname . '-' . $iface->iface_name,
                'mac_address'   => $iface->iface_mac_addr,
                'fixed_ips'     => [
                    {
                        "ip_address"    => $iface->getIPAddr(),
                        "subnet_id"     => $subnet_id,
                    }
                ],
                'network_id'    => $network_id,
            }
        }
    )->{port}->{id};

    return $port_id;
}

=pod

=begin classdoc

Register a new flavor
@return the flavor id

=end classdoc

=cut

sub registerFlavor {
    my ($self, %args) = @_;

    General::checkParams(
        args => \%args,
        required => [ 'name', 'ram', 'vcpus', 'disk', 'id' ]
    );

    my $api = $self->api;
    my $id = $api->compute->flavors->post(
        content => {
            flavor => {
                'name'                        => $args{name},
                'ram'                         => $args{ram},
                'vcpus'                       => $args{vcpus},
                'disk'                        => $args{disk},
                'id'                          => $args{id},
                'swap'                        => 0,
                'os-flavor-access:is_public'  => JSON::true,
                'rxtx_factor'                 => 1,
                'OS-FLV-EXT-DATA:ephemeral'   => 0
            }
        }
    )->{flavor}->{id};
    return $id;
}


=pod

=begin classdoc

Generale scaling method (called by scaleCpu or scalememory)
Takes host and new memory / cpu count in parameter
Update host's flavor and resize host on the new flavor

=end classdoc

=cut

sub _scaleHost {
    my ($self, %args) = @_;

    General::checkParams(
        args     => \%args,
        required => [ 'host' ],
        optional => { memory => undef, cpu_number => undef }
    );

    my $api    = $self->api;
    my $node   = $args{host}->node;
    my $uuid   = $args{host}->openstack_vm_uuid;
    my $flavor = $api->compute->servers(id => $uuid)->get->{server}->{flavor};
    $flavor    = $api->compute->flavors(id => $flavor->{id})->get->{flavor};

    my $newFlavor_id = undef;
    if ($flavor->{id} eq $args{host}->id) {
        $api->compute->flavors(id => $flavor->{id})->delete;
        $newFlavor_id = $flavor->{id};
    }
    else {
        $newFlavor_id = $args{host}->id;
    }

    $newFlavor_id = $self->registerFlavor(
        id    => $newFlavor_id,
        name  => $node->node_hostname,
        ram   => (($args{memory} != undef) ? $args{memory} / 1024 / 1024 : $flavor->{ram}),
        vcpus => ($args{cpu_number} or $flavor->{vcpus}),
        disk  => $flavor->{disk}
    );

    # resize vm and confirm it
    $api->compute->servers(id => $uuid)->action->post(
        content => {
            resize  => {
                flavorRef   => $newFlavor_id
            }
        }
    );
    $api->compute->servers(id => $uuid)->action->post(
        content => {
            confirmResize => undef
        }
    );
}


#sub _synchronizeVmHypervisor {
#    my ($self, %args) = @_;
#    General::checkParams(args => \%args, required => [ 'host' ]);
#
#    my $detail;
#    eval {
#        $detail = $self->getVMDetails(host => $args{host});
#    };
#    if ($@) {
#        if (defined $args{host}->node) {
#            $args{host}->node->disable();
#            $args{host}->setNodeState(state => 'broken');
#        }
#        $args{host}->setAttr(name => 'hypervisor_id', value => undef);
#        $args{host}->save();
#        throw Kanopya::Exception(error => "VM <".$args{host}->id."> not found in infrastructure, node as been disabled and considered as broken");
#    }
#
#    my $hypervisor_hostname = $detail->{server}->{'OS-EXT-SRV-ATTR:host'};
#    $log->debug("According to infractructire VM hypervisor is <$hypervisor_hostname>");
#
#    my $hypervisor_id = Node->find(hash => {node_hostname => $hypervisor_hostname})->host->id;
#
#    my $db_hypervisor = $args{host}->hypervisor;
#
#    if (defined $db_hypervisor && ($hypervisor_id == $db_hypervisor->id)) {
#        return;
#    }
#
#    $args{host}->hypervisor_id($hypervisor_id);
#    return;
#}

1;

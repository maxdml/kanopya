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
                password    => "pass"
            },
            tenantName      => "openstack"
        }
    };

    my $keystone = $self->keystone;
    my @glances  = $self->glances;
    my $glance   = shift @glances;
    my @computes = $self->novas_compute;
    my $compute  = shift @computes;
    my @quantums  = $self->quantums;
    my $quantum  = shift @quantums;

    my $config = {
        verify_ssl => 0,
        identity => {
            url     => 'http://' . $keystone->service_provider->getMasterNode->fqdn . ':5000/v2.0'
        },
        image => {
            url     => 'http://' . $glance->service_provider->getMasterNode->fqdn  . ':9292/v1'
        },
        compute => {
            url     => 'http://' . $compute->service_provider->getMasterNode->fqdn . ':8774/v2'
        },
        network => {
            url     => 'http://' . $quantum->service_provider->getMasterNode->fqdn . ':9696/v2.0'
        }
    };

    my $os_api = OpenStack::API->new(
        credentials => $credentials,
        config      => $config,
    );

    return $os_api;
}

sub addNode {
    my ($self, %args) = @_;

    General::checkParams(
        args     => \%args,
        required => [ 'host', 'mount_point', 'cluster' ]
    );
}

sub registerHypervisor {
    my ($self, %args) = @_;

    General::checkParams(
        args     => \%args,
        required => [ 'host' ]
    );
}

sub unregisterHypervisor {
    my ($self, %args) = @_;

    General::checkParams(
        args     => \%args,
        required => [ 'host' ]
    );
}

=pod

=begin classdoc

Migrate an host from one hypervisor to another

=end classdoc

=cut

sub migrateHost {
    my $self = shift;
    my %args = @_;

    General::checkParams(args     => \%args,
                         required => [ 'host', 'hypervisor_dst', 'hypervisor_cluster' ]);
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

    my $host = $args{host};
    my $uuid = $host->openstack_vm_uuid;

    my $details =  $self->api->tenant(id => $self->api->{tenant_id})
                       ->servers(id => $uuid)
                       ->get(target => 'compute');

    return $details->{server}->{status};
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

    if ($args{cluster}->cluster_boot_policy eq Manager::HostManager->BOOT_POLICIES->{virtual_disk}) {
        # Register system image
        $image_id = $self->registerSystemImage(host    => $args{host},
                                               cluster => $args{cluster});
    }
    else {
        $image_id = $self->registerPXEImage();
    }

    my $flavor = $api->tenant(id => $api->{tenant_id})->flavors(id => $args{cluster}->id)
                     ->get(target => 'compute')->{flavor};

    if ($flavor->{id}) {
        $api->tenant(id => $api->{tenant_id})->flavors(id => $flavor->{id})
            ->delete(target => 'compute');
    }

    $flavor = $api->tenant(id => $api->{tenant_id})->flavors->post(
        target  => 'compute',
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
                $image_id ? ("disk", $args{host}->getNodeSystemimage->
                                                  getContainer->container_size / 1024 / 1024) : ()
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

    # create VM
    my $response = $api->tenant(id => $api->{tenant_id})->servers->post(
        target => 'compute',
        content => {
            server => {
                flavorRef   => $flavor->{flavor}->{id},
                name        => $args{host}->node->node_hostname,
                networks    => $ports,
                $image_id ? ("imageRef", $image_id) : ()
            }
        }
    );

    $log->debug("Nova returned : " . (Dumper $response));

    $args{host} = Entity::Host::VirtualMachine::OpenstackVm->promote(
                      promoted           => $args{host}->_getEntity,
                      nova_controller_id => $self->id,
                      openstack_vm_uuid  => $response->{server}->{id},
                      hypervisor_id      => $args{hypervisor}->id
                  );
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

    my $econtext = $self->getExecutorEContext;
    my $container_access = $image->getContainer->container_access;
    my $mount_point = EEntity->new(entity => $container_access)->mount(econtext => $econtext);

    my $image_source = $mount_point . '/' . $image->getContainer->container_device;
    my $image_container_format = 'bare'; # bare => no container or metadata envelope for the image
    my $image_is_public = 'True'; # accessible by all tenants

    my $response = $self->api->images->post(
        target          => 'image',
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

    my $images = $self->api->images->get(target => "image")->{images};
    my ($pxe_image) = grep { $_->{name} eq "__PXE__" } @{$images};

    if (!$pxe_image) {
        my ($fh, $filename) = tempfile(UNLINK => 1);
        print $fh " ";
        $fh->autoflush();

        my $response = $self->api->images->post(
            target          => 'image',
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

    my $api = $self->api;
    my $hostname = $args{host}->node->node_hostname;

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

        my $network_id = $self->_getOrRegisterNetwork(hostname => $hostname, vlan => $vlan);
        my $subnet_id = $self->_getOrRegisterSubnet(
            hostname    => $hostname,
            iface       => $iface,
            network_id  => $network_id
        );
        # create port to assign IP address
        my $port_id = $self->_registerPort(
            hostname    => $hostname,
            iface       => $iface,
            network_id  => $network_id,
            subnet_id   => $subnet_id
        );

        push @$interfaces, {
            mac     => $iface->iface_mac_addr,
            network => $hostname . '-' . $iface->iface_name,
            port    => $port_id
        };
    }

    return $interfaces;
}

sub stopHost {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ 'host' ]);
}

sub postStart {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host' ]);
}

sub postStartNode {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'cluster', 'host' ]);

    # The Puppet manifest is compiled a first time and requests the creation
    # of the database on the database cluster
    $self->SUPER::postStartNode(%args);

    # We ask :
    # - the database cluster to create databases and users
    # - Keystone to create endpoints, users and roles
    # - AMQP to create queues and users
    for my $component ($self->mysql5, $self->amqp, $self->keystone) {
        if ($component) {
            EEntity->new(entity => $component->service_provider)->reconfigure();
        }
    }

    # Now apply the manifest again
    $self->SUPER::postStartNode(%args);
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

Check the state of an OpenStack host

return boolean

=end classdoc

=cut

sub checkUp {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ "host" ]);

    my $host = $args{host};
    my $vm_state = $self->getVMState(host => $host);

    $log->info('VM <' . $host->id . '> openstack status <' . $vm_state . '>');

    if ($vm_state eq 'SHUTOFF') {
        $log->info('vm powered off');
        return 0;
    }
    elsif ($vm_state eq 'BUILD') {
        $log->info('vm is building');
        return 0;
    }
    elsif ($vm_state eq 'ACTIVE') {
        $log->info('vm is active');
        return 2;
    }
    elsif ($vm_state eq 'ERROR') {
        $log->info('vm is in error state');
        return 0;
    }
    elsif ($vm_state eq 'MIGRATING') {
        $log->info('vm is migrating');
        return 0;
    }
    else {
        throw Kanopya::Exception(error => 'unknown state: ' . $vm_state);
    }

    return 0;
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

    General::checkParams(
        args => \%args,
        required => [ 'hostname' ],
        optional => { vlan => undef }
    );
    my $hostname = $args{hostname};
    my $vlan = $args{vlan};

    my $api = $self->api;
    my $network_id = undef;
    my $networks = $api->networks->get(target => 'network');
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
                'name'                      => $hostname . '-network',
                'admin_state_up'            => JSON::true,
                'provider:network_type'     => defined $vlan ? 'vlan' : 'flat',
                'provider:physical_network' => defined $vlan ? 'physnetvlan' : 'physnetflat',# mappings for bridge interfaces
            }
        };
        $network_conf->{network}->{'provider:segmentation_id'} = $vlan->vlan_number if (defined $vlan);
        $network_id = $api->networks->post(
            target  => 'network',
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

    General::checkParams(args => \%args, required => [ 'hostname', 'iface', 'network_id' ]);
    my $hostname = $args{hostname};
    my $iface = $args{iface};
    my $network_id = $args{network_id};

    my $api = $self->api;

    my $poolip = $iface->getPoolip();
    my $network_addr = NetAddr::IP->new($poolip->network->network_addr,
                                      $poolip->network->network_netmask);
    # check if kanopya.network already registered in openstack.subnet (for openstack.network previously created)
    my $subnet_id = undef;
    my $subnets = $api->subnets(filter => "network-id=$network_id")->get(target => 'network');
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
        $subnet_id = $api->subnets->post(
            target  => 'network',
            content => {
                'subnet' => {
                    'name'              => $hostname . '-subnet',
                    'network_id'        => $network_id,
                    'ip_version'        => 4,
                    'cidr'              => $network_addr->cidr(),
                    'gateway_ip'        => $poolip->network->network_gateway,
                    'allocation_pools'  => [
                        {
                            start   => $network_addr->first(),
                            end     => $network_addr->last()
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

    General::checkParams(args => \%args, required => [ 'hostname', 'iface', 'network_id', 'subnet_id' ]);
    my $hostname    = $args{hostname};
    my $iface       = $args{iface};
    my $network_id  = $args{network_id};
    my $subnet_id   = $args{subnet_id};

    my $api = $self->api;

    my $port_id = $api->ports->post(
        target  => 'network',
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
    my $id = $api->tenant(id => $api->{tenant_id})->flavors->post(
        target => 'compute',
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

    my $api          = $self->api;
    my $node         = $args{host}->node;
    my $uuid         = $args{host}->openstack_vm_uuid;
    my $flavor       = $api->tenant(id => $api->{tenant_id})->servers(id => $uuid)->get(target => 'compute')->{server}->{flavor};
    $flavor          = $api->tenant(id => $api->{tenant_id})->flavors(id => $flavor->{id})->get(target => 'compute')->{flavor};

    my $newFlavor_id = undef;
    if ($flavor->{id} eq $args{host}->id) {
        $api->tenant(id => $api->{tenant_id})->flavors(id => $flavor->{id})->delete(target => 'compute');
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
    $api->tenant(id => $api->{tenant_id})->servers(id => $uuid)->action->post(
        target  => 'compute',
        content => {
            resize  => {
                flavorRef   => $newFlavor_id
            }
        }
    );
    $api->tenant(id => $api->{tenant_id})->servers(id => $uuid)->action->post(
        target  => 'compute',
        content => {
            confirmResize => undef
        }
    );
}

1;

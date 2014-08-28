#    Copyright © 2014 Hedera Technology SAS
#
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

# Maintained by Dev Team of Hedera Technology <dev@hederatech.com>.

=pod
=begin classdoc

The OpenStack component is designed to manage an exiting deployment of OpenStack apis.
This component is able to synchronise the existing infrastructure to the HCM api, and load
the available parameters/option for each OpenStack services.

It implements the 3 HCM drivers interfaces VirtualMachineManager, DiskManager, ExportManager.

=end classdoc
=cut

package Entity::Component::Virtualization::OpenStack;
use parent Entity::Component::Virtualization;
use parent Manager::HostManager::VirtualMachineManager;
use parent Manager::StorageManager;
use parent Manager::BootManager;
use parent Manager::NetworkManager;

use strict;
use warnings;
use Hash::Merge;
use Data::Dumper;

use Kanopya::Exceptions;
use ParamPreset;

use Entity::Host::Hypervisor::OpenstackHypervisor;
use Entity::Host::VirtualMachine::OpenstackVm;
use Entity::Masterimage;
use Entity::Node;

use OpenStack::API;
use OpenStack::Port;
use OpenStack::Volume;
use OpenStack::Server;
use OpenStack::Infrastructure;

use ClassType::ServiceProviderType::ClusterType;

use TryCatch;
use Log::Log4perl "get_logger";
my $log = get_logger("");


use constant ATTR_DEF => {
    executor_component_id => {
        label        => 'Workflow manager',
        type         => 'relation',
        relation     => 'single',
        pattern      => '^[0-9\.]*$',
        is_mandatory => 1,
        is_editable  => 0,
    },
    api_username => {
        label        => 'Openstack login',
        type         => 'string',
        pattern      => '^.*$',
        is_mandatory => 1
    },
    api_password => {
        label        => 'Openstack password',
        type         => 'password',
        pattern      => '^.*$',
        is_mandatory => 1
    },
    keystone_url => {
        label        => 'Keystone URL',
        type         => 'string',
        pattern      => '^.*$',
        is_mandatory => 1
    },
    tenant_name => {
        label        => 'Tenant',
        type         => 'string',
        pattern      => '^.*$',
        is_mandatory => 1
    },
    host_type => {
        is_virtual => 1
    }
};

sub getAttrDef { return ATTR_DEF; }


my $vm_states = { active       => 'in',
                  build        => 'in',
                  deleted      => 'out',
                  error        => 'broken',
                  paused       => 'out',
                  rescued      => 'broken',
                  resized      => 'in',
                  soft_deleted => 'out',
                  stopped      => 'out',
                  suspended    => 'out' };


=pod
=begin classdoc

@constructor

Override the parent constructor to store uri and credentials params
the the related param preset.

@return a class instance

=end classdoc
=cut

sub new {
    my ($class, %args) = @_;


    General::checkParams(args     => \%args,
                         required => [ 'api_username', 'api_password', 'keystone_url', 'tenant_name' ]);

    my $self = $class->SUPER::new(%args);

    # Initialize the param preset entry used to store available configuration
    $self->param_preset(ParamPreset->new());

    return $self;
}

sub hostType {
    my $self = shift;
    return $self->label;
}

=pod
=begin classdoc

@return the network configuration used to check the availability of the openstack apis.

=end classdoc
=cut

sub getNetConf {
    my $self = shift;

    my $conf = {
        novncproxy => {
            port => 6080,
            protocols => ['tcp']
        },
        ec2 => {
            port => 8773,
            protocols => ['tcp']
        },
        compute_api => {
            port => 8774,
            protocols => ['tcp']
        },
        metadata_api => {
            port => 8775,
            protocols => ['tcp']
        },
        volume_api => {
            port => 8776,
            protocols => ['tcp']
        },
        glance_registry => {
            port => 9191,
            protocols => ['tcp']
        },
        image_api => {
            port => 9292,
            protocols => ['tcp']
        },
        keystone_service => {
            port => 5000,
            protocols => ['tcp']
        },
        keystone_admin => {
            port => 35357,
            protocols => ['tcp']
        },
        neutron => {
            port => 9696,
            protocols => ['tcp']
        }
    };

    return $conf;
}


=pod
=begin classdoc

@return the manager params definition.

=end classdoc
=cut

sub getManagerParamsDef {
    my ($self, %args) = @_;

    return {
        %{ $self->SUPER::getManagerParamsDef },
        flavor => {
            label        => 'Flavor',
            type         => 'enum',
            pattern      => '^.*$',
            is_mandatory => 1
        },
        availability_zone => {
            label        => 'Availability Zone',
            type         => 'enum',
            pattern      => '^.*$',
            is_mandatory => 1
        },
        tenant => {
            label        => 'Tenant',
            type         => 'enum',
            pattern      => '^.*$',
            is_mandatory => 1
        },
        volume_type => {
            label        => 'Storage backend',
            type         => 'enum',
            is_mandatory => 1,
            # TODO:  Get the enum options from the available synchronized backend
            options      => [ 'NFS', 'iSCSI', 'RADOS' ]
        },
        networks => {
            label        => 'Networks',
            type         => 'enum',
            is_mandatory => 1,
            options      => []
        },
        subnets => {
            label        => 'Subnets',
            type         => 'enum',
            is_mandatory => 1,
            options      => []
        },
        repository   => {
            is_mandatory => 1,
            label        => 'Repository',
            type         => 'enum',
        },
    };
}


=pod
=begin classdoc

Return the parameters definition available for the VirtualMachineManager api.

@see <package>Manager::HostManager</package>

=end classdoc
=cut

sub getHostManagerParams {
    my $self = shift;
    my %args = @_;

    my $params = $self->getManagerParamsDef;
    my $pp = $self->param_preset->load;

    my $flavors = $params->{flavor};
    my @flavor_names = map {$pp->{flavors}->{$_}->{name}} keys %{$pp->{flavors}};
    $flavors->{options} = \@flavor_names;

    my $zones = $params->{availability_zone};
    my @zone_names = keys %{$pp->{zones}};
    $zones->{options} = \@zone_names;

    my @tenant_names = keys %{$pp->{tenants_name_id}};
    my $tenants = $params->{tenant};
    $tenants->{options} = \@tenant_names;

    my $hash = {
        flavor => $flavors,
        availability_zone => $zones,
        tenant => $tenants,
    };

    return $hash;
}


=pod
=begin classdoc

Check parameters that will be given to the VirtualMachineManager api methods.

@see <package>Manager::HostManager</package>

=end classdoc
=cut

sub checkHostManagerParams {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'flavor', 'availability_zone', 'tenant' ]);
}


=pod
=begin classdoc

Return the parameters definition available for the DiskManager api.

@see <package>Manager::StorageManager</package>

=end classdoc
=cut

sub getStorageManagerParams {
    my ($self, %args) = @_;

    return { volume_type => $self->getManagerParamsDef->{volume_type} };
}


=pod
=begin classdoc

Check parameters that will be given to the DiskManager api methods.

@see <package>Manager::StorageManager</package>

=end classdoc
=cut

sub checkStorageManagerParams {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'volume_type' ]);
}


=pod
=begin classdoc

@return the network manager parameters as an attribute definition.

@see <package>Manager::NetworkManager</package>

=end classdoc
=cut

sub getNetworkManagerParams {
    my ($self, %args) = @_;

    my $params = $self->getManagerParamsDef;
    my $pp = $self->param_preset->load;

    my @tenant_names = keys %{$pp->{tenants_name_id}};
    my $tenants = $params->{tenant};
    $tenants->{options} = \@tenant_names;
    $tenants->{reload} = 1;
    my $hash = {
        tenant => $tenants,
    };

    if (defined $args{params}->{tenant}) {
        my $tenant_id = $pp->{tenants_name_id}->{$args{params}->{tenant}};
        my $networks = $self->getManagerParamsDef->{networks};
        $networks->{options} = [];
        $networks->{reload} = 1;

        for my $network_id (@{$pp->{tenants}->{$tenant_id}->{networks}}) {
            push @{$networks->{options}}, $pp->{networks}->{$network_id}->{name};
        }

        $hash->{networks} = $networks;
    }

    if (defined $args{params}->{networks}) {
        my $network_id = $pp->{networks_name_id}->{$args{params}->{networks}};
        $log->info("network id = " . $network_id);
        my $subnets = $self->getManagerParamsDef->{subnets};
        $subnets->{options} = [];

        for my $subnet_id (@{$pp->{networks}->{$network_id}->{subnets}}) {
            $log->info("subnet_id = $subnet_id, cird = " . $pp->{subnets}->{$subnet_id}->{cidr});
            push @{$subnets->{options}}, $pp->{subnets}->{$subnet_id}->{cidr};
        }

        $hash->{subnets} = $subnets;
    }

    return $hash;
}


=pod
=begin classdoc

Check params required for managing network connectivity.

@see <package>Manager::NetworkManager</package>

=end classdoc
=cut

sub checkNetworkManagerParams {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'networks' ]);
}



=pod
=begin classdoc

Check for virtual machine placement, and create the virtual host instance.

@see <package>Manager::HostManager</package>

=end classdoc
=cut

sub getFreeHost {
    my ($self, %args) = @_;

    General::checkParams(args => \%args,
                         required => [ 'networks', 'flavor', 'availability_zone', 'tenant' ]);

    $log->info("Looking for a virtual host");
    try {
        return $self->createVirtualHost(ifaces => scalar(@{ [ $args{networks} ] }), %args);
    }
    catch ($err) {
        # We can't create virtual host for some reasons (e.g can't meet constraints)
        throw Kanopya::Exception::Internal(
                  error => "Virtual machine manager <" . $self->label . "> has not capabilities " .
                           "to host this vm with flavor <$args{flavor}>:\n" . $err
              );
    }
}


=pod
=begin classdoc

Return the boot policies for the host ruled by this host manager

@see <package>Manager::HostManager</package>

=end classdoc
=cut

sub getBootPolicies {
    my $self = shift;

    return (Manager::HostManager->BOOT_POLICIES->{virtual_disk});
}


=pod
=begin classdoc

Create and start a virtual machine from the given parameters by calling the nova api.

@see <package>Manager::HostManager</package>

=end classdoc
=cut

sub startHost {
    my ($self, %args) = @_;

    General::checkParams(args  => \%args, required => [ 'host', 'flavor' ]);

    my $flavor_id = undef;
    my %flavors = %{$self->param_preset->load->{flavors}};
    while (my ($id, $flavor) = each (%flavors)) {
        if ($flavor->{name} eq $args{flavor}) {
            $flavor_id = $id;
            last;
        }
    }

    my @ids = map {$_->id} $args{host}->ifaces;
    my @macs = map {$_->iface_mac_addr} $args{host}->ifaces;
    my $port_macs = $self->param_preset->load->{port_macs};
    my @ports_ids = map {$port_macs->{$_}} @macs;

    #TODO use an other field to store volume_id
    my $server = OpenStack::Server->create(
                     api => $self->_api,
                     volume_id => $args{host}->node->systemimage->systemimage_desc,
                     flavor_id => $flavor_id,
                     port_ids => \@ports_ids,
                     instance_name => $args{host}->node->node_hostname,
                 );
    $log->debug(Dumper $server);

    $self->promoteVm(
        host => $args{host}->_entity,
        vm_uuid => $server->{server}->{id},
    );

    return;
}


=pod
=begin classdoc

Stop the virtual machine by calling the nova api.

@see <package>Manager::HostManager</package>

=end classdoc
=cut

sub stopHost {
    my ($self, %args) = @_;
    General::checkParams(args  => \%args, required => [ "host" ]);

    return OpenStack::Server->delete(api => $self->_api, id => $args{host}->openstack_vm_uuid);
}


=pod
=begin classdoc

Sclar cpu or ram of the virtual machine by calling the nova api.

@param host_id Host instance id to scale
@param scalein_value Wanted value
@param scalein_type Selectsthe metric to scale in either 'ram' or 'cpu'

@see <package>Manager::HostManager::VirtualMachineManager</package>

=end classdoc
=cut

sub scaleHost {
    my ($self,%args) = @_;

    General::checkParams(args => \%args, required => [ 'host_id', 'scalein_value', 'scalein_type' ]);

    throw Kanopya::Exception::NotImplemented();
}


=pod
=begin classdoc

Migrate a host to the destination hypervisor by calling the nova api.

@see <package>Manager::HostManager::VirtualMachineManager</package>

=end classdoc
=cut

sub migrate {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host_id', 'hypervisor_id' ]);

    throw Kanopya::Exception::NotImplemented();
}


=pod
=begin classdoc

Promote host into OpenstackVm and set its hypervisor id

@return the promoted host

@see <package>Manager::HostManager::VirtualMachineManager</package>

=end classdoc
=cut

sub promoteVm {
    my ($self, %args) = @_;
    General::checkParams(
        args => \%args,
        required => [ 'host', 'vm_uuid' ],
        optional => {hypervisor_id => undef},
    );

     $args{host} = Entity::Host::VirtualMachine::OpenstackVm->promote(
                      promoted           => $args{host},
                      nova_controller_id => $self->id,
                      openstack_vm_uuid  => $args{vm_uuid},
                  );

    $args{host}->hypervisor_id($args{hypervisor_id});
    return $args{host};
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

    my $details = OpenStack::Server->detail(
                      api => $self->_api,
                      id => $args{host}->openstack_vm_uuid,
                  );

    if (defined $details->{itemNotFound}) {
        throw Kanopya::Exception(error => $details->{itemNotFound});
    }

    return {
        hypervisor => $details->{server}->{'OS-EXT-SRV-ATTR:host'},
        state => $details->{server}->{status},
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

    try {
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
    catch ($err) {
        $log->warn($err);
    }
}

=pod
=begin classdoc

Create a Glance volume via Openstack API.

@see <package>Manager::StorageManager</package>

=end classdoc
=cut

sub createSystemImage {
    my ($self, %args) = @_;

    General::checkParams(args     => \%args,
                         required => [ "systemimage_name", "masterimage", "systemimage_size" ],);

    # Create Glance Volume
    my $image_id = undef;
    my %images = %{$self->param_preset->load->{images}};
    while (my ($id, $image) = each (%images)) {
        if ($image->{name} eq $args{masterimage}->masterimage_name) {
            $image_id = $id;
            last;
        }
    }

    #TODO destroy volume during rollback
    my $volume = OpenStack::Volume->create(
                     api => $self->_api,
                     image_id => $image_id,
                     size => $args{systemimage_size} / (1024 ** 3),
                 );

    $log->debug(Dumper $volume);

    my $detail;
    my $time_out = time + 240;
    do {
        sleep 10;
        $detail = OpenStack::Volume->detail(api => $self->_api, id => $volume->{volume}->{id});
        $log->debug($detail->{status});
    } while ($detail->{status} eq 'downloading' && time < $time_out);

    return Entity::Systemimage->new(
               systemimage_name => $args{systemimage_name},
               systemimage_desc => $volume->{volume}->{id},
               storage_manager_id => $self->id,
           );
}


=pod
=begin classdoc

Remove a system image from the storage system.

@see <package>Manager::StorageManager</package>

=end classdoc
=cut

sub removeSystemImage {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => [ "systemimage" ]);
    my $volume = OpenStack::Volume->delete(
                     api => $self->_api,
                     id => $args{systemimage}->systemimage_desc,
                 );

    $args{systemimage}->delete;
}


=pod
=begin classdoc

Do required struff for giving access for the node to the systemimage.

@see <package>Manager::StorageManager</package>

=end classdoc
=cut

sub attachSystemImage {
    my ($self, %args) = @_;
    $log->debug('No system image to attach');
    return;
}


=pod
=begin classdoc

@return the name of the type of storage provided by this storage manager.

@see <package>Manager::StorageManager</package>

=end classdoc
=cut

sub storageType {
    return "OpenStack Cinder";
}


=pod
=begin classdoc

Do the required configuration/actions to provides the boot mechanism for the node.

@see <package>Manager::BootManager</package>

=end classdoc
=cut

sub configureBoot {
    my ($self, %args) = @_;
    $log->debug('No boot configuration');
    return;
}


=pod
=begin classdoc

Workaround for the native HCM boot manager that requires the configuration
of the boot made in 2 steps.

Apply the boot configuration set at configureBoot

@see <package>Manager::BootManager</package>

=end classdoc
=cut

sub applyBootConfiguration {
    my ($self, %args) = @_;
    $log->debug('No boot configuration to apply');
    return;
}


=pod
=begin classdoc

Do the required configuration/actions to provides the proper network connectivity
to the node from the network manager params.

@see <package>Manager::NetworkManager</package>

=end classdoc
=cut

sub configureNetworkInterfaces {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => [ 'networks', 'subnets' ]);

    my $pp = $self->param_preset->load;
    my $net_id = $pp->{networks_name_id}->{$args{networks}};

    my $subnet_id = undef;
    for my $id (@{$pp->{networks}->{$net_id}->{subnets}}) {
        if ($pp->{subnets}->{$id}->{cidr} eq $args{subnets}) {
            $subnet_id = $id;
            last;
        }
    }

    my $port = OpenStack::Port->create(
                   api => $self->_api,
                   network_id => $net_id,
                   subnet_id =>  $subnet_id,
               );

    #TODO store information elsewhere
    $self->param_preset->update(
        params => {
            port_macs => {
                $port->{port}->{mac_address} => $port->{port}->{id}
            }
        }
    );

    $log->debug(Dumper $port);

    # Currently manage only on iface
    my @ifaces = $args{node}->host->getIfaces;
    foreach my $iface (@{ $args{node}->host->getIfaces }) {
        $iface->assignIp(ip_addr => $port->{port}->{fixed_ips}->[0]->{ip_address});
        $args{node}->admin_ip_addr($port->{port}->{fixed_ips}->[0]->{ip_address});
        $iface->iface_mac_addr($port->{port}->{mac_address});
    }

    return;
}


=pod
=begin classdoc


Querry the openstack API to register exsting hypervisors, virtaul machines
and all options available in the existing OpenStack.

=end classdoc
=cut

sub synchronize {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, optional => { 'workflow' => undef });

    return $self->executor_component->run(
               name   => 'Synchronize',
               workflow => delete $args{workflow},
               params => {
                   context => {
                       entity => $self
                   }
               }
           );
}


=pod
=begin classdoc

Terminate a host

=end classdoc
=cut

sub halt {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => [ 'host' ]);

    return OpenStack::Server->stop(api => $self->_api, id => $args{host}->openstack_vm_uuid);
}

sub releaseHost {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => [ 'host' ]);

    return $args{host}->delete();
}

sub _api {
    my ($self, %args) = @_;

    if (defined $self->{_api}) {
        return $self->{_api};
    }

    General::checkParams(args => \%args,
                         optional => { api_username => $self->api_username || 'admin',
                                       api_password => $self->api_password || 'keystone',
                                       keystone_url => $self->keystone_url || 'localhost',
                                       tenant_name  => $self->tenant_name  || 'openstack' } );

    $self->{_api} = OpenStack::API->new(user         => $args{api_username},
                                        password     => $args{api_password},
                                        tenant_name  => $args{tenant_name},
                                        keystone_url => $args{keystone_url});

    return $self->{_api}
}


sub _load {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'infra' ]);

    my $tenants_name_id = {};
    my $tenants = {};
    for my $tenant (@{$args{infra}->{tenants}}) {
        $tenants_name_id->{$tenant->{name}} = $tenant->{id};
        $tenants->{$tenant->{id}} = $tenant;
        $tenants->{$tenant->{id}}->{networks} = [];
    }

    my $zones = {};
    for my $zone (@{$args{infra}->{availability_zones}}) {
        # A zone has no id
        $zones->{$zone->{zoneName}} = $zone;
    }

    my $flavors = {};
    for my $flavor (@{$args{infra}->{flavors}}) {
        $flavors->{$flavor->{id}} = $flavor;
    }

    my $subnets = {};
    for my $subnet (@{$args{infra}->{subnets}}) {
        $subnets->{$subnet->{id}} = $subnet;
    }

    my $images = {};
    for my $image (@{$args{infra}->{images}}) {
        $images->{$image->{id}} = $image;
    }

    my $networks_name_id = {};
    my $networks = {};
    for my $network (@{$args{infra}->{networks}}) {
        push @{$tenants->{$network->{tenant_id}}->{networks}}, $network->{id};
        $networks_name_id->{$network->{name}} = $network->{id};
        $networks->{$network->{id}} = $network
    }

    my $pp = $self->param_preset;
    $pp->update(
        params => {
            tenants => $tenants,
            networks => $networks,
            subnets => $subnets,
            flavors => $flavors,
            zones => $zones,
            images => $images,
            # TODO Remove following and find better method
            networks_name_id => $networks_name_id,
            tenants_name_id => $tenants_name_id,
        }
    );

    # Manage images
    my $cluster_type = ClassType::ServiceProviderType::ClusterType->find(
                           service_provider_name => 'Cluster',
                       );

    for my $image_info (@{$args{infra}->{images}}) {
        Entity::Masterimage->new(
            masterimage_name => $image_info->{name},
            masterimage_file => $image_info->{file},
            masterimage_size => $image_info->{size},
            masterimage_cluster_type_id => $cluster_type->id,
        );
    }

    # Manage hypervisors
    my $count = 0;
    my $hv_count = 0;
    for my $hypervisor_info (@{$args{infra}->{hypervisors}}) {
        my $hypervisor = Entity::Host->new(
            active => 1,
            host_ram => $hypervisor_info->{memory_mb} * (1024 ** 2), # MB to B
            host_core => $hypervisor_info->{vcpus},
            host_state => 'up:' . time(),
            host_desc => 'Registered OpenStack Hypervisor - '
                         . $hypervisor_info->{hypervisor_hostname},
            host_serial_number => 'Registered OpenStack Hypervisor - '
                                  . $hypervisor_info->{hypervisor_hostname},
        );
        $hv_count++;

        $self->addHypervisor(host => $hypervisor);

        Entity::Node->new(
            node_hostname       => $hypervisor_info->{hypervisor_hostname},
            host_id             => $hypervisor->id,
            node_state          => 'in:' . time(),
            node_number         => $hv_count,
        );

        for my $vm_info (@{$hypervisor_info->{servers}}) {
            $count++;

            my $network_info = $vm_info->{addresses};

            my $vm = $self->createVirtualHost(
                           ram => $vm_info->{flavor}->{ram} * (1024 ** 2), # MB to B
                           core => $vm_info->{flavor}->{vcpus},
                           ifaces => scalar (keys %$network_info),
                        );

            $vm = $self->promoteVm(
                      host => $vm,
                      vm_uuid => $vm_info->{id},
                      hypervisor_id => $hypervisor->id,
                  );

            my $vm_state = $vm_states->{$vm_info->{'OS-EXT-STS:vm_state'}} . ':' . time();

            my $node = Entity::Node->new(
                           node_hostname       => $vm_info->{name},
                           host_id             => $vm->id,
                           node_state          => $vm_state,
                           node_number         => $count,
                           systemimage_id      => undef, # Manage
                          );

            my @ifaces = $vm->ifaces;

            while(my ($name, $ip_infos) = each(%$network_info)) {

                # TODO Manage floating ips

                my $ip_info;
                # '=' is ok, we assign first and then we test
                while(($ip_info = (pop @$ip_infos)) && ($ip_info->{'OS-EXT-IPS:type'} ne 'fixed')) {}

                if (defined $ip_info) {
                    my $iface = (pop @ifaces);
                    $iface->iface_mac_addr($ip_info->{'OS-EXT-IPS-MAC:mac_addr'});
                    Ip->new(
                        ip_addr  => $ip_info->{addr},
                        iface_id => $iface->id,
                    );
                }
            }
        }
    }
}
1;
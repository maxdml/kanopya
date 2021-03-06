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
use parent Manager::CollectorManager;

use strict;
use warnings;

use Entity::Host::Hypervisor::OpenstackHypervisor;
use Entity::Host::VirtualMachine::OpenstackVm;
use Entity::Masterimage::GlanceMasterimage;
use ClassType::ServiceProviderType::ClusterType;
use Entity::Systemimage::CinderSystemimage;
use Entity::Node;
use Kanopya::Exceptions;
use ParamPreset;

use OpenStack::API;
use OpenStack::Port;
use OpenStack::Volume;
use OpenStack::Server;
use OpenStack::Infrastructure;
use OpenStack::Ceilometer;

use KeystoneEndpoint;
use Hash::Merge;
use Data::Dumper;
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



sub new {
    my ($class, %args) = @_;
    General::checkParams(args     => \%args,
                         required => [ 'api_username', 'api_password', 'keystone_url', 'tenant_name' ]);

    # Initialize the param preset entry used to store available configuration
    my $self = $class->SUPER::new(%args);
    my $pp = ParamPreset->new();
    $self->param_preset_id($pp->id);
    return $self;
}

=pod
=begin classdoc

@constructor

Override the parent constructor to store uri and credentials params
the the related param preset.

@return a class instance

=end classdoc
=cut

sub create {
    my ($class, %args) = @_;
    General::checkParams(args     => \%args,
                         required => [ 'api_username', 'api_password', 'keystone_url', 'tenant_name' ]);

    Kanopya::Database::beginTransaction();
    my $self = $class->new(%args);

    # Try to connect to the api to do not register the componnet if connexion infos are eroneous
    try {
        $self->_api;
    }
    catch ($err) {
        Kanopya::Database::rollbackTransaction();
        throw Kanopya::Exception::Internal::WrongValue(
                  error => "Unable to connect to the OpenStack keystone service, " .
                           "please check your connexion informations."
              );
    }

    for my $id (@{$self->_api->{config}->{identity}->{endpoint_ids}}) {
        try {
            KeystoneEndpoint->new(open_stack_id => $self->id, keystone_uuid => $id);
        }
        catch (Kanopya::Exception::DB::DuplicateEntry $err) {
            Kanopya::Database::rollbackTransaction();
            my $label = KeystoneEndpoint->find(hash => {keystone_uuid => $id})->open_stack->label;
            my $error = 'The component you try to register has already been '
                        . 'registered under the label "'
                        . $label
                        . '"';

            throw Kanopya::Exception::Internal(error => $error);
        }
        catch ($err) {
            Kanopya::Database::rollbackTransaction();
            $err->rethrow;
        }
    }

    my @indicator_sets = (Indicatorset->search(hash =>{indicatorset_name => 'ceilometer'}));
    $self->createCollectorIndicators(
        indicator_sets => \@indicator_sets,
    );

    Kanopya::Database::commitTransaction();
    return $self;
}

sub remove {
    my ($self, %args) = @_;
    $self->unregister();
    $self->SUPER::remove();
}

sub unregister {
    my ($self, %args) = @_;
    my @spms = $self->service_provider_managers;
    if (@spms) {
        my $error = 'Cannot unregister OpenStack: Still used as "'
                    . $spms[0]->manager_category->category_name
                    . '" by cluster "'
                    . $spms[0]->service_provider->label . '"';
        throw Kanopya::Exception::Internal(error => $error);
    }

    my @sis = $self->systemimages;
    if (@sis) {
        my $error = 'Cannot unregister OpenStack: Still linked to a systemimage "'
                    . $sis[0]->label . '"';
        throw Kanopya::Exception::Internal(error => $error);
    }

    for my $vm ($self->hosts) {
        if (defined $vm->node) {
            $vm->node->delete;
        }
        $vm->delete;
    }

    for my $host ($self->hypervisors) {
        if (defined $host->node) {
            $host->node->delete;
        }
        $host->delete;
    }

    $self->removeMasterimages();
}

sub hostType {
    my $self = shift;
    return $self->label;
}


sub label {
    my $self = shift;
    return $self->SUPER::label . " " . $self->keystone_url  . " (" . $self->tenant_name . ")";
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
        hosting_tenant => {
            label        => 'Project',
            type         => 'enum',
            pattern      => '^.*$',
            is_mandatory => 1
        },
        network_tenant => {
            label        => 'Project',
            type         => 'enum',
            pattern      => '^.*$',
            is_mandatory => 1
        },
        volume_type => {
            label        => 'Volume type',
            type         => 'enum',
            is_mandatory => 0,
            options      => []
        },
        repository   => {
            is_mandatory => 1,
            label        => 'Repository',
            type         => 'enum',
        },
        subnets => {
            label        => 'Subnets',
            is_mandatory => 1,
            type         => 'relation',
            relation     => 'multi',
            is_editable  => 1,
            options      => [],
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
    $flavors->{order} = 3;

    my $zones = $params->{availability_zone};
    my @zone_names = keys %{$pp->{zones}};
    $zones->{options} = \@zone_names;
    $zones->{order} = 2;

    my @tenant_names = keys %{$pp->{tenants_name_id}};
    my $tenants = $params->{hosting_tenant};
    $tenants->{options} = \@tenant_names;
    $tenants->{order} = 1;

    return { %{ $self->SUPER::getHostManagerParams },
             flavor => $flavors,
             availability_zone => $zones,
             hosting_tenant => $tenants,};
}


=pod
=begin classdoc

Check parameters that will be given to the VirtualMachineManager api methods.

@see <package>Manager::HostManager</package>

=end classdoc
=cut

sub checkHostManagerParams {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'flavor', 'availability_zone', 'hosting_tenant' ]);
}


=pod
=begin classdoc

Return the parameters definition available for the DiskManager api.

@see <package>Manager::StorageManager</package>

=end classdoc
=cut

sub getStorageManagerParams {
    my ($self, %args) = @_;

    my $pp = $self->param_preset->load;
    my $params = {
        volume_type => $self->getManagerParamsDef->{volume_type},
        masterimage_id => Manager::StorageManager->getManagerParamsDef->{masterimage_id},
    };

    for my $type_id (keys %{ $pp->{volume_types} }) {
        push @{ $params->{volume_type}->{options} }, $pp->{volume_types}->{$type_id}->{name};
    }

    for my $masterimage ($self->masterimages) {
        push @{$params->{masterimage_id}->{options}}, $masterimage->toJSON();
    }

    return $params;
}


=pod
=begin classdoc

Check parameters that will be given to the DiskManager api methods.

@see <package>Manager::StorageManager</package>

=end classdoc
=cut

sub checkStorageManagerParams {
    my ($self, %args) = @_;

    General::checkParams(args => \%args);

    # Workaround: Add a dummy boot_policy to fix missing boot_policy when
    #             when storage manager is not the HCMStorageManager.
    # TODO: Make the param boot_policy required for the HCMDeploymenytManager boot manager params
    $args{boot_policy} = 'Boot from Glance Image';

    return \%args;

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
    my $tenants = $params->{network_tenant};
    $tenants->{options} = \@tenant_names;
    $tenants->{order} = 1;
    $tenants->{reload} = 1;

    my $hash = { network_tenant => $tenants };
    if (defined $args{params}->{network_tenant}) {
        my $tenant_id = $pp->{tenants_name_id}->{$args{params}->{network_tenant}};

        my $subnets = $self->getManagerParamsDef->{subnets};
        for my $network_id (@{ $pp->{tenants}->{$tenant_id}->{networks} }) {
            my $network_name = $pp->{networks}->{$network_id}->{name};

            for my $subnet_id (@{ $pp->{networks}->{$network_id}->{subnets} }) {
                push @{ $subnets->{options} }, $pp->{subnets}->{$subnet_id}->{cidr} . " ($network_name)";
            }
        }
        $hash->{subnets} = $subnets;
        $hash->{subnets}->{order} = 2;
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

    General::checkParams(args => \%args, required => [ 'subnets' ]);
}


=pod
=begin classdoc

Remove the network manager params entry from a hash ref.

@see <package>Manager::NetworkManager</package>

=end classdoc
=cut

sub releaseNetworkManagerParams {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ "params" ]);

    delete $args{params}->{network_tenant};
    delete $args{params}->{subnets};
}


=pod
=begin classdoc

@return the boot manager parameters as an attribute definition.

@see <package>Manager::BootManager</package>

=end classdoc
=cut

sub getBootManagerParams {
    my ($self, %args) = @_;

    return {};
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
                         required => [ 'subnets', 'flavor' ]);

    try {
        my $flavors = $self->param_preset->load->{flavors};
        my $ram;
        my $core;
        while (my ($flavor_id, $flavor) = each(%$flavors)) {
            if ($flavor->{name} eq $args{flavor}) {
                $ram = $flavor->{ram} * 1024 * 1024;
                $core = $flavor->{vcpus};
            }
        }

        return $self->createVirtualHost(
                   ifaces => scalar(keys %{ $args{subnets} }),
                   ram => $ram,
                   core => $core,
               );
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

    General::checkParams(args  => \%args,
                         required => [ 'host', 'flavor', 'hypervisor' ],
                         optional => {hypervisor => undef});

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
                     volume_id => $args{host}->node->systemimage->volume_uuid,
                     flavor_id => $flavor_id,
                     port_ids => \@ports_ids,
                     instance_name => $args{host}->node->node_hostname,
                     availability_zone => 'zone:' . $args{hypervisor}->node->node_hostname,
                 );

    $self->promoteVm(host    => $args{host}->_entity,
                     vm_uuid => $server->{server}->{id});

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

    try {
        OpenStack::Server->delete(
            api => $self->_api,
            id => $args{host}->openstack_vm_uuid,
        );
    }
    catch ($err) {
        # When an Exception happens during the DeployNode transaction,
        # the openstack_vm_uuid is not registered.
        # Try to find the vm with the node hostname
        $log->info('Try to delete the vm by its name');
        try {
            OpenStack::Server->delete(
                api => $self->_api,
                name => $args{host}->node->node_hostname,
            );
        }
        catch ($err) {
            $log->warn('Error when deleting Openstack server:' . $err);
        }
    }

    return;
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

sub migrateHost {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => [ 'host', 'hypervisor' ]);

    OpenStack::Server->migrate(
        api => $self->_api,
        id => $args{host}->openstack_vm_uuid,
        hypervisor_hostname => $args{hypervisor}->node->node_hostname,
    );

    return;
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

    General::checkParams(args     => \%args,
                         required => [ 'host', 'vm_uuid' ],
                         optional => { 'hypervisor_id' => undef });

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
                      flavor_detail => 1,
                  );

    if (defined $details->{itemNotFound}) {
        throw Kanopya::Exception(error => $details->{itemNotFound});
    }

    return {
        hypervisor => $details->{server}->{'OS-EXT-SRV-ATTR:hypervisor_hostname'},
        state => $details->{server}->{status},
        ram => $details->{server}->{flavor}->{ram} * 1024 * 1024, #MB to B
        cpu => $details->{server}->{flavor}->{vcpus},
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

    my $details;
    try {
        $details =  $self->getVMDetails(%args);
    }
    catch ($err) {
        $log->warn($err);
        return {state => 'fail'};
    }

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

=pod
=begin classdoc

Create a Glance volume via Openstack API.

@see <package>Manager::StorageManager</package>

=end classdoc
=cut

sub createSystemImage {
    my ($self, %args) = @_;

    General::checkParams(args     => \%args,
                         required => [ "systemimage_name", "masterimage", "systemimage_size" ],
                         optional => { "volume_type" => undef });

    my $pp = $self->param_preset->load;

    # Create Glance Volume
    my $image_id = undef;
    my %images = %{ $pp->{images} };
    while (my ($id, $image) = each (%images)) {
        if ($image->{name} eq $args{masterimage}->masterimage_name) {
            $image_id = $id;
            last;
        }
    }

    my $volume_type_id;
    if (defined $args{volume_type}) {
        my %types = %{ $pp->{volume_types} };
        while (my ($id, $type) = each (%types)) {
            if ($type->{name} eq $args{volume_type}) {
                $volume_type_id = $id;
                last;
            }
        }
    }

    #TODO destroy volume during rollback
    my $volume = OpenStack::Volume->create(api => $self->_api,
                                           image_id => $image_id,
                                           size => $args{systemimage_size} / (1024 ** 3),
                                           volume_type => $volume_type_id);

    my $detail;
    my $time_out = time + 3600;
    do {
        $detail = OpenStack::Volume->detail(api => $self->_api, id => $volume->{volume}->{id});

        $log->debug("Volume creation status: $detail->{status} (timeout " . ($time_out - time) . "s left)");
        if ($detail->{status} eq 'error') {
            throw Kanopya::Exception::Internal(error => "Unable to create volume: " . Dumper($detail));
        }

        sleep 10;
    } while ($detail->{status} =~ m/downloading|creating/ && time < $time_out);

    return Entity::Systemimage::CinderSystemimage->new(
               systemimage_name => $args{systemimage_name},
               volume_uuid => $volume->{volume}->{id},
               image_uuid => $image_id,
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

    if (defined $args{systemimage}->volume_uuid) {
        my $detail;
        my $time_out = time + 60;
        do {
            try {
                $detail = OpenStack::Volume->detail(api => $self->_api, id => $args{systemimage}->volume_uuid);
            }
            catch ($err) {
                $log->warn('Error when getting volume detail: ' . $err);
                return $args{systemimage}->delete;
            }
            $log->debug("Volume to delete status: $detail->{status} (timeout " . ($time_out - time) . "s left)");

            sleep 3;
        } while ($detail->{status} =~ m/in-use/ && time < $time_out);

        try {
            my $volume = OpenStack::Volume->delete(
                             api => $self->_api,
                             id => $args{systemimage}->volume_uuid,
                         );
            $log->debug(Dumper $volume);
        }
        catch ($err) {
            $log->warn('Error when deleting volume: ' . $err);
        }
    }
    else {
        $log->warn('No volume to delete');
    }
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

    General::checkParams(args => \%args, required => [ 'subnets', 'node' ]);

    my $pp = $self->param_preset->load;
    my @ifaces = $args{node}->host->getIfaces;
    my $port_macs = {};
    for my $subnet (values %{ $args{subnets} }) {
        (my $subnet_addr = $subnet) =~ s/ \(.*\)$//g;
        (my $network_name = $subnet) =~ s/^.* \(//g;
        $network_name =~ s/\)$//g;

        my $subnet_id;
        my $network_id = $pp->{networks_name_id}->{$network_name};
        try {
            my @uuids = grep { $pp->{subnets}->{$_}->{cidr} eq $subnet_addr }
                            @{ $pp->{networks}->{$network_id}->{subnets} };
            $subnet_id = pop(@uuids);
        }
        catch ($err) {
            throw Kanopya::Exception::Internal::Inconsistency(
                      error => "Unable to retrieve network and subnet id for $subnet:$err"
                  );
        }

        $log->info("Found network $network_id and subnet $subnet_id for $subnet.");
        my $port = OpenStack::Port->create(api        => $self->_api,
                                           network_id => $network_id,
                                           subnet_id  =>  $subnet_id);

        $port_macs->{$port->{port}->{mac_address}} = $port->{port}->{id};

        # Assign the resulting ip the the next iface
        my $iface = shift(@ifaces);
        $log->info('Assign iface ' . $iface->iface_name . ' with ip <' .
                   $port->{port}->{fixed_ips}->[0]->{ip_address} . '> and mac <' .
                   $port->{port}->{mac_address} . '>');

        $iface->assignIp(ip_addr => $port->{port}->{fixed_ips}->[0]->{ip_address});
        $iface->iface_mac_addr($port->{port}->{mac_address});

        # If the node admin ip not set, use the first one
        if (! defined $args{node}->admin_ip_addr) {
            $args{node}->admin_ip_addr($port->{port}->{fixed_ips}->[0]->{ip_address});
        }
    }

    # TODO store information elsewhere
    $self->param_preset->update(params => { port_macs => $port_macs });

    return;
}

sub unconfigureNetworkInterface {
    my ($self, %args) = @_;
    my @mac_addresses = map {$_->reload->iface_mac_addr} $args{node}->host->getIfaces;

    my $params = $self->param_preset->load;

    for my $addr (@mac_addresses) {
        if (! defined $params->{port_macs}->{$addr}) {
            $log->warn('Cannot find port_uuid and delete OpenStack Port. '
                       . ' this can happened when the port creation and the '
                       . ' exception occurs during the same transaction');
        }
        else {
            try {
                OpenStack::Port->delete(
                    api => $self->_api,
                    id => $params->{port_macs}->{$addr}
                );
            }
            catch($err) {
                $log->warn('Error when deleting port:' . $err);
            }
            delete $params->{port_macs}->{$addr};
        }
    }
    $self->param_preset->update(params => $params, override => 1);
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
    try {
        OpenStack::Server->stop(api => $self->_api, id => $args{host}->openstack_vm_uuid);
    }
    catch($err) {
        $log->warn('Error during openstack node halt ' . $err);
    }
}

sub releaseHost {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => [ 'host' ]);

    return $args{host}->delete();
}

=pod
=begin classdoc

Get all the vms of an hypervisor through Openstack API

@param host hypervisor

=end classdoc
=cut

sub getHypervisorVMs {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => [ 'host' ]);

    my $vms = OpenStack::Hypervisor->servers(
                  id => $args{host}->node->node_hostname,
                  api => $self->_api,
              );

    my @vms = ();
    my @unk_vm_uuids = ();

    for my $uuid (map {$_->{uuid}} @$vms) {
        try {
            my $e = Entity::Host::VirtualMachine::OpenstackVm->find(hash => {
                        openstack_vm_uuid => $uuid
                    });
            push @vms, $e;
        }
        catch (Kanopya::Exception::Internal::NotFound $err) {
            $log->warn('unknown openstack virtual machine <' . $uuid . '>');
            push @unk_vm_uuids, $uuid;
        }
    }

    return {
        unk_vm_uuids => \@unk_vm_uuids,
        vms => \@vms,
    };
}


sub selectHypervisor {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => [ 'flavor' ]);
    my $flavors = $self->param_preset->load->{flavors};
    my $ram;
    my $core;
    while (my ($flavor_id, $flavor) = each(%$flavors)) {
        if ($flavor->{name} eq $args{flavor}) {
            $ram = $flavor->{ram} * 1024 * 1024;
            $core = $flavor->{vcpus};
            last;
        }
    }

    return $self->SUPER::selectHypervisor(ram => $ram, core => $core, %args);
}

sub postStart {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => [ 'host' ]);

    my $detail = OpenStack::Server->detail(
                     api => $self->_api,
                     id => $args{host}->openstack_vm_uuid
                 );

    my $hypervisor_id;
    my $hypervisor_name = $detail->{server}->{'OS-EXT-SRV-ATTR:host'};
    try {
        $hypervisor_id = $self->findRelated(
                             filters => ['hypervisors'],
                             hash => {
                                 'node.node_hostname' => $hypervisor_name,
                             }
                         )->id;
    }
    catch ($err) {
        $log->warn("No hypervisor with name $hypervisor_name is linked to this HostManager");
    }

    $args{host}->hypervisor_id($hypervisor_id);
}


sub increaseConsumers {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => [ 'operation' ]);

    my @states = $self->entity_states;

    for my $state (@states) {
        if ($state->consumer_id eq $args{operation}->workflow_id) {
            next;
        }
        throw Kanopya::Exception::Execution::InvalidState(
                  error => "Entity state <" . $state->state
                           . "> already set by consumer <"
                           . $state->consumer->label . ">"
              );
    }

    $self->setConsumerState(
        state => $args{operation}->operationtype->operationtype_name,
        consumer => $args{operation}->workflow,
    );
}

=pod
=begin classdoc

Decrease the number of current consumers of the manager.

=end classdoc
=cut

sub decreaseConsumers {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => [ 'operation' ]);
    $self->removeState(consumer => $args{operation}->workflow);
}


=pod
=begin classdoc

Remove related master images

=end classdoc
=cut

sub removeMasterimages {
    my ($self, %args) = @_;
    my $images = $self->param_preset->load->{images};
    for my $image (values %$images) {
        try {
            Entity::Masterimage::GlanceMasterimage->find(hash => {
                masterimage_name => $image->{name},
                masterimage_file => $image->{file},
            })->delete();
        }
        catch (Kanopya::Exception::Internal::NotFound $err) {
            $log->warn('Systeimage <' . $image->{name} . '> seems to have been already deleted');
        }
        catch ($err) {
            $err->rethrow;
        }
    }
}

=pod
=begin classdoc

Override the vmms relation to raise an execption as the OpenStack iaas do not manage the hypervisors.

=end classdoc
=cut

sub vmms {
    my ($self, %args) = @_;

    throw Kanopya::Exception::Internal(error => "Hypervisors not managed by iaas " . $self->label);
}

sub retrieveData {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => ['nodelist', 'indicators']);

    my $output = {};
    my @oids = keys %{$args{indicators}};

    my $res = OpenStack::Ceilometer->retrieve(api => $self->_api,
                                              meters => \@oids,
                                              hostnames => $args{nodelist});

    for my $nodename (@{$args{nodelist}}) {
        for my $oid (@oids) {
            $output->{$nodename}->{$oid} = $res->{$nodename}->{$oid}->{volume};
        }
    }

    return $output;
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

sub _createHypervisor {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => [ 'ram', 'core', 'hostname' ]);

    my $hypervisor = Entity::Host->new(
                         active => 1,
                         host_ram => $args{ram},
                         host_core => $args{core},
                         host_serial_number => $args{hostname},
                         host_desc => 'Registered OpenStack Hypervisor - '
                                      . $args{hostname},
                     );

    $self->addHypervisor(host => $hypervisor);
    return $hypervisor;
}

sub _updateHypervisor {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => [ 'ram', 'core', 'hypervisor' ]);
    $args{hypervisor}->update(
        host_ram => $args{ram},
        host_core => $args{core},
    );
    return;
}

sub _synchronizeHypervisors {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => [ 'hypervisor_list' ]);

    # Delete removed hypervisor
    for my $hv ($self->hypervisors) {
        if (! exists $args{hypervisor_list}->{$hv->host_serial_number}) {
            for my $vm ($hv->virtual_machines) {
                $vm->hypervisor_id(undef);
            }
            try {
                $hv->node->remove();
            }
            $hv->delete();
        }
    }

    my $hv_count = 0;
    for my $hypervisor_info (values %{$args{hypervisor_list}}) {
        $hv_count++;

        my $hypervisor;
        try {
            $hypervisor = Entity::Host::Hypervisor->find(hash => {
                              host_serial_number => $hypervisor_info->{hypervisor_hostname},
                          });

            $self->_updateHypervisor(
                hypervisor => $hypervisor,
                ram => $hypervisor_info->{memory_mb} * (1024 ** 2),
                core => $hypervisor_info->{vcpus},
            );
        }
        catch (Kanopya::Exception::Internal::NotFound $err) {
            $hypervisor = $self->_createHypervisor(
                              ram => $hypervisor_info->{memory_mb} * (1024 ** 2),
                              core => $hypervisor_info->{vcpus},
                              hostname => $hypervisor_info->{hypervisor_hostname},
                          );
        }
        catch ($err) {
            $err->rethrow();
        }

        $hypervisor->setState(state => 'up');

        # Create the corresponding node if not exist
        # Can not use findOrCreate here as the node number should differs
        my $node = $hypervisor->node;
        my @fqdn = split('\.', $hypervisor_info->{hypervisor_hostname});

        if (! defined $node) {
            $node = Entity::Node->new(
                node_hostname => $fqdn[0],
                host_id       => $hypervisor->id,
                node_state    => 'in:' . time(), #TODO manage disabled hv
                node_number   => $hv_count,
            );
        }
        else {
            $node->update(
                node_hostname => $fqdn[0],
                node_number => $hv_count,
            );
        }
    }
}

sub _updateVm {
    my ($self, %args) = @_;
    General::checkParams(
        args => \%args,
        required => [ 'vm', 'ram', 'core', 'hostname', 'hypervisor_name' ],
    );

    # TODO Optimize to avoid this call
    my $hypervisor = $self->find(
                         related => 'hypervisors',
                         hash => {
                            'node.node_hostname' => $args{hypervisor_name},
                         }
                     );

    $args{vm}->update(
        hypervisor_id => $hypervisor->id,
        host_serial_number => $args{hostname},
        host_ram => $args{ram},
        host_core => $args{core},
    );
}

sub _createVm {
    my ($self, %args) = @_;
    General::checkParams(
        args => \%args,
        required => [ 'ram', 'core', 'hostname', 'hypervisor_name', 'vm_uuid', 'num_ifaces' ]
    );

    my $vm = $self->createVirtualHost(
                 ram  => $args{ram},
                 core => $args{core},
                 ifaces => $args{num_ifaces},
                 serial_number => $args{hostname},
          );

    # TODO Optimize to avoid this call
    my $hypervisor = $self->find(
                         related => 'hypervisors',
                         hash => {
                            'node.node_hostname' => $args{hypervisor_name},
                         }
                     );

    $vm = $self->promoteVm(
              host => $vm,
              vm_uuid => $args{vm_uuid},
              hypervisor_id => $hypervisor->id,
          );

    return $vm;
}


sub _synchronizeVirtualMachines {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => [ 'vm_list' ]);

    # Delete removed vm
    for my $vm ($self->hosts) {
        if (! exists $args{vm_list}->{$vm->openstack_vm_uuid}) {
            try {
                $vm->node->delete();
            }
            $vm->delete();
        }
    }

    my $count = 0;

    for my $vm_info (values %{$args{vm_list}}) {
        $count++;

        my $network_info = $vm_info->{addresses};

        my $vm;
        try {
            $vm = Entity::Host::VirtualMachine::OpenstackVm->find(
                      hash => {openstack_vm_uuid => $vm_info->{id}}
                  );

            $self->_updateVm(
                 vm => $vm,
                 ram => $vm_info->{flavor}->{ram} * (1024 ** 2), # MB to B
                 core => $vm_info->{flavor}->{vcpus},
                 hostname => $vm_info->{name},
                 hypervisor_name => $vm_info->{'OS-EXT-SRV-ATTR:host'},
            );
        }
        catch (Kanopya::Exception::Internal::NotFound $err) {
            $vm = $self->_createVm(
                      ram => $vm_info->{flavor}->{ram} * (1024 ** 2), # MB to B
                      core => $vm_info->{flavor}->{vcpus},
                      vm_uuid => $vm_info->{id},
                      hostname => $vm_info->{name},
                      num_ifaces => scalar (keys %$network_info),
                      hypervisor_name => $vm_info->{'OS-EXT-SRV-ATTR:host'},
                  );
        }
        catch ($err) {
            $err->rethrow();
        }

        # Create the corresponding node if not exist
        my $node = $vm->node;
        if (! defined $node) {
            $node = Entity::Node->new(
                        node_hostname => $vm_info->{name},
                        node_number => $count,
                        host_id => $vm->id,
                        systemimage_id => undef, # Manage
                    );
        }
        else {
            $node->update(
                node_hostname       => $vm_info->{name},
                node_number         => $count,
            );
        }
        $node->setState(state => $vm_states->{$vm_info->{'OS-EXT-STS:vm_state'}} . ':' . time());
        my @ifaces = $vm->ifaces;
        
        my $nr_ifaces  = scalar @ifaces;
        my $nr_netinfo = scalar keys %$network_info;

        if ($nr_ifaces < $nr_netinfo) {
            # create new ifaces if missing
            for my $i (1..($nr_netinfo - $nr_ifaces)) {
                $vm->addIface(
                    iface_name     => 'eth' . $nr_ifaces + $i - 1,
                    iface_mac_addr => $self->generateMacAddress(),
                    iface_pxe      => 0,
                );
            }
            @ifaces = $vm->ifaces;
        }
        elsif ($nr_ifaces > $nr_netinfo) {
            for my $i (1..($nr_ifaces - $nr_netinfo)) {
                (pop @ifaces)->delete();
            }
            @ifaces = $vm->ifaces;
        }

        # Reaffect all mac/ip
        for my $iface (@ifaces) {
            $iface->iface_mac_addr(undef);
            for my $ip ($iface->ips) {
                $ip->delete;
            }
        }

        while(my ($name, $ip_infos) = each(%$network_info)) {

            # TODO Manage floating ips
            my $ip_info;
            # '=' is ok, we assign first and then we test
            while(($ip_info = (pop @$ip_infos)) && ($ip_info->{'OS-EXT-IPS:type'} ne 'fixed')) {}

            if (defined $ip_info) {
                my $iface = (pop @ifaces);
                try {
                    $iface->iface_mac_addr($ip_info->{'OS-EXT-IPS-MAC:mac_addr'});
                }
                catch (Kanopya::Exception::DB $err) {
                    # Check if VM is the HCM Master Node
                    my $iface = Entity::Iface->find(hash => {
                                    iface_mac_addr => $ip_info->{'OS-EXT-IPS-MAC:mac_addr'}
                                });

                    # Warning works only when vm hostname corresponds to
                    # Openstack Instance Name (converted in lower case)
                    if (lc($vm_info->{name}) eq $iface->host->node->node_hostname) {
                        # VM is the HCM Master Node !
                        $log->warn('HCM Master node is in the openstack'
                                   . 'Skip iface configuration');
                        next;
                    }
                    else {
                        $err->rethrow;
                    }
                }
                catch ($err) {
                    $err->rethrow;
                }

                Ip->new(
                    ip_addr  => $ip_info->{addr},
                    iface_id => $iface->id,
                );
                $node->admin_ip_addr($ip_info->{addr});
            }
        }
    }
}

sub _synchronizeMasterimages {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => [ 'images' ]);

    # Delete removed masterimage
    for my $mi ($self->masterimages) {
        if (! exists $args{images}->{$mi->masterimage_file}) {
            $mi->delete;
        }
    }

    my $type = ClassType::ServiceProviderType::ClusterType->find(hash => {
                   service_provider_name => 'Cluster',
               });

    for my $image_info (values %{$args{images}}) {
        try {
            my $image = Entity::Masterimage::GlanceMasterimage->find(hash => {
                            masterimage_file => $image_info->{file},
                        });

            $image->update(
                masterimage_name => $image_info->{name},
                masterimage_size => $image_info->{size},
            );
        }
        catch (Kanopya::Exception::Internal::NotFound $err) {
            Entity::Masterimage::GlanceMasterimage->new(
                masterimage_name => $image_info->{name},
                masterimage_size => $image_info->{size},
                masterimage_file => $image_info->{file},
                masterimage_cluster_type_id => $type->id,
                storage_manager_id => $self->id,
            );
        }
        catch ($err) {
            $err->rethrow();
        }
    }
}

sub _load {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'infra' ], optional => { 'config' => {} });

    # Firstly create the IAAS infrastructure, the nodes where are ditributed the IAAS service
    my $endpoints = {};
    my @services = grep { ref($args{config}->{$_}) eq "HASH" && defined $args{config}->{$_}->{hostname} }
                       keys %{ $args{config} };

    for my $service (@services) {
        if (! defined $endpoints->{$args{config}->{$service}->{hostname}}) {
            $endpoints->{$args{config}->{$service}->{hostname}} = [$service];
        }
        else {
            push @{ $endpoints->{$args{config}->{$service}->{hostname}} }, $service;
        }
    }

    # For each node, associate the IAAS component
    for my $hostname (keys %{ $endpoints }) {
        my $node = Entity::Node->findOrCreate(node_hostname => $hostname);

        $log->info("Associate component \"" . $self->label . "\" with node \"" . $node->label . "\"");
        my $master = (scalar(grep { $_ eq "identity" } @{ $endpoints->{$hostname} }) > 0) ? 1 : 0;
        $self->registerNode(node => $node, master_node => $master);
    }

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

    my $volume_types = {};
    for my $volume_type (@{ $args{infra}->{volume_types} }) {
        $volume_types->{delete $volume_type->{id}} = $volume_type;
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
            volume_types => $volume_types,
            flavors => $flavors,
            zones => $zones,
            images => $images,
            # TODO Remove following and find better method
            networks_name_id => $networks_name_id,
            tenants_name_id => $tenants_name_id,
        },
        override => 1,
    );

    my $hypervisor_list = {};
    my $vm_list = {};
    for my $hypervisor_info (@{$args{infra}->{hypervisors}}) {
        $hypervisor_list->{$hypervisor_info->{hypervisor_hostname}} = $hypervisor_info;
        for my $vm_info (@{$hypervisor_info->{servers}}) {
            $vm_list->{$vm_info->{id}} = $vm_info;
        }
    }

    $self->_synchronizeHypervisors(hypervisor_list => $hypervisor_list);
    $self->_synchronizeVirtualMachines(vm_list => $vm_list);

    my %images = map {$_->{file}, $_} @{$args{infra}->{images}};
    $self->_synchronizeMasterimages(images => \%images);

    return;
}
1;

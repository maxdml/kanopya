#    Copyright © 2011-2012 Hedera Technology SAS
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

Vsphere component version 5.
-> Manage connection to a vsphere instance (also works with single hypervisors instances)
-> Set and get component configuration
-> Retrieve vsphere entities (datacenters, clusters, hypervisors, vms)
-> Register vsphere entities into Kanopya (same than retrieve plus datastores/repositories)
-> Power on vms
-> promote virtual machines classes to Vsphere5Vm and hypervisors to Vsphere5Hypervisor

@since
@instance hash
@self $self

=end classdoc

=cut

package Entity::Component::Virtualization::Vsphere5;
use base "Entity::Component::Virtualization";
use base "Manager::HostManager::VirtualMachineManager";
use base "Manager::NetworkManager";

use strict;
use warnings;

use VMware::VIRuntime;

use General;
use Kanopya::Exceptions;
use Kanopya::Database;
use Entity::Repository::Vsphere5Repository;
use Vsphere5Datacenter;
use Entity::User;
use Entity::Policy;
use Entity::ServiceTemplate;
use Entity::ServiceProvider::Cluster;
use Entity::Host::VirtualMachine::Vsphere5Vm;
use Entity::Host::Hypervisor::Vsphere5Hypervisor;
use Entity::ContainerAccess;
use Entity::Host;

use TryCatch;
use Data::Dumper;
use Log::Log4perl "get_logger";

my $log = get_logger("");
my $errmsg;


use constant ATTR_DEF => {
    executor_component_id => {
        label        => 'Workflow manager',
        type         => 'relation',
        relation     => 'single',
        pattern      => '^[0-9\.]*$',
        is_mandatory => 1,
        is_editable  => 0,
    },
    repositories => {
        label       => 'Virtual machine images repositories',
        type        => 'relation',
        relation    => 'single_multi',
        is_editable => 1,
        specialized => 'Vsphere5Repository'
    },
    vsphere5_login => {
        label        => 'Login',
        type         => 'string',
        pattern      => '^.*$',
        is_mandatory => 1,
        is_editable  => 1
    },
    vsphere5_pwd => {
        label        => 'Password',
        type         => 'password',
        pattern      => '^.+$',
        is_mandatory => 1,
        is_editable  => 1
    },
    vsphere5_url => {
        label        => 'URL',
        pattern      => '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$',
        is_editable  => 1,
        is_mandatory => 1
    },
    # TODO: move this virtual attr to HostManager attr def when supported
    host_type => {
        is_virtual => 1
    }
};

sub getAttrDef { return ATTR_DEF; }

=pod

=begin classdoc

Declare the list of methods accessible from the API and their permissions

@return the list of methods with their descriptions and permissions

=end classdoc

=cut

sub methods {
    return {
        retrieveDatacenters =>  {
            description =>  'Retrieve a list of Datacenters',
        },
        retrieveClustersAndHypervisors =>  {
            description =>  'Retrieve a list of Clusters and Hypervisors (that are not in a cluster) ' .
                            'registered in a Datacenter',
        },
        retrieveClusterHypervisors =>  {
            description =>  'Retrieve a list of Hypervisors that are registered in a Cluster',
        },
        retrieveHypervisorVms =>  {
            description =>  'Retrieve a list of vms registered under a vsphere hypervisor',
        },
        register =>  {
            description =>  'Register a new item with the vsphere component',
        },
    };
}


sub new {
    my ($class, %args) = @_;
    General::checkParams(args     => \%args,
                         required => [ 'vsphere5_login', 'vsphere5_pwd', 'vsphere5_url' ]);

    # Initialize the param preset entry used to store available configuration
    my $self = $class->SUPER::new(%args);
    my $pp = ParamPreset->new();
    $self->param_preset_id($pp->id);
    $self->{vsphere} = undef;
    return $self;
}



sub create {
    my ($class, %args) = @_;
    General::checkParams(args     => \%args,
                         required => [ 'vsphere5_login', 'vsphere5_pwd', 'vsphere5_url' ]);

    Kanopya::Database::beginTransaction();
    my $self = $class->new(%args);

    # Try to connect to the API, to block registering the component if connexion infos are erroneous
    try {
        $self->connect();
    }
    catch ($err) {
        $log->error($err);
        Kanopya::Database::rollbackTransaction();
        throw Kanopya::Exception::Internal::WrongValue(
                  error => "Unable to connect to the vSphere IAAS, " .
                           "please check your connexion informations."
              );
    }

    Kanopya::Database::commitTransaction();
    return $self;
}


=pod
=begin classdoc

Return the boot policies for the host ruled by this host manager

=end classdoc
=cut

sub getBootPolicies {
    return (Manager::HostManager->BOOT_POLICIES->{virtual_disk},
            Manager::HostManager->BOOT_POLICIES->{pxe_iscsi},
            Manager::HostManager->BOOT_POLICIES->{pxe_nfs});
}


=pod
=begin classdoc

@return the manager params definition.

=end classdoc
=cut

sub getManagerParamsDef {
    my ($self, %args) = @_;

    return {
        %{ Manager::HostManager::getManagerParamsDef($self) },
        %{ Manager::NetworkManager::getManagerParamsDef($self) },
        core => {
            label        => 'Initial CPU number',
            type         => 'integer',
            unit         => 'core(s)',
            pattern      => '^\d*$',
            is_mandatory => 1
        },
        ram => {
            label        => 'Initial RAM amount',
            type         => 'integer',
            unit         => 'byte',
            pattern      => '^\d*$',
            is_mandatory => 1
        },
        max_core => {
            label        => 'Maximum CPU number',
            type         => 'integer',
            unit         => 'core(s)',
            pattern      => '^\d*$',
            is_mandatory => 1
        },
        max_ram => {
            label        => 'Maximum RAM amount',
            type         => 'integer',
            unit         => 'byte',
            pattern      => '^\d*$',
            is_mandatory => 1
        },
    };
}

sub checkHostManagerParams {
    my ($self,%args) = @_;

    General::checkParams(args => \%args, required => [ 'ram', 'core', 'max_core', 'max_ram' ]);
}

sub getHostManagerParams {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, optional => { "params" => {} });

    my $definition = $self->getManagerParamsDef();

    my $pp = $self->param_preset;

    my @dcs = map { $_->{name} } @{$pp->load()->{datacenters}} ;

    my $hash = {
        core       => $definition->{core},
        ram        => $definition->{ram},
        max_core   => $definition->{max_core},
        max_ram    => $definition->{max_ram},
        datacenter => {
            type        => 'enum',
            is_editable => 1,
            options     => \@dcs
        },
    };

    return $hash;
}


=pod
=begin classdoc

@return an available hypervisors by calling the capacity manager

@see <package>Manager::HostManager::VirtualMachineManager</package>

=end classdoc
=cut

sub selectHypervisor {
    my ($self, %args) = @_;
    General::checkParams(args => \%args,
                         optional => {
                             cluster => undef,
                             affinity => 'default',
                         },
                         required => [ 'ram', 'core', 'datacenter' ]);

    my $datacenter = Vsphere5Datacenter->find( name => $args{datacenter});

    my $hypervisors = Entity::Host::Hypervisor::Vsphere5Hypervisor->search( vsphere5_datacenter => $datacenter);

    my @hv_ids = map { $_->vsphere5_hypervisor_id} @{$hypervisors};

    $args{selected_hv_ids} = \@hv_ids;

    $self->SUPER::selectHypervisor(%args);

}


=pod
=begin classdoc

@return the network manager parameters as an attribute definition.

@see <package>Manager::NetworkManager</package>

=end classdoc
=cut

sub getNetworkManagerParams {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, optional => { "params" => {} });

    my $hash = Manager::NetworkManager::getNetworkManagerParams($self, %args);

    $hash->{interfaces}->{attributes}->{attributes}->{network}->{type} = 'enum';
    $hash->{interfaces}->{attributes}->{attributes}->{network}->{is_editable} = 1;

    my $pp = $self->param_preset;

    my @nets = map { @{$_->{network}} } @{$pp->load()->{datacenters}} ;

    $hash->{interfaces}->{attributes}->{attributes}->{network}->{options} = \@nets;

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

    Manager::NetworkManager::checkNetworkManagerParams($self, %args);

}


=pod
=begin classdoc

Get the basic configuration of the Vsphere component

@return %base_configuration

=end classdoc
=cut

sub getBaseConfiguration {
    return {
        vsphere5_login      => 'login',
        vsphere5_pwd        => 'password',
        vsphere5_url        => '127.0.0.1'
    };
}

=pod

=begin classdoc

Try to open a connection to a vCenter or ESXi instance

@param login the user name that will be used for the connection
@param pwd the user's password
@param url the url of the vCenter or ESXi instance

=end classdoc

=cut

sub connect {
    my ($self) = @_;
    # General::checkParams(args => \%args, required => ['user_name', 'password', 'url']);
    
    return if defined $self->{vsphere};
    
    my $service_url = $self->vsphere5_url;
    if ($service_url !~ m#://#) {
        $service_url = "https://".$service_url;
    }
    eval {
        $self->{vsphere} = Vim->new(service_url => $service_url);
        $self->{vsphere}->login(
            user_name => $self->vsphere5_login,
            password  => $self->vsphere5_pwd );
    };
    if ($@) {
        $errmsg = 'Could not connect to vCenter server: '.$@;
        throw Kanopya::Exception::Internal(error => $errmsg);
    }
    return;
}

=pod

=begin classdoc

End a session to a vCenter or ESXi instance

=end classdoc

=cut

sub disconnect {
    my ($self) = @_;
    return unless defined $self->{vsphere};
    
    eval {
        $self->{vsphere}->logout();
    };
    if ($@) {
        $errmsg = 'Could not disconnect from vCenter server: '.$@;
        throw Kanopya::Exception::Internal(error => $errmsg);
    }
    $log->debug('A connection to vSphere has been closed');
    $self->{vsphere} = undef;    
    return;
}


=pod
=begin classdoc

Register existing hypervisors, virtual machines
and all options available in the existing vSphere.

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

Retrieve a list of all datacenters

@param id_request ID of request (used to differentiate UI requests)

@return: \@datacenter_infos

=end classdoc
=cut

sub retrieveDatacenters {
    my ($self,%args) = @_;

    General::checkParams(args => \%args, optional => {'id_request' => undef});
    my @datacenters_infos;

    my $datacenter_views;
    eval {
        $datacenter_views = $self->findEntityViews(
                                   view_type      => 'Datacenter',
                                   array_property => ['name'],
                            );
    };
    if ($@) {
        my $errmsg = 'Error in datacenters retrieval:' . $@;
        throw Kanopya::Exception::Internal(error => $errmsg);
    }

    foreach my $datacenter_view (@$datacenter_views) {
        my %datacenter_infos = (
            name => $datacenter_view->name,
            type => 'datacenter',
         );
        push @datacenters_infos, \%datacenter_infos;
    }

    my $response = defined $args{id_request} ?
                       {
                           id_response => $args{id_request},
                           items_list  => \@datacenters_infos,
                       } :
                       \@datacenters_infos;
    return $response;
}


=pod
=begin classdoc

Retrieve a list of Clusters and Hypervisors (that are not in a cluster)
hosted in a given Datacenter

@param datacenter_name the datacenter name
@param id_request ID of request (used to differentiate UI requests)

@return \@clusters_and_hypervisors_infos

=end classdoc
=cut

sub retrieveClustersAndHypervisors {
    my ($self,%args) = @_;

    General::checkParams(
        args => \%args,
        required => ['datacenter_name'],
        optional => {'id_request' => undef}
    );

    my @clusters_hypervisors_infos;
    my $datacenter_name = $args{datacenter_name};

    #Find datacenter view
    my $datacenter_view = $self->findEntityView(
                              view_type   => 'Datacenter',
                              hash_filter => { name => $datacenter_name }
                          );
    #get datacenter host folder
    my $host_folder = $self->getView(mo_ref => $datacenter_view->hostFolder);

    #We only gather ClusterComputeResource or ComputeResource
    CHILD:
    foreach my $child (@{ $host_folder->childEntity || [] }) {

        my $child_view = $self->getView(mo_ref => $child);
        my $compute_resource_infos;

        if (ref ($child_view) eq 'ClusterComputeResource') {
            $compute_resource_infos = {
                name => $child_view->name,
                type => 'cluster',
            };
        }
        elsif (ref ($child_view) eq 'ComputeResource' && defined $child_view->host) {
            my $view = $self->getView(mo_ref => $child_view->host->[0]);
            my $uuid = $view->hardware->systemInfo->uuid;

            $compute_resource_infos = {
                name => $child_view->name,
                type => 'hypervisor',
                uuid => $uuid,
            };
        }
        else {
            next CHILD;
        }

        push @clusters_hypervisors_infos, $compute_resource_infos;
    }

    my $response = defined $args{id_request} ?
                       {
                           id_response => $args{id_request},
                           items_list  => \@clusters_hypervisors_infos,
                       } :
                       \@clusters_hypervisors_infos;

    return $response;
}

=pod
=begin classdoc

Retrieve a cluster's hypervisors

@param cluster_name the name of the target cluster
@param datacenter_name the name of the cluster's datacenter
@param id_request ID of request (used to differentiate UI requests)

@return \@hypervisors_infos

=end classdoc
=cut

sub retrieveClusterHypervisors {
    my ($self,%args) = @_;

    General::checkParams(
        args => \%args,
        required => ['cluster_name', 'datacenter_name'],
        optional => {'id_request' => undef}
    );

    # retrieve views
    my $datacenter_view = $self->findEntityView(
                              view_type   => 'Datacenter',
                              hash_filter => { name => $args{datacenter_name}},
                          );

    my $cluster_view    = $self->findEntityView(
                              view_type    => 'ClusterComputeResource',
                              hash_filter  => { name => $args{cluster_name}},
                              begin_entity => $datacenter_view,
                          );

    # retrieve the cluster's hypervisors details
    my $hypervisor_views  = $self->getViews(mo_ref_array => $cluster_view->host);
    my @hypervisors_infos;

    foreach my $hypervisor_view (@$hypervisor_views) {
        my %hypervisor_infos = (
            name => $hypervisor_view->name,
            type => 'clusterHypervisor',
            uuid => $hypervisor_view->hardware->systemInfo->uuid,
        );

        push @hypervisors_infos, \%hypervisor_infos;
    }

    my $response = defined $args{id_request} ?
                       {
                           id_response => $args{id_request},
                           items_list  => \@hypervisors_infos,
                       } :
                       \@hypervisors_infos;

    return $response;
}


=pod
=begin classdoc

Retrieve all the VM from a vsphere hypervisor

@param datacenter_name the name of the hypervisor's datacenter
@param hypervisor_name the name of the target hypervisor
@param id_request ID of request (used to differentiate UI requests)

@return \@vms_infos

=end classdoc
=cut

sub retrieveHypervisorVms {
    my ($self,%args) = @_;

    General::checkParams(
        args => \%args,
        required => [ 'datacenter_name', 'hypervisor_uuid' ],
        optional => { 'id_request' => undef }
    );

    # retrieve views
    my $datacenter_view = $self->findEntityView(
                              view_type   => 'Datacenter',
                              hash_filter => { name => $args{datacenter_name}},
                          );

    my $hypervisor_view = $self->findEntityView(
                              view_type    => 'HostSystem',
                              hash_filter  => {
                                  'hardware.systemInfo.uuid' => $args{hypervisor_uuid}
                              },
                              begin_entity => $datacenter_view,
                          );

    # get vms details
    my $vm_views = $self->getViews(mo_ref_array => $hypervisor_view->vm);
    my @vms_infos;

    foreach my $vm_view (@$vm_views) {
        my $vm_infos = {
            name => $vm_view->name,
            type => 'vm',
            uuid => $vm_view->config->uuid,
        };

        push @vms_infos, $vm_infos;
    }

    my $response = defined $args{id_request} ?
                       {
                           id_response => $args{id_request},
                           items_list  => \@vms_infos,
                       } :
                       \@vms_infos;

    return $response;
}


=pod
=begin classdoc

Retrieve all the networks from a vsphere datacenter

@param datacenter_name the name of the hypervisor's datacenter

@return \@networks

=end classdoc
=cut

sub retrieveNetworks {
    my ($self,%args) = @_;

    General::checkParams(
        args => \%args,
        required => [ 'datacenter_name' ],
    );

    my $networks = ();

    # retrieve views
    my $datacenter_view = $self->findEntityView(
                              view_type   => 'Datacenter',
                              hash_filter => { name => $args{datacenter_name}},
                          );

    my $network_views = $self->getViews( mo_ref_array => $datacenter_view->{network});

    for my $network_view (@{$network_views}) {
        # Discard uplinks networks
        my $tags = $network_view->{tag};
        if ( ! defined($tags) or ! grep { $_->{key} eq 'SYSTEM/DVS.UPLINKPG'} @{$tags}) {
            push @{$networks}, $network_view->{name};
        }
    }

    return $networks;
}

=pod
=begin classdoc

Retrieve all the datastore from a vsphere datacenter

@param datacenter_name the name of the hypervisor's datacenter

@return \@datacenters

=end classdoc
=cut

sub retrieveDatastores {
    my ($self,%args) = @_;

    General::checkParams(
        args => \%args,
        required => [ 'datacenter_name' ],
    );

    my $datastores = ();

    # retrieve views
    my $datacenter_view = $self->findEntityView(
                              view_type   => 'Datacenter',
                              hash_filter => { name => $args{datacenter_name}},
                          );

    my $datastore_views = $self->getViews( mo_ref_array => $datacenter_view->{datastore});

    for my $datastore_view (@{$datastore_views}) {
        # Only choose NFS datastores

        my $type = $datastore_view->{summary}->{type};
        if ( defined($type) and $type eq 'NFS' ) {
            my $datastore_info = {
                type      => $type,
                name      => $datastore_view->{name},
                size      => $datastore_view->{summary}->{capacity},
                freespace => $datastore_view->{summary}->{freespace},
                export    => $datastore_view->{info}->{nas}->{remotePath},
                ip        => $datastore_view->{info}->{nas}->{remoteHost},
                port      => '2049',
                options   => 'rw,no_root_squash',
            };
            push @{$datastores}, $datastore_info;
        }
    }

    return $datastores;
}


=pod
=begin classdoc

Get a vsphere managed object view

@param mo_ref the managed object reference

@return $view

=end classdoc
=cut

sub getView {
    my ($self,%args) = @_;

    General::checkParams(args => \%args, required => [ 'mo_ref' ]);

    $self->connect();

    my $view;
    eval {
        $view = $self->{vsphere}->get_view(mo_ref => $args{mo_ref});
    };
    if ($@) {
        $errmsg = 'Could not get view: '.$@;
        throw Kanopya::Exception::Internal(error => $errmsg);
    }

    return $view;
}


=pod
=begin classdoc

Get views of vsphere managed objects

@param mo_ref_array array of managed object references

@return views of managed objects

=end classdoc
=cut

sub getViews {
    my ($self,%args) = @_;

    General::checkParams(args => \%args, required => [ 'mo_ref_array' ]);

    $self->connect();

    my $views;
    eval {
        $views = $self->{vsphere}->get_views(mo_ref_array => $args{mo_ref_array});
    };
    if ($@) {
        $errmsg = 'Could not get views: '.$@;
        throw Kanopya::Exception::Internal(error => $errmsg);
    }

    return $views;
}


=pod
=begin classdoc

Find a view of a specified managed object type

@param view_type the type of the requested view. Can be one of the following:
    - HostSystem
    - VirtualMachine
    - Datacenter
    - Folder
    - ResourcePool
    - ClusterComputeResource
    - ComputeResource
@param hash_filter a hash containing the filter to be applied to the request

@optional array_property an array containing properties filter to be applied to the request
@optional begin_entity_view the inventory point where the function must start the research.
          Used to delimit the search to a specific sub-folder in the vsphere arborescence

@return view a managed entity view

=end classdoc
=cut

sub findEntityView {
    my ($self,%args) = @_;

    General::checkParams(
        args     => \%args,
        required => ['view_type','hash_filter'],
        optional => {
            'array_property' => undef,
            'begin_entity'   => undef,
        }
    );

    $self->connect();

    my $hash = {
        view_type    => $args{view_type},
        filter       => $args{hash_filter},
        properties   => $args{array_property},
    };
    $hash->{begin_entity} = $args{begin_entity} if (defined $args{begin_entity});

    my $view;
    eval {
        $view = $self->{vsphere}->find_entity_view(%$hash);
    };
    if ($@) {
        $errmsg = 'Could not get entity ' . keys(%{ $args{hash_filter} })
                  . ' of type ' . $args{view_type} . ': '. $@;
        throw Kanopya::Exception::Internal(error => $errmsg);
    }

    return $view;
}


=pod
=begin classdoc

Find some views of a specified managed object type

@param view_type the type of the requested views. Can be one of the following:
    - HostSystem
    - VirtualMachine
    - Datacenter
    - Folder
    - ResourcePool
    - ClusterComputeResource
    - ComputeResource
@param hash_filter a hash containing the filter to be applied to the request

@optional array_property an array containing properties filter to be applied to the request
@optional begin_entity_view the inventory point where the function must start the research.
          Used to delimit the search to a specific sub-folder in the vsphere arborescence

@return views a list of managed entity views

=end classdoc
=cut

sub findEntityViews {
    my ($self,%args) = @_;

    General::checkParams(args     => \%args,
                         required => ['view_type'],
                         optional => {
                             'hash_filter'    => undef,
                             'array_property' => undef,
                             'begin_entity'   => undef,
                         });

    $self->connect();

    my $hash = {
        view_type    => $args{view_type},
        filter       => $args{hash_filter},
        properties   => $args{array_property},
    };
    $hash->{begin_entity} = $args{begin_entity} if (defined $args{begin_entity});

    my $views;
    eval {
        $views = $self->{vsphere}->find_entity_views(%$hash);
    };
    if ($@) {
        $errmsg = 'Could not get entities of type ' . $args{view_type} . ': ' . $@;
        throw Kanopya::Exception::Internal(error => $errmsg);
    }

    return $views;
}


=pod
=begin classdoc

Register vSphere items into kanopya service providers

@param register_items a list of objects to the registered into Kanopya

@optional parent the parent object of the current item to be registered

@return registered_items a list of the registered items. Can be service providers or datacenters

=end classdoc
=cut

sub register {
    my ($self,%args) = @_;

    General::checkParams(args => \%args, required => ['register_items'],
                                         optional => {
                                             parent => undef,
                                         });

    my @register_items = @{ $args{register_items} };

    my %register_methods = (
        'cluster'    => 'registerCluster',
        'datacenter' => 'registerDatacenter',
        'hypervisor' => 'registerHypervisor',
        'vm'         => 'registerVm',
    );

    my @registered_items;
    foreach my $register_item (@register_items) {
        my $register_method = $register_methods{$register_item->{type}};

        my $registered_item;
        eval {
            $registered_item = $self->$register_method(
                                   name   => $register_item->{name},
                                   parent => $args{parent},
                                   uuid   => $register_item->{uuid},
                               );
        };
        if ($@) {
            $errmsg = 'Could not register '. $register_item->{name} .' in Kanopya: '. $@;
            throw Kanopya::Exception::Internal(error => $errmsg);
        }

        push @registered_items, $registered_item;

        if (defined ($register_item->{children}) &&
            scalar(@{ $register_item->{children} }) != 0) {

            $self->register(register_items => $register_item->{children},
                            parent         => $registered_item);
        }
    }

    return \@registered_items;
}


=pod
=begin classdoc

Register a new vsphere datacenter into Kanopya.
Check if the datacenter is already registered and linked to this component

@param name the name of the datacenter to be registered

@return datacenter the registered datacenter or an already existing one

=end classdoc
=cut

sub registerDatacenter {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => ['name']);

    my $datacenter;
    eval {
        $datacenter = Vsphere5Datacenter->find(hash => {
                          vsphere5_datacenter_name => $args{name},
                          vsphere5_id              => $self->id,
                      });
    };
    if ($@) {
        eval {
            $log->info("Registering Vsphere5Datacenter $args{name}.");
            $datacenter = Vsphere5Datacenter->new(
                              vsphere5_datacenter_name => $args{name},
                              vsphere5_id              => $self->id
                          );
        };
        if ($@) {
            $errmsg = 'Datacenter '. $args{name} .' could not be created: '. $@;
            throw Kanopya::Exception::Internal(error => $errmsg);
        }

        return $datacenter;
    }
    else {
        $errmsg  = 'Datacenter '. $args{name} .' already registered';
        $log->debug($errmsg);

        return $datacenter;
    }
}


=pod
=begin classdoc

Register a new virtual machine to match a vsphere vm
One cluster is created by vm registered. If a cluster with vm's name, that means the vm is already registered

@param name the name of the virtual machine to be registered
@param parent the parent service provider

@return service_provider

=end classdoc
=cut

sub registerVm {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => ['parent', 'name', 'uuid']);

    my $hosting_hypervisor = $args{parent};
    my $vm_uuid            = $args{uuid};
    my $sp_renamed         = $self->_formatName(name => $args{name}, type => 'cluster');
    my $node_renamed       = $self->_formatName(name => $args{name}, type => 'node');

    #Get the hypervisor view
    my $hypervisor_view = $self->findEntityView(
                              view_type   => 'HostSystem',
                              hash_filter => {
                                  'hardware.systemInfo.uuid' => $hosting_hypervisor->vsphere5_uuid,
                              }
                          );

    #get the VM view from vSphere
    my $vm_view = $self->findEntityView(view_type    => 'VirtualMachine',
                                        hash_filter  => { 'config.uuid' => $vm_uuid },
                                        begin_entity => $hypervisor_view);

    # One cluster created by vm registered
    my $service_provider;
    try {
        $service_provider = Entity::ServiceProvider::Cluster->find(hash => {
                                cluster_name => $sp_renamed,
                            });
    }
    catch {
        my $admin_user = Entity::User->find(hash => { user_login => 'admin' });

        $service_provider = Entity::ServiceProvider::Cluster->new(
            active                 => 1,
            cluster_name           => $sp_renamed,
            cluster_min_node       => 1,
            cluster_max_node       => 1,
            cluster_si_persistent  => 1,
            cluster_domainname     => 'my.domain',
            cluster_basehostname   => 'vsphere-registered-vm-' . $vm_view->summary->vm->value,
            cluster_nameserver1    => '127.0.0.1',
            cluster_nameserver2    => '127.0.0.1',
            owner_id               => $admin_user->id,
        );

        # policy and service template
        my $st = $self->_registerTemplate(policy_name  => 'vsphere_vm_policy',
                                          service_name => 'vSphere registered VMs');

        $service_provider->applyPolicies(pattern => { 'service_template_id' => $st->id });

        # Now set this manager as host manager for the new service provider
        $service_provider->addManager(manager_type => 'HostManager',
                                      manager_id   => $self->id);
    }

    my $virtual_machine;
    try {
        # Assuming we have one vm by service
        my @nodes = $service_provider->nodes;
        $virtual_machine = (pop(@nodes))->host;
    }
    catch {
        $virtual_machine = Entity::Host->new(
                               host_manager_id    => $self->id,
                               host_serial_number => '',
                               host_desc          => $hypervisor_view->name . ' vm',
                               active             => 1,
                               host_ram           => $vm_view->config->hardware->memoryMB * 1024 * 1024,
                               host_core          => $vm_view->config->hardware->numCPU,
                           );

        # TODO : add MAC addresses for vSphere registered hosts

        #promote new virtual machine class to a vsphere5Vm one
        $self->promoteVm(host          => $virtual_machine,
                         vm_uuid       => $vm_uuid,
                         hypervisor_id => $hosting_hypervisor->id,
                         guest_id      => $vm_view->config->guestId);

        # Register the node
        $service_provider->registerNode(host     => $virtual_machine,
                                        hostname => $node_renamed,
                                        number   => 1,
                                        state    => 'in');
    }

    # connected state : the fact that host is available or not for management
    # power state will be managed by state-manager
    my $host_state = $vm_view->runtime->connectionState->val eq 'connected'
                         ? 'up' : 'broken';

    $service_provider->cluster_state($host_state eq 'up' ? 'up:' . time() : 'down:' . time());
    $virtual_machine->host_state($host_state . ':' . time());

    return $service_provider;
}


=pod
=begin classdoc

Register a new host to match a vsphere hypervisor
Check if a matching service provider already exist in Kanopya and, if so, return it
instead of creating a new one

@param name the name of the hypervisor to be registered
@param parent the parent of the hypervisor (must be a Vsphere5Datacenter object)

@return service_provider

=end classdoc
=cut

sub registerHypervisor {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => ['parent','name', 'uuid']);

    my $datacenter   = $args{parent};
    my $dc_name      = $datacenter->vsphere5_datacenter_name;
    my $node_renamed = $self->_formatName(name => $args{name}, type => 'node');
    my $hv_uuid      = $args{uuid};

    my $vsphere_hyp;
    eval {
        $log->debug("Try to find existing hypervisor with $hv_uuid");
        $vsphere_hyp = Entity::Host::Hypervisor::Vsphere5Hypervisor->find(hash => {
                           vsphere5_uuid => $hv_uuid }
                       );
        $log->debug("Found existing hypervisor with $hv_uuid, " . $vsphere_hyp->label);
    };
    if ($@) {
        $log->debug("Not found, register a new one");
        my $datacenter_view = $self->findEntityView(
                                  view_type   => 'Datacenter',
                                  hash_filter => {
                                      name => $dc_name
                                  }
                              );
        my $hypervisor_view = $self->findEntityView(
                                  view_type    => 'HostSystem',
                                  hash_filter  => {
                                      'hardware.systemInfo.uuid' => $hv_uuid,
                                  },
                                  begin_entity => $datacenter_view,
                              );

        my $sp_name = $self->_formatName(name => $dc_name, type => 'cluster');

        $log->debug("Try to find the service $sp_name corresponding to the datacenter $dc_name");
        my $service_provider;
        try {
            $service_provider = Entity::ServiceProvider::Cluster->find(hash => { cluster_name => $sp_name });
        }
        catch {
            my $admin_user = Entity::User->find(hash => { user_login => 'admin' });

            (my $hostname = $sp_name) =~ s/_/-/;
            $service_provider = Entity::ServiceProvider::Cluster->new(
                service_template_id    => Entity::ServiceTemplate->findOrCreate(service_name => "vSphere registered Datacenters")->id,
                active                 => 1,
                cluster_name           => $sp_name,
                cluster_min_node       => 1,
                cluster_max_node       => 1,
                cluster_si_persistent  => 1,
                cluster_domainname     => 'my.domain',
                cluster_basehostname   => 'vsphere-datacenter-' . lc($hostname),
                cluster_nameserver1    => '127.0.0.1',
                cluster_nameserver2    => '127.0.0.1',
                owner_id               => $admin_user->id,
            );
        }

        # connected state : the fact that host is available or not for management
        # power state will be managed by state-manager
        my $host_state = $hypervisor_view->runtime->connectionState->val eq 'connected'
                             ? 'up' : 'broken';

        my $hv = Entity::Host->new(
                     host_serial_number => '',
                     host_desc          => $dc_name . ' hypervisor',
                     active             => 1,
                     host_ram           => $hypervisor_view->hardware->memorySize,
                     host_core          => $hypervisor_view->hardware->cpuInfo->numCpuCores,
                     host_state         => $host_state . ':' . time(),
                 );

        # TODO : add MAC addresses for vSphere registered hosts

        $log->debug("Add host " . $hv->label . " as hypervisor on vSphere " . $self->label);

        # promote new hypervisor class to a vsphere5Hypervisor one
        $vsphere_hyp = $self->addHypervisor(
                              host => $hv,
                              datacenter_id => $datacenter->id,
                              uuid => $hv_uuid
                          );


        $log->debug("Register hypervisor " . $vsphere_hyp->label .
                    " as node on service " . $service_provider->label);

        # Register the node
        my @nodes = $service_provider->nodes;
        $service_provider->registerNode(
            host     => $hv,
            hostname => $node_renamed,
            number   => scalar(@nodes),
            state    => 'in'
        );

        # TODO : state management + concurrent access
        my ($sp_state, $sp_timestamp) = $service_provider->getState;
        if ($host_state eq 'up' && $sp_state eq 'down') {
            $service_provider->setState(state => 'up');
        }

        return $vsphere_hyp;
    }
    else {
        $errmsg  = 'Hypervisor '. $args{name} .' already registered';
        $log->debug($errmsg);

        return $vsphere_hyp;
    }
}


=pod
=begin classdoc

Allow registering of hypervisors of a vsphere Cluster

@param name the name of the cluster to be registered
@param parent the parent of the cluster (must be a Vsphere5Datacenter object)

@return service_provider

=end classdoc
=cut

sub registerCluster {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => ['parent','name']);

    # we return datacenter since vsphere's clusters are not registered in Kanopya
    return $args{parent};
}


=pod
=begin classdoc

Launch a scale workflow that can be of type 'cpu' or 'memory'

@param host_id
@param scalein_value
@param scalein_type

=end classdoc
=cut

sub scaleHost {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host_id', 'scalein_value', 'scalein_type' ]);

    # vsphere requires memory value to be a multiple of 128 Mb
    if ($args{scalein_type} eq 'memory') {
        $args{scalein_value} -= $args{scalein_value} % (128 * 1024 * 1024);
    }

    $self->SUPER::scaleHost(%args);
}


=pod
=begin classdoc

Return a mac address auto generated and not used by any host

@return string mac adress

=end classdoc
=cut

sub generateMacAddress {
    my ($self) = @_;

    return $self->SUPER::generateMacAddress(
        regexp => '00:50:56:[0-3]{1}[a-f0-9]{1}:[a-f0-9]{2}:[a-f0-9]{2}'
    );
}


=pod
=begin classdoc

Register a new repository in kanopya for vSphere usage

@param repository_name the name of the datastore
@param container_access the Kanopya container access object associated to the datastore

@return $repository

=end classdoc
=cut

sub addRepository {
    my ($self,%args) = @_;

    General::checkParams(args => \%args, required => [ 'container_access' ]);

    return Entity::Repository::Vsphere5Repository->new(
               virtualization_id   => $self->id,
               repository_name     => $args{container_access}->container->container_name,
               container_access_id => $args{container_access}->id,
           );
}


=pod
=begin classdoc

Get one or all the datacenters attached to this vsphere component

@optional datacenter_name the name of a specific datacenter to be retrieved

@return $datacenters

=end classdoc
=cut

sub getDatacenters {
    my ($self,%args) = @_;

    my $datacenters;

    if (defined $args{datacenter_name}) {
        $datacenters  = Vsphere5Datacenter->find(
                            hash => {
                                vsphere5_id              => $self->id,
                                vsphere5_datacenter_name => $args{datacenter_name},
                            }
                        );
    }
    else {
        $datacenters  = Vsphere5Datacenter->search(
                               hash => { vsphere5_id => $self->id }
                        );
    }

    return $datacenters;
}


=pod
=begin classdoc

Get a repository corresponding to a container access

@param container_access_id the container access id associated to the repository to be retrieved

@return $repository

=end classdoc
=cut

sub getRepository {
    my ($self,%args) = @_;

    General::checkParams(args => \%args, required => [ 'container_access_id' ] );

    my $repository = Entity::Repository::Vsphere5Repository->find(hash => {
                         container_access_id => $args{container_access_id} }
                     );

    if (! defined $repository) {
        throw Kanopya::Exception::Internal(error => "No repository configured for Vsphere  " .$self->id);
    }

    return $repository;
}


=pod
=begin classdoc

Promote a virtual machine object to a Vsphere5Vm one

@param host the virtual machine host object to be promoted
@param guest_id the vmware guest id of the vm
@param hypervisor_id id of hypervisor hosting vm

@return vsphere5vm the promoted virtual machine

=end classdoc
=cut

sub promoteVm {
    my ($self, %args) = @_;

    General::checkParams(args => \%args,
                         required => [ 'host', 'vm_uuid', 'hypervisor_id' ],
                         optional => { 'guest_id' => 'debian6_64Guest' });

    $args{host} = Entity::Host::VirtualMachine::Vsphere5Vm->promote(
                      promoted           => $args{host},
                      vsphere5_id        => $self->id,
                      vsphere5_uuid      => $args{vm_uuid},
                      vsphere5_guest_id  => $args{guest_id},
                  );

    $args{host}->hypervisor_id($args{hypervisor_id});
    return $args{host};
}


sub _registerTemplate {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'policy_name', 'service_name' ]);

    my $hp_hash = { policy_name => $args{policy_name}, policy_type => 'hosting' };

    # policy
    my $hp;
    eval {
        $hp = Entity::Policy->find(hash => $hp_hash);
    };
    if ($@) {
        $hp = Entity::Policy->new(%$hp_hash);
    }

    # service template
    my $st = Entity::ServiceTemplate->findOrCreate(service_name => $args{service_name});
    $st->hosting_policy_id($hp->id);

    return $st;
}


=pod
=begin classdoc

Promote an Hypervisor class into a Vsphere5Hypervisor one

@param host the hypervisor class to be promoted
@param datacenter_id the id of the hypervisor's datacenter

@return vsphere5Hypervisor the promoted hypervisor

=end classdoc
=cut

sub addHypervisor {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host', 'datacenter_id', 'uuid' ]);

    return Entity::Host::Hypervisor::Vsphere5Hypervisor->promote(
               promoted               => $self->SUPER::addHypervisor(host => $args{host}),
               vsphere5_datacenter_id => $args{datacenter_id},
               vsphere5_uuid          => $args{uuid},
           );
}


=pod
=begin classdoc

Format a name that will be used for clusters and nodes creation

=end classdoc
=cut

sub _formatName {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'name', 'type' ]);

    my $name = $args{name};
    if ($args{type} eq 'cluster') {
        ($name = $args{name}) =~ s/[^A-Za-z0-9_]/_/g;
    }
    elsif ($args{type} eq 'node') {
        ($name = $args{name}) =~ s/[^\w\d_]/_/g;
    }

    return $name;
}

sub remove {
    my ($self, %args) = @_;
    $self->unregister();
    $self->SUPER::remove();
}

sub unregister {
    my ($self, %args) = @_;

    my @sis = $self->systemimages;
    if (@sis) {
        my $error = 'Cannot unregister vSphere: Still linked to a systemimage "'
                    . $sis[0]->label . '"';
        throw Kanopya::Exception::Internal(error => $error);
    }

    for my $datacenter ($self->vsphere5_datacenters) {
        $self->unregisterDatacenter(datacenter => $datacenter);
    }

    $self->removeMasterimages();
}


sub unregisterDatacenter {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'datacenter' ]);

    my @hypervisors = $args{datacenter}->vsphere5_hypervisors;

    $log->info($self->label . ", datacenter " . $args{datacenter}->label . " is managing " .
               scalar(@hypervisors) . " hypervisors, removing its.");

    my @services;
    for my $hypervisor (@hypervisors) {
        # If the hypervisor is linked to a service provider yet,
        # add it to the list of services to delete
        if (defined $hypervisor->node) {
            my $sp = $hypervisor->node->service_provider;
            if (defined $sp && scalar(grep { $_->id eq $sp->id } @services) <= 0) {
                push @services, $sp;
            }
        }

        $self->unregisterHypervisor(hypervisor => $hypervisor);
    }

    for my $service (@services) {
        $log->info("Removing service " . $service->label);
        $service->delete;
    }

    $args{datacenter}->delete;
}


sub unregisterHypervisor {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'hypervisor' ]);

    $log->info("Removing hypervisor " . $args{hypervisor}->label);

    my @vms = $args{hypervisor}->virtual_machines;

    $log->info("Hypervisor " . $args{hypervisor}->label . " is hosting " . scalar(@vms) .
               " virtual machines, removing its.");

    for my $vm (@vms) {
        $self->unregisterVm(vm => $vm);
    }

    if (defined $args{hypervisor}->node) {
        $args{hypervisor}->node->delete;
    }
    $args{hypervisor}->delete;
}


sub unregisterVm {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'vm' ]);

    $log->info("Removing virtual machine $args{vm}");
    if (defined $args{vm}->node) {
        my $service = $args{vm}->node->service_provider;
        $args{vm}->node->delete;

        if (defined $service) {
            $log->info("Removing service " . $service->label);
            $service->delete;
        }
    }
    $args{vm}->delete;
}

sub unregisterRepository {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'repository' ]);

    my $repository = $args{repository};

    $log->info("Removing repository: " . $repository->repository_name);
    my $container_access = $repository->container_access;
    if (defined $container_access) {
        my $container = $container_access->container;
        if (defined $container) {
            $container->delete;
        }
        $container_access->delete;
    }
    $repository->delete;
}


=pod
=begin classdoc

Remove related master images

=end classdoc
=cut

sub removeMasterimages {
    my ($self, %args) = @_;
}


=pod
=begin classdoc

Override the vmms relation to raise an execption as the vSphere iaas do not manage the hypervisors.

=end classdoc
=cut

sub vmms {
    my ($self, %args) = @_;

    throw Kanopya::Exception::Internal(error => "Hypervisors not managed by iaas " . $self->label);
}


=pod
=begin classdoc

override DESTROY to disconnect any open session toward a vSphere instance

=end classdoc
=cut

# sub DESTROY {
#     my $self = shift;

#     $self->disconnect();
# }

1;

# Cluster.pm - This object allows to manipulate cluster configuration
#    Copyright 2011 Hedera Technology SAS
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
# Created 3 july 2010
package Entity::ServiceProvider::Inside::Cluster;
use base 'Entity::ServiceProvider::Inside';

use strict;
use warnings;

use Kanopya::Exceptions;
use Entity::Component;
use Entity::Host;
use Externalnode::Node;
use Entity::Systemimage;
use Entity::Tier;
use Externalnode::Node;
use Operation;
use Workflow;
use NodemetricCombination;
use Clustermetric;
use AggregateCombination;
use Policy;
use Administrator;
use General;
use ServiceProviderManager;
use ServiceTemplate;
use VerifiedNoderule;
use Entity::Billinglimit;
use Entity::Component::Kanopyaworkflow0;
use Entity::Component::Kanopyacollector1;

use Hash::Merge;

use Log::Log4perl "get_logger";
use Data::Dumper;

our $VERSION = "1.00";

my $log = get_logger("administrator");
my $errmsg;

use constant ATTR_DEF => {
    cluster_name => {
        pattern      => '^\w+$',
        is_mandatory => 1,
        is_extended  => 0,
        is_editable  => 0
    },
    cluster_desc => {
        pattern      => '^.*$',
        is_mandatory => 0,
        is_extended  => 0,
        is_editable  => 1
    },
    cluster_type => {
        pattern      => '^.*$',
        is_mandatory => 0,
        is_extended  => 0,
        is_editable  => 0
    },
    cluster_boot_policy => {
        pattern      => '^.*$',
        is_mandatory => 0,
        is_extended  => 0,
        is_editable  => 0
    },
    cluster_si_shared => {
        pattern      => '^(0|1)$',
        is_mandatory => 1,
        is_extended  => 0,
        is_editable  => 0
    },
    cluster_si_persistent => {
        pattern      => '^(0|1)$',
        is_mandatory => 1,
        is_extended  => 0,
        is_editable  => 0
    },
    cluster_min_node => {
        pattern      => '^\d*$',
        is_mandatory => 1,
        is_extended  => 0,
        is_editable  => 1
    },
    cluster_max_node => {
        pattern      => '^\d*$',
        is_mandatory => 1,
        is_extended  => 0,
        is_editable  => 1
    },
    cluster_priority => {
        pattern      => '^\d*$',
        is_mandatory => 1,
        is_extended  => 0,
        is_editable  => 1
    },
    cluster_state => {
        pattern      => '^up:\d*|down:\d*|starting:\d*|stopping:\d*$',
        is_mandatory => 0,
        is_extended  => 0,
        is_editable  => 0
    },
    cluster_domainname => {
        pattern      => '^[a-z0-9-]+(\.[a-z0-9-]+)+$',
        is_mandatory => 1,
        is_extended  => 0,
        is_editable  => 0
    },
    cluster_nameserver1 => {
        pattern      => '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$',
        is_mandatory => 1,
        is_extended  => 0,
        is_editable  => 0
    },
    cluster_nameserver2 => {
        pattern      => '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$',
        is_mandatory => 1,
        is_extended  => 0,
        is_editable  => 0
    },
    cluster_basehostname => {
        pattern      => '^[a-z_0-9]+$',
        is_mandatory => 1,
        is_extended  => 0,
        is_editable  => 1
    },
    active => {
        pattern      => '^[01]$',
        is_mandatory => 0,
        is_extended  => 0,
        is_editable  => 0
    },
    masterimage_id => {
        pattern      => '\d*',
        is_mandatory => 0,
        is_extended  => 0,
        is_editable  => 0
    },
    kernel_id => {
        pattern      => '^\d*$',
        is_mandatory => 0,
        is_extended  => 0,
        is_editable  => 1
    },
	user_id => {
        pattern      => '^\d+$',
        is_mandatory => 1,
        is_extended  => 0,
        is_editable  => 0
    },
};

sub getAttrDef { return ATTR_DEF; }

sub methods {
    return {
        'create'    => {'description' => 'create a new cluster',
                        'perm_holder' => 'mastergroup',
        },
        'get'        => {'description' => 'view this cluster',
                        'perm_holder' => 'entity',
        },
        'update'    => {'description' => 'save changes applied on this cluster',
                        'perm_holder' => 'entity',
        },
        'remove'    => {'description' => 'delete this cluster',
                        'perm_holder' => 'entity',
        },
        'addNode'    => {'description' => 'add a node to this cluster',
                        'perm_holder' => 'entity',
        },
        'removeNode'=> {'description' => 'remove a node from this cluster',
                        'perm_holder' => 'entity',
        },
        'activate'=> {'description' => 'activate this cluster',
                        'perm_holder' => 'entity',
        },
        'deactivate'=> {'description' => 'deactivate this cluster',
                        'perm_holder' => 'entity',
        },
        'start'=> {'description' => 'start this cluster',
                        'perm_holder' => 'entity',
        },
        'stop'=> {'description' => 'stop this cluster',
                        'perm_holder' => 'entity',
        },
        'forceStop'=> {'description' => 'force stop this cluster',
                        'perm_holder' => 'entity',
        },
        'setperm'    => {'description' => 'set permissions on this cluster',
                        'perm_holder' => 'entity',
        },
        'addComponent'    => {'description' => 'add a component to this cluster',
                        'perm_holder' => 'entity',
        },
        'removeComponent'    => {'description' => 'remove a component from this cluster',
                        'perm_holder' => 'entity',
        },
        'configureComponents'    => {'description' => 'configure components of this cluster',
                        'perm_holder' => 'entity',
        },
    };
}

=head2 getClusters

=cut

sub getClusters {
    my $class = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => ['hash']);

    return $class->search(%args);
}

sub getCluster {
    my $class = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => ['hash']);

    my @clusters = $class->search(%args);
    return pop @clusters;
}

sub checkConfigurationPattern {
    my $self = shift;
    my $class = ref($self) || $self;
    my %args = @_;

    General::checkParams(args => \%args, required => [ 'attrs' ]);

    # Firstly, check the cluster attrs
    $class->checkAttrs(attrs => $args{attrs});

    # Then check the configuration if required
    if (defined $args{composite}) {

        # For now, only check the manaher paramters only
        for my $manager_def (values %{ $args{composite}->{managers} }) {
            if (defined $manager_def->{manager_id}) {
                my $manager = Entity->get(id => $manager_def->{manager_id});

                $manager->checkManagerParams(manager_type   => $manager_def->{manager_type},
                                             manager_params => $manager_def->{manager_params});
            }
        }

        # TODO: Check cross managers dependencies. For example, the list of
        #       disk managers depend on the host manager.
    }
}

=head2 create

    %params => {
        cluster_name     => 'foo',
        cluster_desc     => 'bar',
        cluster_min_node => 1,
        cluster_max_node => 10,
        masterimage_id   => 4,
        ...
        managers => {
            host_manager => {
                manager_id     => 2,
                manager_type   => 'host_manager',
                manager_params => {
                    cpu => 2,
                    ram => 1024,
                },
            },
            disk_manager => { ... },
        },
        policies => {
            hosting => 45,
            storage => 54,
            network => 32,
            ...
        },
        interfaces => {
            admin => {
                interface_role => 'admin',
                interfaces_networks => [ 1 ],
            }
        },
        components => {
            puppet => {
                component_type => 42,
            },
        },
    };

=cut

sub create {
    my ($class, %params) = @_;

    my $admin = Administrator->new();
    my $mastergroup_eid = $class->getMasterGroupEid();
    my $granted = $admin->{_rightchecker}->checkPerm(entity_id => $mastergroup_eid, method => 'create');
    if (not $granted) {
        throw Kanopya::Exception::Permission::Denied(error => "Permission denied to create a new user");
    }

    # Override params with poliies param presets
    my $merge = Hash::Merge->new('RIGHT_PRECEDENT');

    # Prepare the configuration pattern from the service template
    if (defined $params{service_template_id}) {
        # ui related, we get the completed values as flatened values from the form
        # so we need to transform all the flatened params to a configuration pattern.
        my %flatened_params = %params;
        %params = ();

        my $service_template = ServiceTemplate->get(id => $flatened_params{service_template_id});
        for my $policy (@{ $service_template->getPolicies }) {
            # Register policy ids in the params
            push @{ $params{policies} }, $policy->getAttr(name => 'policy_id');

            # Rebuild params as a configuration pattern
            my $pattern = Policy->buildPatternFromHash(policy_type => $policy->getAttr(name => 'policy_type'), hash => \%flatened_params);
            %params = %{ $merge->merge(\%params, \%$pattern) };
        }
    }

    

    General::checkParams(args => \%params, required => [ 'managers' ]);
    General::checkParams(args => $params{managers}, required => [ 'host_manager', 'disk_manager' ]);

    # Firstly apply the policies presets on the cluster creation paramters.
    for my $policy_id (@{ $params{policies} }) {
        my $policy = Policy->get(id => $policy_id);

        # Load params preset into hash
        my $policy_presets = $policy->getParamPreset->load();

        # Merge current polciy preset with others
        %params = %{ $merge->merge(\%params, \%$policy_presets) };
    }

    delete $params{policies};

    $log->debug("Final parameters after applying policies:\n" . Dumper(%params));

    my %composite_params;
    for my $name ('managers', 'interfaces', 'components', 'billing_limits') {
        if ($params{$name}) {
            $composite_params{$name} = delete $params{$name};
        }
    }

    $class->checkConfigurationPattern(attrs => \%params, composite => \%composite_params);

    $log->debug("New Operation Create with attrs : " . %params);
    Operation->enqueue(
        priority => 200,
        type     => 'AddCluster',
        params   => {
            cluster_params => \%params,
            presets        => \%composite_params,
        },
    );
}

sub applyPolicies {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ "presets" ]);

    my ($name, $value);
    for my $name (keys %{ $args{presets} }) {
        $value = $args{presets}->{$name};

        # Handle managers cluster config
        if ($name eq 'managers') {
            $self->configureManagers(managers => $value);
        }
        # Handle components cluster config
        elsif ($name eq 'components') {
            for my $component (values %$value) {
                # TODO: Check if the component is already installed
                my $instance = $self->addComponentFromType(component_type_id => $component->{component_type});
                if (defined $component->{component_configuration}) {
                    $instance->setConf($component->{component_configuration});
                }
            }
        }
        # Handle network interfaces cluster config
        elsif ($name eq 'interfaces') {
            $self->configureInterfaces(interfaces => $value);
        }
        elsif ($name eq 'billing_limits') {
            $self->configureBillingLimits(billing_limits => $value);
        }
        else {
            $self->setAttr(name => $name, value => $value);
        }
    }
    $self->save();
}

sub configureManagers {
    my $self = shift;
    my %args = @_;

    # Workaround to handle connectors that have btoh category.
    # We need to fix this when we willmerge inside/outside.
    my ($wok_disk_manager, $wok_export_manager);
    eval {
        $wok_disk_manager   = $args{managers}->{disk_manager}->{manager_id};
        $wok_export_manager = $args{managers}->{export_manager}->{manager_id};
    };
    if ($wok_disk_manager and $wok_export_manager) {
        my $kanopya = Entity->get(id => 1);
        # FileImagaemanager0 -> FileImagaemanager0
        if ($wok_disk_manager != $kanopya->getComponent(name => "Lvm", version => "2")->getAttr(name => 'component_id')) {
            $args{managers}->{export_manager}->{manager_id} = $wok_disk_manager;
        }
    }

    # Install new managers or/and new managers params if required
    if (defined $args{managers}) {
        # Add default workflow manager
        my $workflow_manager = Entity::Component::Kanopyaworkflow0->find(hash => { service_provider_id => 1 });
        $args{managers}->{workflow_manager} = {
            manager_id   => $workflow_manager->getId,
            manager_type => "workflow_manager"
        };

        # Add default collector manager
        my $collector_manager = Entity::Component::Kanopyacollector1->find(hash => { service_provider_id => 1 });
        $args{managers}->{collector_manager} = {
            manager_id   => $collector_manager->getId,
            manager_type => "collector_manager"
        };

        for my $manager (values %{$args{managers}}) {
            # Check if the manager is already set, add it otherwise,
            # and set manager parameters if defined.
            my $cluster_manager;
            eval {
                $cluster_manager = ServiceProviderManager->find(hash => { manager_type        => $manager->{manager_type},
                                                                          service_provider_id => $self->getId });
            };
            if ($@) {
                next if not $manager->{manager_id};
                $cluster_manager = $self->addManager(manager      => Entity->get(id => $manager->{manager_id}),
                                                     manager_type => $manager->{manager_type});
            }
            if ($manager->{manager_params}) {
                $cluster_manager->addParams(params => $manager->{manager_params}, override => 1);
            }
        }
    }

    my $disk_manager   = $self->getManager(manager_type => 'disk_manager');
    my $export_manager = eval { $self->getManager(manager_type => 'export_manager') };

    # If the export manager exists, deduce the boot policy
    if ($export_manager) {
        my $bootpolicy = $disk_manager->getBootPolicyFromExportManager(export_manager => $export_manager);
        $self->setAttr(name => 'cluster_boot_policy', value => $bootpolicy);
        $self->save();
    }
    # Else use the boot policy to deduce the export manager to use
    else {
        $export_manager = $disk_manager->getExportManagerFromBootPolicy(
                              boot_policy => $self->getAttr(name => 'cluster_boot_policy')
                          );

        $self->addManager(manager => $export_manager, manager_type => "export_manager");
    }

    # Get export manager parameter related to si shared value.
    my $readonly_param = $export_manager->getReadOnlyParameter(
                             readonly => $self->getAttr(name => 'cluster_si_shared')
                         );
    # TODO: This will be usefull for the first call to applyPolicies at the cluster creation,
    #       but there will be export manager params consitency problem if policies are updated.
    if ($readonly_param) {
        $self->addManagerParameter(
            manager_type => 'export_manager',
            name         => $readonly_param->{name},
            value        => $readonly_param->{value}
        );
    }
}

sub configureInterfaces {
    my $self = shift;
    my %args = @_;

    if (defined $args{interfaces}) {
        for my $interface_pattern (values %{ $args{interfaces} }) {
            if ($interface_pattern->{interface_role}) {
                my $role = Entity::InterfaceRole->get(id => $interface_pattern->{interface_role});

                # TODO: This mechanism do not allows to define many interfaces
                #       with the same role within policies.

                # Check if an interface with the same role already set, add it otherwise,
                # Add networks to the interrface if not exists.
                my $interface;
                eval {
                    $interface = Entity::Interface->find(
                                     hash => { service_provider_id => $self->getAttr(name => 'entity_id'),
                                               interface_role_id   => $role->getAttr(name => 'entity_id') }
                                 );
                };
                if ($@) {
                    my $default_gateway = (defined $interface_pattern->{default_gateway} && $interface_pattern->{default_gateway} == 1) ? 1 : 0;
                    $interface = $self->addNetworkInterface(interface_role  => $role,
                                                            default_gateway => $default_gateway);
                }

                if ($interface_pattern->{interface_networks}) {
                    for my $network_id (@{ $interface_pattern->{interface_networks} }) {
                        eval {
                            $interface->associateNetwork(network => Entity::Network->get(id => $network_id));
                        };
                        if($@) {
                            my $msg = '>>>>> interface '.$interface->getAttr(name => 'interface_id');
                            $msg .= 'already associated with network'.$network_id;
                            $log->debug($msg);
                        }
                    }
                }
            }
        }
    }
}

sub configureBillingLimits {
    my $self    = shift;
    my %args    = @_;

    if (defined($args{billing_limits})) {
        foreach my $name (keys %{$args{billing_limits}}) {
            my $value = $args{billing_limits}->{$name};
            Entity::Billinglimit->new(
                start               => $value->{start},
                ending              => $value->{ending},
                type                => $value->{type},
                soft                => $value->{soft},
                service_provider_id => $self->getAttr(name => 'entity_id'),
                repeats             => $value->{repeats},
                repeat_start_time   => $value->{repeat_start_time},
                repeat_end_time     => $value->{repeat_end_time},
                value               => $value->{value}
            );
        }
    }
}

=head2 update

=cut

sub update {
    my $self = shift;
    my $adm = Administrator->new();
    # update method concerns an existing entity so we use his entity_id
       my $granted = $adm->{_rightchecker}->checkPerm(entity_id => $self->{_entity_id}, method => 'update');
       if(not $granted) {
           throw Kanopya::Exception::Permission::Denied(error => "Permission denied to update this entity");
       }
    # TODO update implementation
}

=head2 remove

=cut

sub remove {
    my $self = shift;
    my $adm = Administrator->new();

    # delete method concerns an existing entity so we use his entity_id
    my $granted = $adm->{_rightchecker}->checkPerm(entity_id => $self->{_entity_id}, method => 'delete');
    if (not $granted) {
        throw Kanopya::Exception::Permission::Denied(error => "Permission denied to delete this entity");
    }

    $log->debug("New Operation Remove Cluster with cluster id : " .  $self->getAttr(name => 'cluster_id'));
    Operation->enqueue(
        priority => 200,
        type     => 'RemoveCluster',
        params   => {
            context => {
                cluster => $self,
            },
        },
    );
}

sub forceStop {
    my $self = shift;
    my $adm = Administrator->new();

    # delete method concerns an existing entity so we use his entity_id
    my $granted = $adm->{_rightchecker}->checkPerm(entity_id => $self->{_entity_id}, method => 'forceStop');
    if (not $granted) {
        throw Kanopya::Exception::Permission::Denied(error => "Permission denied to force stop this entity");
    }

    $log->debug("New Operation Force Stop Cluster with cluster: " . $self->getAttr(name => "cluster_id"));
    Operation->enqueue(
        priority => 200,
        type     => 'ForceStopCluster',
        params   => {
            context => {
                cluster => $self,
            },
        },
    );
}

sub extension { return "clusterdetails"; }

sub activate {
    my $self = shift;

    $log->debug("New Operation ActivateCluster with cluster_id : " . $self->getAttr(name => 'cluster_id'));
    Operation->enqueue(
        priority => 200,
        type     => 'ActivateCluster',
        params   => {
            context => {
                cluster => $self,
            },
        },
    );
}

sub deactivate {
    my $self = shift;

    $log->debug("New Operation DeactivateCluster with cluster_id : " . $self->getAttr(name => 'cluster_id'));
    Operation->enqueue(
        priority => 200,
        type     => 'DeactivateCluster',
        params   => {
            context => {
                cluster => $self,
            },
        },
    );
}



sub getTiers {
    my $self = shift;

    my %tiers;
    my $rs_tiers = $self->{_dbix}->tiers;
    if (! defined $rs_tiers) {
        return;
    }
    else {
        my %tiers;
        while ( my $tier_row = $rs_tiers->next ) {
            my $tier_id = $tier_row->get_column("tier_id");
            $tiers{$tier_id} = Entity::Tier->get(id => $tier_id);
        }
    }
    return \%tiers;
}


=head2 toString

    desc: return a string representation of the entity

=cut

sub toString {
    my $self = shift;
    my $string = $self->{_dbix}->get_column('cluster_name');
    return $string.' (Cluster)';
}

=head2 getComponents

    Desc : This function get components used in a cluster. This function allows to select
            category of components or all of them.
    args:
        administrator : Administrator : Administrator object to instanciate all components
        category : String : Component category
    return : a hashref of components, it is indexed on component_instance_id

=cut

sub getComponents {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => ['category']);

    my $components_rs = $self->{_dbix}->parent->search_related("components", undef,
		{ '+columns' => { "component_name"     => "component_type.component_name",
						  "component_version"  => "component_type.component_version",
						  "component_category" => "component_type.component_category"},
	   join => ["component_type"]}
	);

    my %comps;
    $log->debug("Category is $args{category}");
    while ( my $component_row = $components_rs->next ) {
        my $comp_id           = $component_row->get_column('component_id');
        my $comptype_category = $component_row->get_column('component_category');
        my $comptype_name     = $component_row->get_column('component_name');
        my $comptype_version  = $component_row->get_column('component_version');

        $log->debug("Component name: $comptype_name");
        $log->debug("Component version: $comptype_version");
        $log->debug("Component category: $comptype_category");
        $log->debug("Component id: $comp_id");

        if (($args{category} eq "all")||
            ($args{category} eq $comptype_category)){
            $log->debug("One component instance found with " . ref($component_row));
            my $class= "Entity::Component::" . $comptype_name . $comptype_version;
            my $loc = General::getLocFromClass(entityclass=>$class);
            eval { require $loc; };
            $comps{$comp_id} = $class->get(id =>$comp_id);
        }
    }
    return \%comps;
}

=head2 getComponent

    Desc : This function get component used in a cluster. This function allows to select
            a particular component with its name and version.
    args:
        administrator : Administrator : Administrator object to instanciate all components
        name : String : Component name
        version : String : Component version
    return : a component instance

=cut

sub getComponent{
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => ['name','version']);

    my $hash = {
        'component_type.component_name'    => $args{name},
        'component_type.component_version' => $args{version}
    };

    my $component_row;
    eval {
        my $components_rs = $self->{_dbix}->parent->search_related(
                                "components", $hash,
                                { "+columns" =>
                                    { "component_name"     => "component_type.component_name",
                                      "component_version"  => "component_type.component_version",
                                      "component_category" => "component_type.component_category" },
                                  join => [ "component_type" ] }
                            );

        $log->debug("Name is $args{name}, version is $args{version}");

        $component_row = $components_rs->next;
    };
    if (not defined $component_row or $@) {
        throw Kanopya::Exception::Internal(
                  error => "Component with name <$args{name}>, version <$args{version}> " .
                           "not installed on this cluster:\n$@"
              );
    }

    $log->debug("Comp name is " . $component_row->get_column('component_name'));
    $log->debug("Component found with " . ref($component_row));

    my $comp_category = $component_row->get_column('component_category');
    my $comp_id       = $component_row->id;
    my $comp_name     = $component_row->get_column('component_name');
    my $comp_version  = $component_row->get_column('component_version');

    my $class= "Entity::Component::" . $comp_name . $comp_version;
    my $loc = General::getLocFromClass(entityclass => $class);

    eval { require $loc; };
    if ($@) {
        throw Kanopya::Exception::Internal::UnknownClass(error => "Could not find $loc :\n$@");
    }
    return "$class"->get(id => $comp_id);
}

sub getComponentByInstanceId{
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => ['component_instance_id']);

    my $hash = {'component_instance_id' => $args{component_instance_id}};
    my $comp_instance_rs = $self->{_dbix}->search_related("component_instances", $hash,
                                            { '+columns' => {"component_name" => "component.component_name",
                                                            "component_version" => "component.component_version",
                                                            "component_category" => "component.component_category"},
                                                    join => ["component"]});

    my $comp_instance_row = $comp_instance_rs->next;
    if (not defined $comp_instance_row) {
        throw Kanopya::Exception::Internal(error => "Component with component_instance_id '$args{component_instance_id}' not found on this cluster");
    }
    $log->debug("Comp name is " . $comp_instance_row->get_column('component_name'));
    $log->debug("Component instance found with " . ref($comp_instance_row));
    my $comp_category = $comp_instance_row->get_column('component_category');
    my $comp_instance_id = $comp_instance_row->get_column('component_instance_id');
    my $comp_name = $comp_instance_row->get_column('component_name');
    my $comp_version = $comp_instance_row->get_column('component_version');
    my $class= "Entity::Component::" . $comp_name . $comp_version;
    my $loc = General::getLocFromClass(entityclass=>$class);
    eval { require $loc; };
    return "$class"->get(id =>$comp_instance_id);
}

sub getMasterNode {
    my $self = shift;
    my $node_instance_rs = $self->{_dbix}->parent->search_related(
                               "nodes", { master_node => 1 }
                           )->single;

    if(defined $node_instance_rs) {
        my $host = { _dbix => $node_instance_rs->host };
        bless $host, "Entity::Host";
        return $host;
    } else {
        $log->debug("No Master node found for this cluster");
        return;
    }
}

sub getMasterNodeIp {
    my $self = shift;
    my $master = $self->getMasterNode();

    if ($master) {
        my $node_ip = $master->getAdminIp;

        $log->debug("Master node found and its ip is $node_ip");
        return $node_ip;
    }
}

sub getMasterNodeFQDN {
    my ($self) = @_;
    my $domain = $self->getAttr(name => 'cluster_domainname');
    my $master = $self->getMasterNode();
    my $hostname = $master->getAttr(name => 'host_hostname');
    return $hostname.'.'.$domain;
}

sub getMasterNodeId {
    my $self = shift;
    my $host = $self->getMasterNode;

    if (defined ($host)) {
        return $host->getAttr(name => "host_id");
    }
}

sub getMasterNodeSystemimage {
    my $self = shift;
    my $node_instance_rs = $self->{_dbix}->parent->search_related(
                               "nodes", { master_node => 1 }
                           )->single;

    if(defined $node_instance_rs) {
        return Entity::Systemimage->get(id => $node_instance_rs->get_column('systemimage_id'));
    }
}

=head2 addComponent

link a existing component with the cluster

=cut

sub addComponent {
    my $self = shift;
    my %args = @_;
    my $noconf;

    General::checkParams(args => \%args, required => ['component']);

    my $component = $args{component};
    $component->setAttr(name  => 'service_provider_id',
                        value => $self->getAttr(name => 'cluster_id'));
    $component->save();

    return $component;
}

=head2 addComponentFromType

create a new componant and link it to the cluster

=cut

sub addComponentFromType {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => ['component_type_id']);

    my $type_id = $args{component_type_id};
    my $adm = Administrator->new();
    my $row = $adm->{db}->resultset('ComponentType')->find($type_id);
    my $comp_name = $row->get_column('component_name');
    my $comp_version = $row->get_column('component_version');
    my $comp_class = 'Entity::Component::'.$comp_name.$comp_version;
    my $location = General::getLocFromClass(entityclass => $comp_class);
    eval {require $location };
    my $component = $comp_class->new();

    return $self->addComponent(component => $component);
}

=head2 removeComponent

remove a component instance and all its configuration
from this cluster

=cut

sub removeComponent {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => ['component_instance_id']);

    my $component_instance = Entity::Component->get(id => $args{component_instance_id});
    $component_instance->delete;
}

=head2 getHosts

    Desc : This function get hosts executing the cluster.
    args:
        administrator : Administrator : Administrator object to instanciate all components
    return : a hashref of host, it is indexed on host_id

=cut

sub getHosts {
    my $self = shift;

    my %hosts;
    eval {
        my @nodes = Externalnode::Node->search(hash => { inside_id => $self->getId });
        for my $node (@nodes) {
            my $host = $node->host;
            my $host_id = $host->getId;
            eval {
                $hosts{$host_id} = $host;
            };
            $log->debug("Host $host_id found in cluster " . $self->getId);
        }
    };
    if ($@) {
        throw Kanopya::Exception::Internal(
                  error => "Could not get cluster nodes:\n$@"
              );
    }
    return \%hosts;
}

=head2 getHostManager

    desc: Return the component/conector that manage this cluster.

=cut

sub getHostManager {
    my $self = shift;

    return $self->getManager(manager_type => 'host_manager');
}

=head2 getCurrentNodesCount

    class : public
    desc : return the current nodes count of the cluster

=cut

sub getCurrentNodesCount {
    my $self = shift;
    my $nodes = $self->{_dbix}->parent->nodes;
    if ($nodes) {
    return $nodes->count;}
    else {
        return 0;
    }
}

sub getPublicIps {
    my $self = shift;

    my $publicip_rs = $self->{_dbix}->ipv4_publics;
    my $i =0;
    my @pub_ip =();
    while ( my $publicip_row = $publicip_rs->next ) {
        my $publicip = {publicip_id => $publicip_row->get_column('ipv4_public_id'),
                        address => $publicip_row->get_column('ipv4_public_address'),
                        netmask => $publicip_row->get_column('ipv4_public_mask'),
                        gateway => $publicip_row->get_column('ipv4_public_default_gw'),
                        name     => "eth0:$i",
                        cluster_id => $self->{_dbix}->get_column('cluster_id'),
        };
        $i++;
        push @pub_ip, $publicip;
    }
    return \@pub_ip;
}

=head2 getQoSConstraints

    Class : Public

    Desc :

=cut

sub getQoSConstraints {
    my $self = shift;
    my %args = @_;

    # TODO retrieve from db (it's currently done by RulesManager, move here)
    return { max_latency => 22, max_abort_rate => 0.3 } ;
}

=head2 addNode

=cut

sub addNode {
    my $self = shift;
    my %args = @_;

    my $adm = Administrator->new();

    # Check Rights
    # addNode method concerns an existing entity so we use his entity_id
    my $granted = $adm->{_rightchecker}->checkPerm(entity_id => $self->{_entity_id},
                                                   method    => 'addNode');
    if (not $granted) {
        throw Kanopya::Exception::Permission::Denied(
                  error => "Permission denied to add a node to this cluster"
              );
    }

    return Workflow->run(
        name => 'AddNode',
        params   => {
            context => {
                cluster => $self,
            }
        }
    );
}

sub getHostConstraints {
    my $self = shift;

    #TODO BIG IA, HYPER INTELLIGENCE TO REMEDIATE CONSTRAINTS CONFLICTS
    my $components = $self->getComponents(category=>"all");

    # Return the first constraint found.
    foreach my $k (keys %$components) {
        my $constraints = $components->{$k}->getHostConstraints();
        if ($constraints){
            return $constraints;
        }
    }
    return;
}

=head2 removeNode

=cut

sub removeNode {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => ['host_id']);

    my $adm = Administrator->new();
    # removeNode method concerns an existing entity so we use his entity_id
    my $granted = $adm->{_rightchecker}->checkPerm(entity_id => $self->{_entity_id}, method => 'removeNode');
    if(not $granted) {
        throw Kanopya::Exception::Permission::Denied(error => "Permission denied to remove a node from this cluster");
    }

    Workflow->run(
        name => 'StopNode',
        params   => {
            context => {
                cluster => $self,
                host    => Entity::Host->get(id => $args{host_id})
            }
        }
     );
}

=head2 start

=cut

sub start {
    my $self = shift;

    my $adm = Administrator->new();
    # start method concerns an existing entity so we use his entity_id
    my $granted = $adm->{_rightchecker}->checkPerm(entity_id => $self->{_entity_id}, method => 'start');
    if (not $granted) {
        throw Kanopya::Exception::Permission::Denied(error => "Permission denied to start this cluster");
    }

    $self->setState(state => 'starting');

    # Enqueue operation AddNode.
    return $self->addNode();
}

=head2 stop

=cut

sub stop {
    my $self = shift;

    my $adm = Administrator->new();
    # stop method concerns an existing entity so we use his entity_id
    my $granted = $adm->{_rightchecker}->checkPerm(entity_id => $self->{_entity_id}, method => 'stop');
    if (not $granted) {
        throw Kanopya::Exception::Permission::Denied(error => "Permission denied to stop this cluster");
    }

    $log->debug("New Operation StopCluster with cluster_id : " . $self->getAttr(name => 'cluster_id'));
    return Operation->enqueue(
        priority => 200,
        type     => 'StopCluster',
        params   => {
            context => {
                cluster => $self,
            }
        },
    );
}

=head2 getState

=cut

sub getState {
    my $self = shift;
    my $state = $self->{_dbix}->get_column('cluster_state');
    return wantarray ? split(/:/, $state) : $state;
}

=head2 setState

=cut

sub setState {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => ['state']);
    my $new_state = $args{state};
    my $current_state = $self->getState();
    $self->{_dbix}->update({'cluster_prev_state' => $current_state,
                            'cluster_state' => $new_state.":".time})->discard_changes();;
}


sub getNewNodeNumber {
	my $self = shift;
	my $nodes = $self->getHosts();

	# if no nodes already registered, number is 1
	if(! keys %$nodes) { return 1; }

	my @current_nodes_number = ();
	while( my ($host_id, $host) = each(%$nodes) ) {
		push @current_nodes_number, $host->getNodeNumber();
	}
	@current_nodes_number = sort(@current_nodes_number);
	$log->debug("Nodes number sorted: ".Dumper(@current_nodes_number));

	my $counter = 1;
	for my $number (@current_nodes_number) {
		if("$counter" eq "$number") {
			$counter += 1;
			next;
		} else {
			return $counter;
		}
	}
	return $counter;
}

=head2 getNodeState


=cut

sub getNodeState {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => ['hostname']);

    my $host       = Entity::Host->find(hash => {host_hostname => $args{hostname}});
    my $host_id    = $host->getId();
    my $node       = Externalnode::Node->find(hash => {host_id => $host_id});
    my $node_state = $node->getAttr(name => 'node_state');

    return $node_state;
}

=head2 getNodesMetrics

    Desc: call collector manager to retrieve nodes metrics values.
    return \%data;

=cut

sub getNodesMetrics {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'time_span', 'indicators' ]);

    my $collector_manager = $self->getManager(manager_type => "collector_manager");

    my $nodes = $self->getHosts();
    my @nodelist;

    while (my ($host_id, $host_object) = each(%$nodes)) {
        push @nodelist, $host_object->getAttr(name => 'host_hostname');
    }

    return $collector_manager->retrieveData(
               nodelist   => \@nodelist,
               time_span  => $args{'time_span'},
               indicators => $args{'indicators'}
           );
}

sub generateOverLoadNodemetricRules {
    my ($self, %args) = @_;
    my $service_provider_id = $self->getId();

    my $creation_conf = {
        'memory' => {
             formula         => 'id2 / id1',
             comparator      => '>',
             threshold       => 70,
             rule_label      => '%MEM used too high',
             rule_description => 'Percentage memory used is too high',
        },
        'cpu' => {
            #User+Idle+Wait+Nice+Syst+Kernel+Interrupt
             formula         => '(id5 + id6 + id7 + id8 + id9 + id10) / (id5 + id6 + id7 + id8 + id9 + id10 + id11)',
             comparator      => '>',
             threshold       => 70,
             rule_label      => '%CPU used too high',
             rule_description => 'Percentage processor used is too high',
        },
    };

    while (  my ($key, $value) = each(%$creation_conf) ) {
        my $combination_param = {
            nodemetric_combination_formula             => $value->{formula},
            nodemetric_combination_service_provider_id => $service_provider_id,
        };

        my $comb  = NodemetricCombination->new(%$combination_param);

        my $condition_param = {
            nodemetric_condition_combination_id      => $comb->getAttr(name=>'nodemetric_combination_id'),
            nodemetric_condition_comparator          => $value->{comparator},
            nodemetric_condition_threshold           => $value->{threshold},
            nodemetric_condition_service_provider_id => $service_provider_id,
        };

        my $condition = NodemetricCondition->new(%$condition_param);
        my $conditionid = $condition->getAttr(name => 'nodemetric_condition_id');
        my $prule = {
            nodemetric_rule_formula             => 'id'.$conditionid,
            nodemetric_rule_label               => $value->{rule_label},
            nodemetric_rule_description         => $value->{rule_description},
            nodemetric_rule_state               => 'enabled',
            nodemetric_rule_service_provider_id => $service_provider_id,
        };
        my $rule = NodemetricRule->new(%$prule);
    }
}

=head2 generateDefaultMonitoringConfiguration

    Desc: create default nodemetric combination and clustermetric for the service provider

=cut


sub generateDefaultMonitoringConfiguration {
    my ($self, %args) = @_;

    my $collector = $self->getManager(manager_type => "collector_manager");
    my $indicators = $collector->getIndicators();
    my $service_provider_id = $self->getId;

    # We create a nodemetric combination for each indicator
    foreach my $indicator (@$indicators) {
        my $combination_param = {
            nodemetric_combination_formula => 'id' . $indicator->getId,
            nodemetric_combination_service_provider_id => $service_provider_id,
        };
        NodemetricCombination->new(%$combination_param);
    }

    #definition of the functions
    my @funcs = qw(mean max min std dataOut);

    #we create the clustermetric and associate combination
    foreach my $indicator (@$indicators) {
        foreach my $func (@funcs) {
            my $cm_params = {
                clustermetric_service_provider_id      => $service_provider_id,
                clustermetric_indicator_id             => $indicator->getId,
                clustermetric_statistics_function_name => $func,
                clustermetric_window_time              => '1200',
            };
            my $cm = Clustermetric->new(%$cm_params);

            my $acf_params = {
                aggregate_combination_service_provider_id   => $service_provider_id,
                aggregate_combination_formula               => 'id' . $cm->getId
            };
            my $clustermetric_combination = AggregateCombination->new(%$acf_params);
        }
    }
}

1;

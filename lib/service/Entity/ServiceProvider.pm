#    Copyright © 2011 Hedera Technology SAS
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

TODO

=end classdoc
=cut

package Entity::ServiceProvider;
use base Entity;

use General;
use Entity::Node;
use ClassType::ComponentType;
use ClassType::ServiceProviderType;
use ComponentCategory::ManagerCategory;
use Entity::Component;
use Entity::Interface;
use Entity::Metric::Nodemetric;
use ServiceProviderManager;
use Entity::Rule::NodemetricRule;
use VerifiedNoderule;

use List::Util qw[min max];
use TryCatch;
use Log::Log4perl "get_logger";

my $log = get_logger("");
my $errmsg;

use constant ATTR_DEF => {
    service_provider_type_id => {
        pattern      => '^\d+$',
        is_mandatory => 0,
        is_extended  => 0
    },
    components => {
        label        => 'Components',
        type         => 'relation',
        relation     => 'single_multi',
        link_to      => 'component',
        is_mandatory => 0,
        is_editable  => 0,
    },
    interfaces => {
        label        => 'Interfaces',
        type         => 'relation',
        relation     => 'single_multi',
        link_to      => 'interface',
        is_mandatory => 0,
        is_editable  => 1,
    },
    billinglimits => {
        label        => 'Limits',
        type         => 'relation',
        relation     => 'single_multi',
        link_to      => 'billinglimit',
        is_mandatory => 0,
        is_editable  => 1,
    },
};

sub getAttrDef { return ATTR_DEF; }

sub methods {
    return {
        registerNode => {
            description => 'add a node to this service provider.',
        },
        addComponent => {
            description => 'add a component to this service provider.',
        },
        removeComponent => {
            description => 'remove a component from this service provider.',
        },
        addManager => {
            description => 'add a manager to this service provider.',
        },
        getNodeMonitoringData => {
            description => 'get monitoring data of a node.',
        },
        enableNode => {
            description => 'enable node.',
        },
        disableNode => {
            description => 'disable node',
        },
        addManagerParameters => {
            description => 'add paramaters to a manager.',
        },
        getManagerParameters => {
            description => 'get managers parameters.',
        },
    };
}


=pod
=begin classdoc

@constructor

Override the constructor to set the proper service provider type.

@return the service provider instance

=end classdoc
=cut

sub new {
    my $class = shift;
    my %args = @_;

    if (! defined $args{service_provider_type_id} && $class ne 'Entity::ServiceProvider') {
        (my $type = $class) =~ s/^.*:://g;
        $args{service_provider_type_id}
            = ClassType::ServiceProviderType->find(hash => { service_provider_name => $type })->id;
    }

    return $class->SUPER::new(%args);
}


=pod
=begin classdoc

Register a new node in the servie provider.
Also reconfigure the components about the node registration.

@return the registered node

=end classdoc
=cut

sub registerNode {
    my ($self, %args) = @_;

    General::checkParams(args     => \%args,
                         required => [ 'hostname' ],
                         optional => { 'host'             => undef,
                                       'systemimage'      => undef,
                                       'number'           => undef,
                                       'state'            => 'out',
                                       'monitoring_state' => 'enabled',
                                       'components'       => [ $self->components ] });

    # Compute the node number from existing nodes if not defined
    if (! defined $args{number}) {
        my @nodes = $self->nodes;
        $args{number} = max(map { $_->node_number } @nodes) + 1;
        $log->debug("Node number <$args{number}> computed for node $args{hostname}");
    }

    my $node = Entity::Node->new(
                   service_provider_id => $self->id,
                   node_hostname       => $args{hostname},
                   host_id             => $args{host} ? $args{host}->id : undef,
                   node_state          => $args{state} . ':' . time(),
                   monitoring_state    => $args{monitoring_state},
                   node_number         => $args{number},
                   systemimage_id      => $args{systemimage} ? $args{systemimage}->id : undef,
                   owner_id            => $self->owner_id,
               );

    # Enable the node if monitoring enabled
    if ($node->monitoring_state eq 'enabled') {
        $self->enableNode(node_id => $node->id);
    }

    # Force to install required component if not defined
    for my $required (@{ $self->getRequiredComponents() }) {
        if (scalar(grep { $_->id == $required->id } @{ $args{components} }) <= 0) {
            push @{ $args{components} }, $required;
        }
    }

    # Link the service provider components to the new node
    for my $component (@{ $args{components} }) {
        $log->info("Register component \"" . $component->label . "\" on node " . $node->label);
        $component->registerNode(node => $node, master_node => ($node->node_number == 1) ? 1 : 0);
    }

    # If the node linked to a host, configure the network connectivity
    # TODO: Manage network connectivity on node instead of host.
    if (defined $node->host) {
        # Set the ifaces netconf according to the cluster interfaces
        # We consider that the available ifaces match the cluster
        # interfaces since getFreeHost selection done.
        foreach my $interface ($self->interfaces) {
            # Firstly find the corresponding iface from name
            my $iface = $node->host->find(related => 'ifaces',
                                          hash    => { iface_name => $interface->interface_name });

            # Set the related netconfs
            my @netconfs = $interface->netconfs;

            $log->info("Configure iface " . $iface->iface_name . " with netconfs " . join(', ', @netconfs));
            $iface->update(netconf_ifaces => \@netconfs, override_relations => 1);
        }
    }

    # Create the nodemetric for the new node from the existing clustermetrics indicators
    # Create Nodemetrics for all existing nodes fo the service provider
    for my $clustermetric ($self->clustermetrics) {
        Entity::Metric::Nodemetric->findOrCreate(
            nodemetric_node_id      => $node->id,
            nodemetric_indicator_id => $clustermetric->clustermetric_indicator_id
        );
    }

    return $node;
}


=pod
=begin classdoc

Unregister the node from the servie provider, and free assigned ips.

@return the registered node

=end classdoc
=cut

sub unregisterNode {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'node' ]);

    # Remove collector indicators if managed by a collector
    try {
        my $collector = $self->getManager(manager_type => 'CollectorManager');

        my @collector_indicators = $collector->collector_indicators;
        for my $collector_indicator (@collector_indicators) {
            my $indicator = $collector_indicator->indicator;
            my $rrd_name = $indicator->id . '_' . $args{node}->node_hostname;
            $log->info('Deleting RRD file ' . $rrd_name);
            TimeData::RRDTimeData->deleteTimeDataStore(name => $rrd_name);
        }
    }
    catch (Kanopya::Exception::Internal::NotFound $err) {
        $log->warn("No collector manager defined, skipping deletion of indicators");
    }
    catch ($err) {
        $err->rethrow();
    }

    if (defined $args{node}->host) {
        # Free assigned ips
        my @ifaces = $args{node}->host->getIfaces;
        for my $iface (@ifaces) {
            my @ips = $iface->ips;
            for my $ip (@ips) {
                $ip->delete();
            }
            # Remove the network connectivity
            $iface->update(netconf_ifaces => [], override_relations => 1);
        }
    }
    $args{node}->delete();
}


=pod
=begin classdoc

Get the monitoring data for a node.

@return node monitoring data

=end classdoc
=cut

sub getNodeMonitoringData {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'node_id', 'indicator_ids' ]);

    my $node = Entity::Node->get(id => $args{node_id});
    my $manager = $self>getManager(manager_type => 'CollectorManager');

    # Construst indicators params as expected by CollectorManager
    my %indicators;
    for my $indic_id (@{$args{indicator_ids}}) {
        $indicators{$indic_id} = Entity::Indicator->get(id => $indic_id);
    }
    delete $args{indicator_ids};

    my $data = $manager->retrieveData(
        nodelist    => [ $node->node_hostname ],
        indicators  => \%indicators,
        %args
    );

    return $data->{$node->node_hostname} || {};
}


=pod
=begin classdoc

Enable a node.

=end classdoc
=cut

sub enableNode {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'node_id' ]);

    my $node = Entity::Node->get(id => $args{node_id});

    my @nm_rules = Entity::Rule::NodemetricRule->search(hash => { service_provider_id => $self->id });
    foreach my $nm_rule (@nm_rules) {
        try {
            VerifiedNoderule->new(
                verified_noderule_node_id            => $node->id,
                verified_noderule_state              => 'undef',
                verified_noderule_nodemetric_rule_id => $nm_rule->id,
            );
        }
        catch(Kanopya::Exception::DB::DuplicateEntry $err) {
            my $msg = 'Nodemetric rules <' . $nm_rule->id .'> is already undef for node <' . $node->id . '>';
            $log->debug($msg);
        }
    }

    return $node->enable();
}


=pod
=begin classdoc

Disable a node.

=end classdoc
=cut

sub disableNode {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'node_id' ]);

    my $node = Entity::Node->get(id => $args{node_id});

    my @verified_noderules = $node->verified_noderules;
    while(@verified_noderules) {
        (pop @verified_noderules)->delete();
    }

    return $node->disable();
}

sub getNodesMetrics {}

sub getState {
    throw Kanopya::Exception::NotImplemented();
}

sub getManager {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ 'manager_type' ]);

    my $cluster_manager = $self->findRelated(filters => [ 'service_provider_managers' ],
                                             custom  => { category => $args{manager_type} });

    return $cluster_manager->manager;
}

sub getNodes {
    my ($self, %args) = @_;

    my @nodes = Entity::Node->search(hash => {
                    service_provider_id => $self->id(),
                });

    my @node_hashs;
    for my $node (@nodes){
        my @verified_rules = VerifiedNoderule->search(hash => {
                                verified_noderule_state => 'verified'
                             });
        my @undef_rules    = VerifiedNoderule->search(hash => {
                                verified_noderule_state => 'undef'
                             });

        push @node_hashs, {
            state              => $node->getAttr(name => 'monitoring_state'),
            id                 => $node->getAttr(name => 'node_id'),
            hostname           => $node->getAttr(name => 'node_hostname'),
            num_verified_rules => scalar @verified_rules,
            num_undef_rules    => scalar @undef_rules,
        };
    }
    return \@node_hashs;
}


=pod
=begin classdoc

Add a manager to a service provider

@param manager_id the id of the component to use as manager
@param manager_type the type of the manager to add

@return the ServiceProviderManager instance

=end classdoc
=cut

sub addManager {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'manager_id', 'manager_type' ]);

    my $category = ComponentCategory::ManagerCategory->find(hash => {
                       category_name => $args{manager_type}
                   });

    my $manager = ServiceProviderManager->new(
                      service_provider_id => $self->id,
                      manager_category_id => $category->id,
                      manager_id          => $args{manager_id}
                  );

    if ($args{manager_params}) {
        $manager->addParams(params => $args{manager_params});
    }
    return $manager;
}

sub addManagerParameter {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ 'manager_type', 'name', 'value' ]);

    my $cluster_manager = $self->findRelated(filters => [ 'service_provider_managers' ],
                                             custom  => { category => $args{manager_type} });

    $cluster_manager->addParams(params => { $args{name} => $args{value} });
}


=pod
=begin classdoc

Set parameters of a manager defined by its type.

@param manager_type the type of the manager on which we set the params
@param params the parameters hash to set

=end classdoc
=cut

sub addManagerParameters {
    my $self = shift;
    my %args = @_;

    General::checkParams(args     => \%args,
                         required => [ "manager_type", "params" ],
                         optional => { "override" => 0 });

    my $manager = $self->findRelated(filters => [ 'service_provider_managers' ],
                                     custom  => { category => $args{manager_type} });

    $manager->addParams(params => $args{params}, override => $args{override});
}


sub getManagerParameters {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ 'manager_type' ]);

    my $cluster_manager = $self->findRelated(filters => [ 'service_provider_managers' ],
                                             custom  => { category => $args{manager_type} });

    return $cluster_manager->getParams();
}

=pod
=begin classdoc

Add a network interface on this service provider

=end classdoc
=cut

sub addNetworkInterface {
    my ($self, %args) = @_;

    General::checkParams(args     => \%args,
                         required => [ 'netconfs', 'interface_name' ],
                         optional => { 'bonds_number' => 0 });

    my $params = {
        service_provider_id => $self->id,
        bonds_number        => $args{bonds_number},
        netconf_interfaces  => $args{netconfs},
        interface_name      => $args{interface_name},
    };
    return Entity::Interface->new(%$params);
}


sub removeNetworkInterface {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => ['interface_id']);

    Entity::Interface->get(id => $args{interface_id})->delete();
}

sub getLimit {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ "type" ]);

    #If there is a billing limit, use it, otherwise return undef
    my @limits;
    eval {
        # Firtly get billing limit
        #
        # TODO: Use only one request
        @limits = Entity::Billinglimit->search(hash => {
                      service_provider_id => $self->id,
                      soft                => 0,
                      type                => $args{type},
                  });
    };
    if (scalar (@limits) != 0) {
        my $billing_limit_value;
        my $now = time() * 1000;
        for my $limit (@limits) {
            if (($limit->start < $now) && ($limit->ending > $now)){
                $billing_limit_value = $billing_limit_value ?
                                           min($billing_limit_value, $limit->value) : $limit->value;
            }
        }

        # Get Limit from host_manager
        my $host_params = $self->getManagerParameters(manager_type => 'HostManager');

        my $host_limit_value;

        if ($args{type} eq 'ram') {
            if(defined $host_params->{max_ram}) {
                $host_limit_value = $host_params->{max_ram};
            }
            else {
                $log->info('host limit ram undef');
            }
        }
        elsif ($args{type} eq 'cpu') {
            $host_limit_value = $host_params->{max_core};
        }

        my $value;
        if (defined $billing_limit_value){
            if ( defined $host_limit_value ) {
                $value = min( $billing_limit_value, $host_limit_value  );
            }
            else {
                $value = $billing_limit_value;
            }
        }
        else {
            $value = $host_limit_value;
        }
        return $value;
    }
    else {
        return;
    }
}


=pod
=begin classdoc

Create a new componant and link it to the cluster

@param component_type_id ID of the component to be added
@param default_configuration the defaut configuration to be setted to component

@return component

=end classdoc
=cut

sub addComponent {
    my ($self, %args) = @_;

    General::checkParams(args     => \%args,
                         required => [ 'component_type_id' ],
                         optional => { 'component_configuration'       => undef,
                                       'component_extra_configuration' => undef,
                                       'component_template_id'         => undef });

    # Check if the type of the given component is installable on this type
    # of service provider.
    my $component_type = ClassType::ComponentType->get(id => $args{component_type_id});

    # For instance, allow the addiction of component on generic service providers
    if (defined $self->service_provider_type) {
        my @service_provider_types = $component_type->service_provider_types;
        if (scalar (grep { $_->id == $self->service_provider_type_id } @service_provider_types) <= 0) {
            throw Kanopya::Exception::Internal(
                      error => "Component type <" . $component_type->component_name .
                               "> can not be installed on a service provider of type <" .
                               $self->service_provider_type->service_provider_name . ">."
                  );
        }
    }

    # If the component is already installed, just return it
    try {
        return $self->find(related => 'components',
                           hash    => { component_type_id   => $args{component_type_id} });
    }
    catch ($err) {
        # Component do not exists yet, add it.
    }

    my $comp_class = $component_type->class_type;
    my $location = General::getLocFromClass(entityclass => $comp_class);
    require $location;

    $log->info("Add component of type ". $component_type->component_name . " on service " . $self->label);

    # Set component's configuration or use default
    my $component;
    if (defined $args{component_configuration}) {
        $component = $comp_class->new(service_provider_id   => $self->id,
                                      component_template_id => $args{component_template_id},
                                      param_presets         => $args{component_extra_configuration},
                                      %{ $args{component_configuration} });
    }
    else {
        $component = $comp_class->new(service_provider_id   => $self->id,
                                      component_template_id => $args{component_template_id},
                                      param_presets         => $args{component_extra_configuration});
    }

    # For instance install the component on all node of the service provider,
    # use the first started node as master node for the component.
    for my $node ($self->nodes) {
        $component->registerNode(node => $node, master_node => ($node->node_number == 1));
    }

    # Insert default configuration for tables linked to component (when exists)
    $component->insertDefaultExtendedConfiguration();

    return $component;
}


sub getComponents {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ 'category' ],
                                         optional => { 'order_by' => undef });

    my $findargs = {
        hash => { 'service_provider_id' => $self->id }
    };

    if (defined ($args{category}) and $args{category} ne "all") {
        $findargs->{custom}->{category} = $args{category};
    };

    my @components = Entity::Component->search(%$findargs);

    if (defined ($args{order_by})) {
        my $criteria = $args{order_by};
        @components = sort { $a->$criteria <=> $b->$criteria } @components;
    }

    return wantarray ? @components : \@components;
}

sub getComponent {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, optional => { 'node'     => undef, 'name'     => undef,
                                                       'category' => undef, 'version'  => undef });

    my $findargs = { hash => {} };

    # If filter on node defined, do not filter on service_provider as
    # it is implicit from node filter
    if (defined $args{node}) {
        $findargs->{hash}->{'component_nodes.node.node_id'} = $args{node}->id;
    }
    else {
        $findargs->{hash}->{'service_provider_id'} = $self->id;
    }

    if (defined ($args{name})) {
        $findargs->{hash}->{'component_type.component_name'} = $args{name};
    }

    if (defined ($args{category})) {
        $findargs->{custom}->{category} = $args{category};
    }

    if (defined ($args{version})) {
        $findargs->{hash}->{'component_type.component_version'} = $args{version};
    }

    return Entity::Component->find(%$findargs);
}

sub getRequiredComponents {
    my ($self, %args) = @_;

    return [];
}

sub nodesByWeight {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, optional => { 'master_node' => 1 });

    my @nodes = $self->nodes;
    if (not $args{master_node}) {
        # If option set, keep non master nodes only
        @nodes = grep { scalar($_->getMasterComponents) == 0 } @nodes;
    }

    return sort {
        # Firstly sort by number of master components
        scalar($b->getMasterComponents) <=> scalar($a->getMasterComponents)
            ||
        # Then by number of components
        scalar($b->component_nodes) <=> scalar($a->component_nodes)
            ||
        # Finally by node number
        $a->node_number <=> $b->node_number
    } @nodes;
}

=pod

=begin classdoc

Check if billing limits will be reached for given metrics

@param host a new host to be added to the service
@return boolean

=end classdoc

=cut

sub checkBillingLimits {
    my ($self,%args) = @_;

    General::checkParams(args => \%args, required => [ 'metrics' ]);

    my $cluster_metrics = $self->getServiceMetricsValues();

    while ((my $metric, $value) = each %{ $args{metrics} }) {
        $log->debug("checking Billing limit for $metric");

        my $service_metric_limit = $self->getLimit(type => $metric);

        my $new_service_metric = $cluster_metrics->{$metric} + $value;

        if (defined $service_metric_limit && $new_service_metric > $service_metric_limit) {
            my $error = "Service $metric billing limit (<$service_metric_limit>) ";
            $error   .= "would be oversteped (<$new_service_metric>): action is forbidden";
            throw Kanopya::Exception::Internal(error => $error);
        }
    }
    return 1;
}

=pod

=begin classdoc

Retrieve ram and cores values for the whole cluster

@return ram and cpu

=end classdoc

=cut

sub getServiceMetricsValues {
    my ($self,%args) = @_;

    my @nodes = $self->nodes;
    my $service_ram = 0;
    my $service_cpu = 0;

    foreach my $node (@nodes) {
        $service_ram += $node->host->host_ram;
        $service_cpu += $node->host->host_core;
    }

    return {
        ram => $service_ram,
        cpu => $service_cpu,
    };
}



=pod

=begin classdoc

Overrides method in order to remove properly the components

=end classdoc

=cut

sub remove {
    my ($self, %args) = @_;


    @metrics = ($self->clustermetrics,
                $self->combinations);
    while (@metrics) {
        (pop @metrics)->remove();
    }

    my @components = $self->components;
    while (@components) {
        (pop @components)->remove();
    }

    return $self->SUPER::remove(%args);
}
1;
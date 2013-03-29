=pod

=begin classdoc

Subroutines to upgrade KIO 

@since 2013-March-26

=end classdoc

=cut


package Kanopya::Tools::KioImport;

use strict;
use warnings;

use Data::Dumper;
use General;
use JSON;
use Kanopya::Exceptions;
use BaseDB;
use Entity::Component;
use Entity::Component::ActiveDirectory;
use Entity::Component::Scom;
use Entity::Component::Sco;
use Node;
use Entity::Rule::AggregateRule;
use ServiceProviderManager;
use Entity::Combination::AggregateCombination;
use Entity::AggregateCondition;
use Entity::ServiceProvider::Cluster;
use Entity::Clustermetric;
use Entity::CollectorIndicator;
use Entity::Indicator;
use Entity::Combination::ConstantCombination;
use Dashboard;
use Entity::Host;
use Entity::Indicator;
use Entity::Combination::NodemetricCombination;
use Entity::NodemetricCondition;
use Entity::Rule::NodemetricRule;
use ParamPreset;
use Entity::User;
use UserProfile;
use VerifiedNoderule;
use Entity::WorkflowDef;
use Entity::ServiceProvider::Externalcluster;
use ClassType::ComponentType;

BaseDB->authenticate( login =>'admin', password => 'K4n0pY4' );

my $export_dir = '/vagrant/';
my $export_bdd_file = $export_dir . 'bdd.json';

open (my $FILE, '<', $export_bdd_file) or die 'could not open \'$export_bdd_file\' : $!\n';
my $import;
while (my $line  = <$FILE>) {
    $import .= $line;
}

my $json_imported_items = JSON->new->utf8->decode($import);

my $services = $json_imported_items->{services};

# We need to map old ids to new ones for data updates
# reminder:
# AggregateCombination formula  => clustermetric ids
# NodemetricCombination formula => collector indicator ids
# AggregateRule                 => AggregateCondition ids
# NodemetricRule                => NodemetricCondition ids

my $collector_indicator_map;
my $clustermetric_map;
my $service_provider_map;
my $formula_map;
my @service_providers = grep {not defined $_->{connectors} } @$services;
my @technical_services = grep {defined $_->{connectors} } @$services;

# register service providers with component(s) (technical services)
for my $technical_service (@technical_services) {
    
    my $new_externalcluster = Entity::ServiceProvider::Externalcluster->new(
        externalcluster_name       => $technical_service->{externalcluster_name},
        externalcluster_desc       => $technical_service->{externalcluster_desc},
        externalcluster_state      => $technical_service->{externalcluster_state},
        externalcluster_prev_state => $technical_service->{externalcluster_prev_state},
    );

    $service_provider_map->{$technical_service->{service_provider_id}} = 
        $new_externalcluster;

    # register node(s)
    if (defined @{ $technical_service->{externalnodes} }) {
        for my $old_externalnode (@{ $technical_service->{externalnodes} }) {
            my $new_node = Node->new(
                node_hostname       => $old_externalnode->{externalnode_hostname},
                node_number         => 0,
                monitoring_state    => $old_externalnode->{externalnode_state},
                service_provider_id => $new_externalcluster->id
            );
        }
    }

    # register component(s)
    for my $connector (@{ $technical_service->{connectors} }) {
        my $component_type_id = ClassType::ComponentType->find(hash => {
                                    component_name => $connector->{connector_type}
                                })->id;

        my $component_class_type = 'Entity::Component::' . $connector->{connector_type};
        my $component = $component_class_type->new(
            component_type_id     => $component_type_id,
            service_provider_id   => $new_externalcluster->id,
        );

        if (defined $connector->{collector_indicators}) {

            foreach my $old_collector_indicator (@{ $connector->{collector_indicators} }) {
                my $old_indicator_name = $old_collector_indicator->{indicator_name};
                my $indicator_id = Entity::Indicator->find( hash => {
                                     indicator_name => $old_indicator_name, 
                                   })->id;

                $collector_indicator_map->{$old_collector_indicator->{collector_indicator_id}} =
                    Entity::CollectorIndicator->new(
                        collector_manager_id => $component->id,
                        indicator_id         => $indicator_id,
                    )->id;
            }

            $formula_map->{collector_indicators} = $collector_indicator_map;
        }
    }
}

# register service providers with managers 
for my $service_provider (@service_providers) {
    my $new_externalcluster = Entity::ServiceProvider::Externalcluster->new(
        externalcluster_name       => $service_provider->{externalcluster_name},
        externalcluster_desc       => $service_provider->{externalcluster_desc},
        externalcluster_state      => $service_provider->{externalcluster_state},
        externalcluster_prev_state => $service_provider->{externalcluster_prev_state}
    );

    $service_provider_map->{$service_provider->{service_provider_id}} = 
        $new_externalcluster;

    my $manager_categories = {
        directory_service_manager => 'DirectoryServiceManager',
        collector_manager         => 'CollectorManager',
        workflow_manager          => 'WorkflowManager',
    };

    foreach my $old_manager (@{ $service_provider->{service_provider_managers} }) {
        my $manager_service_provider =
            $service_provider_map->{$old_manager->{origin_service_id}};

        my $manager_id = $manager_service_provider->getComponent(
                             category => $manager_categories->{$old_manager->{manager_type}}
                         )->id;

        $new_externalcluster->addManager(
            manager_id   => $manager_id,
            manager_type => $manager_categories->{$old_manager->{manager_type}}
        );
    }

    for my $old_clustermetric (@{ $service_provider->{clustermetrics} }) {
        my $clustermetric_indicator_id =
            $collector_indicator_map->{$old_clustermetric->{clustermetric_indicator_id}};

        $clustermetric_map->{$old_clustermetric->{clustermetric_id}} =
            Entity::Clustermetric->new(
                clustermetric_label                    => $old_clustermetric->{clustermetric_label},
                clustermetric_indicator_id             => $clustermetric_indicator_id,
                clustermetric_statistics_function_name => $old_clustermetric->{clustermetric_statistics_function_name},
                clustermetric_formula_string           => $old_clustermetric->{clustermetric_formula_string},
                clustermetric_unit                     => $old_clustermetric->{clustermetric_unit},
                clustermetric_window_time              => $old_clustermetric->{clustermetric_window_time},
                clustermetric_service_provider_id      => $new_externalcluster->id
            )->id;
    }
    $formula_map->{clustermetrics} = $clustermetric_map;

    #register combinations
    foreach my $old_combination (@{ $service_provider->{combinations} }) {
        if (defined $old_combination->{nodemetric_combination_id}) {
            #we update the old formula with the new ids
            my $nc_formula =  $old_combination->{nodemetric_combination_formula};
            $nc_formula =~ s/id(\d+)/id$formula_map->{collector_indicators}->{$1}/g;

            Entity::Combination::NodemetricCombination->new(
                nodemetric_combination_label          => $old_combination->{nodemetric_combination_label},
                nodemetric_combination_formula        => $nc_formula,
                nodemetric_combination_formula_string => $old_combination->{nodemetric_combination_formula_string},
                combination_unit                      => $old_combination->{combination_unit},
                service_provider_id                   => $new_externalcluster->id,
            );
        }

        if (defined $old_combination->{aggregate_combination_id}) {
            #we update the old formula with the new ids
            my $ac_formula = $old_combination->{aggregate_combination_formula};
            $ac_formula =~ s/id(\d+)/id$formula_map->{clustermetrics}->{$1}/g;

            Entity::Combination::AggregateCombination->new(
                aggregate_combination_label           => $old_combination->{aggregate_combination_label},
                aggregate_combination_formula         => $ac_formula,
                aggregate_combination_formula_string  => $old_combination->{aggregate_combination_formula_string},
                combination_unit                      => $old_combination->{combination_unit},
               service_provider_id                    => $new_externalcluster->id,
            );
        }
    }
}

1;

#!/usr/bin/perl

use strict;
use warnings;

use Test::More 'no_plan', 'no_diag';
use Test::Exception;
use Test::Pod;
use Data::Dumper;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init({ level=>'DEBUG', file=>'/tmp/benchmark_orchestrator_loop.log', layout=>'%F %L %p %m%n' });
my $log = get_logger("");

use Kanopya::Tools::Execution;
use Kanopya::Tools::Register;
use Kanopya::Tools::Retrieve;
use Kanopya::Tools::Create;
use Kanopya::Tools::Profiler;

lives_ok {
    use Administrator;
    use Aggregator;
    use Orchestrator;

    use Entity::ServiceProvider::Inside::Cluster;
    use Entity::Connector::MockMonitor;
    
    use Entity::Clustermetric;
    use Entity::Combination::AggregateCombination;
    use Entity::AggregateCondition;
    use Entity::Rule::AggregateRule;

} 'All uses';

Administrator::authenticate(login =>'admin', password => 'K4n0pY4');
my $adm          = Administrator->new;
my $aggregator   = Aggregator->new();
my $orchestrator = Orchestrator->new();
my $profiler     = Kanopya::Tools::Profiler->new(schema => $adm->{db});

$adm->beginTransaction;

my $serviceload = 1;
my $nodeload = 1;
my $ruleload = 0;

my $kanopya = Entity::ServiceProvider::Inside::Cluster->find(hash => { cluster_name => 'Kanopya' });
my $mock_monitor = Entity::Connector::MockMonitor->new(
                       service_provider_id => $kanopya->id,
                   );

# Get indicators
my $indic1 = Entity::CollectorIndicator->find (hash => {});


sub registerCluster {
    my ($self, %args) = @_;

    my $cluster = Kanopya::Tools::Create->createCluster(cluster_conf => {
                      cluster_name         => "Cluster" . $serviceload, 
                      cluster_basehostname => "default" . $serviceload
                  });

    $cluster->addManager(
        manager_id      => $mock_monitor->id,
        manager_type    => 'collector_manager',
        no_default_conf => 1,
    );
 
    addNode(cluster => $cluster, number => $nodeload);

    $serviceload++;
}

sub addNode {
    my (%args) = @_;

    # Register a host for the new service
    my $host = Kanopya::Tools::Register->registerHost(board => {
                   ram  => 1073741824,
                   core => 4,
               });

    # Make the host node for the new service
    $host->setAttr(name => 'host_hostname', value => 'hostname' . $args{cluster}->cluster_name . 'node' . $args{number}, save => 1);
    $host->becomeNode(inside_id => $args{cluster}->id, master_node => ($args{number} == 1) ? 1 : 0, node_number => $args{number});
    $host->setState(state => 'up');
    $host->setNodeState(state => 'in');
}

sub addAggregateRule {
    my (%args) = @_;

    my $cm = Entity::Clustermetric->new(
                 clustermetric_service_provider_id      => $args{cluster}->id,
                 clustermetric_indicator_id             => ($indic1->id),
                 clustermetric_statistics_function_name => 'sum',
                 clustermetric_window_time              => '1200',
             );

    my $comb = Entity::Combination::AggregateCombination->new(
                   service_provider_id           =>  $args{cluster}->id,
                   aggregate_combination_formula => 'id'.($cm->id),
               );

    my $ac = Entity::AggregateCondition->new(
                 aggregate_condition_service_provider_id => $args{cluster}->id,
                 left_combination_id                     => $comb->id,
                 comparator                              => '>',
                 threshold                               => '0',
             );

    Entity::Rule::AggregateRule->new(
        aggregate_rule_service_provider_id => $args{cluster}->id,
        aggregate_rule_formula             => 'id'.$ac->id,
        aggregate_rule_state               => 'enabled'
    );
}

sub benchmarkAggregatorUpdate {
    my ($self, %args) = @_;

    $aggregator->update();

    print "Benchmarking the aggregator update for $serviceload services, $ruleload agg rules each, $nodeload nodes each:\n";
    $profiler->start(print_queries => 0);

    $orchestrator->manage_aggregates();

    $profiler->stop();
}

eval{
    # Firstly create simple one node services
    my $t;
    while ($serviceload <= 100) {
        benchmarkAggregatorUpdate();

        for my $iteration (1 .. 10) {
            registerCluster();
        }
    }

    while ($nodeload <= 100) {
        benchmarkAggregatorUpdate();

        # Add 10 nodes to each services
        for my $cluster (Entity::ServiceProvider::Inside::Cluster->search(hash => {})) {
            for my $index (1 .. 10) {
                addNode(cluster => $cluster, number => ($nodeload + $index));
            }
        }
        $nodeload += 10;
    }

    while ($ruleload <= 100) {
        benchmarkAggregatorUpdate();

        # Add 10 rules to each services
        for my $cluster (Entity::ServiceProvider::Inside::Cluster->search(hash => {})) {
            for my $index (1 .. 10) {
                addAggregateRule(cluster => $cluster);
            }
        }
        $ruleload += 10;
    }
    benchmarkAggregatorUpdate();

    $adm->rollbackTransaction;
};
if ($@) {
    my $error = $@;
    print $error."\n";

    $adm->rollbackTransaction;

    fail('Exception occurs');
}

1;

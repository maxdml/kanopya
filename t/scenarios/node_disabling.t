#!/usr/bin/perl -w

=head1 SCOPE

TODO

=head1 PRE-REQUISITE

TODO

=cut

use strict;
use warnings;
use Test::More 'no_plan';
use Test::Exception;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init({
    level=>'DEBUG',
    file=>'/vagrant/node_disabling.log',
    layout=>'%F %L %p %m%n'
});

use Administrator;
use Orchestrator;
use Aggregator;
use Entity::ServiceProvider::Outside::Externalcluster;
use Entity::Connector::MockMonitor;
use Entity::Combination::NodemetricCombination;
use Entity::NodemetricCondition;
use Entity::NodemetricRule;
use VerifiedNoderule;
use Entity::Clustermetric;
use Entity::Combination::AggregateCombination;
use Entity::CollectorIndicator;

use Kanopya::Tools::TestUtils 'expectedException';

my $testing = 1;

my $acomb1;
my $nrule1;
my @indicators;
my $service_provider;

main();

sub main {
    Administrator::authenticate( login =>'admin', password => 'K4n0pY4' );
    my $adm = Administrator->new;

    if($testing == 1) {
        $adm->beginTransaction;
    }

    node_disabling();
    test_rrd_remove();

    if ($testing == 1) {
        $adm->rollbackTransaction;
    }
}

sub node_disabling {
    my $aggregator = Aggregator->new();
    my $orchestrator = Orchestrator->new();

    # Create externalcluster with a mock monitor
    my $external_cluster_mockmonitor = Entity::ServiceProvider::Outside::Externalcluster->new(
        externalcluster_name => 'Test Monitor',
    );

    my $mock_monitor = Entity::Connector::MockMonitor->new(
        service_provider_id => $external_cluster_mockmonitor->id,
    );

    $service_provider = Entity::ServiceProvider::Outside::Externalcluster->new(
        externalcluster_name => 'Test Service Provider',
    );

    diag('Add mock monitor to service provider');
    $service_provider->addManager(
        manager_id   => $mock_monitor->id,
        manager_type => 'collector_manager',
    );

    # Create two nodes
    my $node1 = Externalnode->new(
        externalnode_hostname => 'test_node_1',
        service_provider_id   => $service_provider->id,
        externalnode_state    => 'up',
    );

    my $node2 = Externalnode->new(
        externalnode_hostname => 'test_node_2',
        service_provider_id   => $service_provider->id,
        externalnode_state    => 'up',
    );

    my $node3 = Externalnode->new(
        externalnode_hostname => 'test_node_3',
        service_provider_id   => $service_provider->id,
        externalnode_state    => 'up',
    );

    @indicators = Entity::CollectorIndicator->search (hash => {collector_manager_id => $mock_monitor->id});
    my $agg_rule_ids  = _service_rule_objects_creation(indicators => \@indicators);
    my $node_rule_ids = _node_rule_objects_creation(indicators => \@indicators);

    diag('Check if no values before launching aggregator');
    if ( not defined $acomb1->computeLastValue ) {
        diag('## checked');
    }
    else {
        die 'Presence of values before launching aggregator';
    }

    $aggregator->update();

    diag('Check if 3 nodes in aggregator');
    if ( $acomb1->computeLastValue == 3 ) {
        diag('## checked');
    }
    else {
        die 'Not 3 nodes in aggregator';
    }

    $node3->disable();
    sleep(5);
    $aggregator->update();
    # Reload object to get changes
    $node3 = Externalnode->get(id => $node3->id);
    diag('Check disabling node 3');
    if ( $node3->externalnode_state eq 'disabled' ) {
        diag('## disabled');
    }
    else {
        die 'Node 3 not disabled';
    }

    diag('Check if 2 nodes in aggregator');
    if ( $acomb1->computeLastValue == 2 ) {
        diag('## checked');
    }
    else {
        die 'Not 2 nodes in aggregator';
    }

    $node3->enable();
    $node3 = Externalnode->get(id => $node3->id);
    diag('Check enabling node 3');
    if ( $node3->externalnode_state ne 'disabled' ) {
        diag('## enabled');
    }
    else {
        die 'Node 3 not enabled';
    }

    $aggregator->update();
    diag('Check if 3 nodes in aggregator');
    if ( $acomb1->computeLastValue == 3 ) {
        diag('## checked');
    }
    else {
        die 'Not 3 nodes in aggregator';
    }

    $orchestrator->manage_aggregates();

    diag('Check nodes rule verification');
    check_rule_verification(
        nrule1_id => $nrule1->id,
        node1_id  => $node1->id,
        node2_id  => $node2->id,
        node3_id  => $node3->id
    );

    $node3->disable();

    expectedException {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node3->id,
            verified_noderule_nodemetric_rule_id => $nrule1->id,
            verified_noderule_state              => 'verified',
        });
    } 'Kanopya::Exception::Internal::NotFound',
    'Disabled node 3 and check rule not verified';

    $orchestrator->manage_aggregates();

    expectedException {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node3->id,
            verified_noderule_nodemetric_rule_id => $nrule1->id,
            verified_noderule_state              => 'verified',
        });
    } 'Kanopya::Exception::Internal::NotFound',
    'Run orchestrator, disabled node 3 and check rule not verified';
}

sub check_rule_verification {
    my %args = @_;

    lives_ok {
        diag('# Node 1 rule verification');
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $args{node1_id},
            verified_noderule_nodemetric_rule_id => $args{nrule1_id},
            verified_noderule_state              => 'verified',
        });
        diag('## verified');

        diag('# Node 2 rule verification');
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $args{node2_id},
            verified_noderule_nodemetric_rule_id => $args{nrule1_id},
            verified_noderule_state              => 'verified',
        });
        diag('## verified');

        diag('# Node 3 rule verification');
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $args{node3_id},
            verified_noderule_nodemetric_rule_id => $args{nrule1_id},
            verified_noderule_state              => 'verified',
        });
        diag('## verified');
    } 'Check node rules are all verified';
}

sub test_rrd_remove {
    lives_ok {
        my @cms = Entity::Clustermetric->search (hash => {
            clustermetric_service_provider_id => $service_provider->id
        });

        my @cm_ids = map {$_->id} @cms;
        while (@cms) { (pop @cms)->delete(); };

        diag('Check if all aggregrate combinations have been deleted');
        my @acs = Entity::Combination::AggregateCombination->search (hash => {
            service_provider_id => $service_provider->id
        });
        if ( scalar @acs == 0 ) {
            diag('## checked');
        }
        else {
            die 'All aggregate combinations have not been deleted';
        }

        diag('Check if all aggregrate rules have been deleted');
        my @ars = Entity::AggregateRule->search (hash => {
            aggregate_rule_service_provider_id => $service_provider->id
        });
        if ( scalar @ars == 0 ) {
            diag('## checked');
        }
        else {
            die 'All aggregate rules have not been deleted';
        }

        diag('Check if all rrd have been deleted');
        my $one_rrd_remove = 0;
        for my $cm_id (@cm_ids) {
            if (defined open(FILE,'/var/cache/kanopya/monitor/timeDB_'.$cm_id.'.rrd')) {
                $one_rrd_remove++;
            }
            close(FILE);
        }
        if ($one_rrd_remove == 0) {
            diag('## checked');
        }
        else {
            die "All rrd have not been removed : $one_rrd_remove rrd are still remaining";
        }
    } 'Test rrd remove';
}

sub _service_rule_objects_creation {
    my $service_provider = Entity::ServiceProvider::Outside::Externalcluster->find(
        hash => {externalcluster_name => 'Test Service Provider'}
    );

    my $cm1 = Entity::Clustermetric->new(
        clustermetric_service_provider_id => $service_provider->id,
        clustermetric_indicator_id => ((pop @indicators)->id),
        clustermetric_statistics_function_name => 'count',
        clustermetric_window_time => '1200',
    );

    $acomb1 = Entity::Combination::AggregateCombination->new(
        service_provider_id             =>  $service_provider->id,
        aggregate_combination_formula   => 'id'.($cm1->id),
    );
}

sub _node_rule_objects_creation {
    my $service_provider = Entity::ServiceProvider::Outside::Externalcluster->find(
        hash => {externalcluster_name => 'Test Service Provider'}
    );

    # Create nodemetric rule objects
    my $ncomb1 = Entity::Combination::NodemetricCombination->new(
        service_provider_id             => $service_provider->id,
        nodemetric_combination_formula  => 'id'.((pop @indicators)->id).' + id'.((pop @indicators)->id),
    );

    my $nc1 = Entity::NodemetricCondition->new(
        nodemetric_condition_service_provider_id => $service_provider->id,
        left_combination_id => $ncomb1->id,
        nodemetric_condition_comparator => '>',
        nodemetric_condition_threshold => '0',
    );

    $nrule1 = Entity::NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => 'id'.$nc1->id,
        nodemetric_rule_state => 'enabled'
    );
}
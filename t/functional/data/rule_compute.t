#!/usr/bin/perl

use strict;
use warnings;
use Test::More 'no_plan';
use Test::Exception;
use Test::Pod;
use Data::Dumper;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init({level=>'DEBUG', file=>'/tmp/rule_compute.log', layout=>'%F %L %p %m%n'});
my $log = get_logger("");

lives_ok {
    use Administrator;
    use Aggregator;
    use Orchestrator;
    use Entity::ServiceProvider::Outside::Externalcluster;
    use Entity::Connector::MockMonitor;
    use Clustermetric;
    use AggregateCondition;
    use AggregateCombination;
    use AggregateRule;
    use NodemetricCombination;
    use NodemetricCondition;
    use NodemetricRule;
    use VerifiedNoderule;
} 'All uses';

Administrator::authenticate( login =>'admin', password => 'K4n0pY4' );
my $adm = Administrator->new;
$adm->beginTransaction;

my ($indic1);
my ($ac_f, $ac_t);
my ($nc_f, $nc_t);
my ($node,$node2);
my $service_provider;
my $aggregator;
my $orchestrator;

eval{

    $aggregator   = Aggregator->new();
    $orchestrator = Orchestrator->new();

    $service_provider = Entity::ServiceProvider::Outside::Externalcluster->new(
            externalcluster_name => 'Test Service Provider',
    );

    my $external_cluster_mockmonitor = Entity::ServiceProvider::Outside::Externalcluster->new(
            externalcluster_name => 'Test Monitor',
    );

    my $mock_monitor = Entity::Connector::MockMonitor->new(
            service_provider_id => $external_cluster_mockmonitor->id,
    );

    lives_ok{
        $service_provider->addManager(
            manager_id      => $mock_monitor->id,
            manager_type    => 'collector_manager',
            no_default_conf => 1,
        );
    } 'Add mock monitor to service provider';

    # Create node
    $node = Externalnode->new(
        externalnode_hostname => 'node_1',
        service_provider_id   => $service_provider->id,
        externalnode_state    => 'up',
    );

    # Create node
    $node2 = Externalnode->new(
        externalnode_hostname => 'node_2',
        service_provider_id   => $service_provider->id,
        externalnode_state    => 'up',
    );

    # Get indicators
    $indic1 = ScomIndicator->find (
        hash => {
            service_provider_id => $service_provider->id,
            indicator_oid => 'Memory/PercentMemoryUsed'
        }
    );

    test_nodemetric_rules();
    test_aggregate_rules();

    $adm->rollbackTransaction;
};
if($@) {
    $adm->rollbackTransaction;
    my $error = $@;
    print $error."\n";
}

sub test_nodemetric_rules {

    # Create nodemetric rule objects
    my $ncomb = NodemetricCombination->new(
        nodemetric_combination_service_provider_id => $service_provider->id,
        nodemetric_combination_formula => 'id'.($indic1->id),
    );

    $nc_f = NodemetricCondition->new(
        nodemetric_condition_service_provider_id => $service_provider->id,
        nodemetric_condition_combination_id => $ncomb->id,
        nodemetric_condition_comparator => '<',
        nodemetric_condition_threshold => '0',
    );

    $nc_t = NodemetricCondition->new(
        nodemetric_condition_service_provider_id => $service_provider->id,
        nodemetric_condition_combination_id => $ncomb->id,
        nodemetric_condition_comparator => '>',
        nodemetric_condition_threshold => '0',
    );

    $service_provider->addManagerParameter(
        manager_type    => 'collector_manager',
        name            => 'mockmonit_config',
        value           =>  "{'default':{'const':50},'nodes':{'node_2':{'const':null}}}",
    );

    $aggregator->update();

    my $nr_f = NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => 'id'.$nc_f->id,
        nodemetric_rule_state => 'enabled'
    );

    my $nr_t = NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => 'id'.$nc_t->id,
        nodemetric_rule_state => 'enabled'
    );

    $orchestrator->manage_aggregates();

    dies_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node->id,
            verified_noderule_nodemetric_rule_id => $nr_f->id,
            verified_noderule_state              => 'verified',
        })
    } 'Check node rule false';

    lives_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node->id,
            verified_noderule_nodemetric_rule_id => $nr_t->id,
            verified_noderule_state              => 'verified',
        });
    } 'Check node rule true';

    lives_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node2->id,
            verified_noderule_nodemetric_rule_id => $nr_t->id,
            verified_noderule_state              => 'undef',
        });
    } 'Check node undef - rule 1';

    lives_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node2->id,
            verified_noderule_nodemetric_rule_id => $nr_t->id,
            verified_noderule_state              => 'undef',
        });
    } 'Check node undef- rule 2';

    test_not_n();
    test_or_n();
    test_and_n();
    test_big_formulas_n();
}

sub test_aggregate_rules {
    my %args = @_;

    # Clustermetric
    my $cm = Clustermetric->new(
        clustermetric_service_provider_id => $service_provider->id,
        clustermetric_indicator_id => ($indic1->id),
        clustermetric_statistics_function_name => 'sum',
        clustermetric_window_time => '1200',
    );

    # Combination
    my $comb = AggregateCombination->new(
        aggregate_combination_service_provider_id   =>  $service_provider->id,
        aggregate_combination_formula               => 'id'.($cm->id),
    );

    # Condition
    $ac_t = AggregateCondition->new(
        aggregate_condition_service_provider_id => $service_provider->id,
        aggregate_combination_id => $comb->id,
        comparator => '>',
        threshold => '0',
        state => 'enabled'
    );

    $ac_f = AggregateCondition->new(
        aggregate_condition_service_provider_id => $service_provider->id,
        aggregate_combination_id => $comb->id,
        comparator => '<',
        threshold => '0',
        state => 'enabled'
    );

    # No node responds
    $service_provider->addManagerParameter(
        manager_type    => 'collector_manager',
        name            => 'mockmonit_config',
        value           =>  "{'default':{'const':50},'nodes':{'node_2':{'const':null}}}",
    );

    $aggregator->update();

    is($ac_t->eval, 1, 'Check true condition');
    is($ac_f->eval, 0, 'Check false condition');


    test_not();
    test_or();
    test_and();
    test_big_formulas();
}

sub test_and_n {

    my $r1 = NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => 'id'.$nc_f->id.' && '.'id'.$nc_f->id,
        nodemetric_rule_state => 'enabled'
    );

    my $r2 = NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => 'id'.$nc_f->id.' && '.'id'.$nc_t->id,
        nodemetric_rule_state => 'enabled'
    );

    my $r3 = NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => 'id'.$nc_t->id.' && '.'id'.$nc_f->id,
        nodemetric_rule_state => 'enabled'
    );

    my $r4 = NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => 'id'.$nc_t->id.' && '.'id'.$nc_t->id,
        nodemetric_rule_state => 'enabled'
    );

    $orchestrator->manage_aggregates();

    dies_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node->id,
            verified_noderule_nodemetric_rule_id => $r1->id,
            verified_noderule_state              => 'verified',
        })
    } 'Check node 0 && 0';

    dies_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node->id,
            verified_noderule_nodemetric_rule_id => $r2->id,
            verified_noderule_state              => 'verified',
        })
    } 'Check node 0 && 1';

    dies_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node->id,
            verified_noderule_nodemetric_rule_id => $r3->id,
            verified_noderule_state              => 'verified',
        })
    } 'Check node 1 && 0';

    lives_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node->id,
            verified_noderule_nodemetric_rule_id => $r4->id,
            verified_noderule_state              => 'verified',
        })
    } 'Check node 1 && 1';
}

sub test_and {
    my $rule1 = AggregateRule->new(
        aggregate_rule_service_provider_id => $service_provider->id,
        aggregate_rule_formula => 'id'.$ac_t->id.' && id'.$ac_t->id,
        aggregate_rule_state => 'enabled'
    );

    my $rule2 = AggregateRule->new(
        aggregate_rule_service_provider_id => $service_provider->id,
        aggregate_rule_formula => 'id'.$ac_t->id.' && id'.$ac_f->id,
        aggregate_rule_state => 'enabled'
    );

    my $rule3 = AggregateRule->new(
        aggregate_rule_service_provider_id => $service_provider->id,
        aggregate_rule_formula => 'id'.$ac_f->id.' && id'.$ac_t->id,
        aggregate_rule_state => 'enabled'
    );

    my $rule4 = AggregateRule->new(
        aggregate_rule_service_provider_id => $service_provider->id,
        aggregate_rule_formula => 'id'.$ac_f->id.' && id'.$ac_f->id,
        aggregate_rule_state => 'enabled'
    );

    $orchestrator->manage_aggregates();
    is($rule1->eval, 1, 'Check 1 && 1 rule');
    is($rule2->eval, 0, 'Check 1 && 0 rule');
    is($rule3->eval, 0, 'Check 0 && 1 rule');
    is($rule4->eval, 0, 'Check 0 && 0 rule');
}
sub test_or_n {

    my $r1 = NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => 'id'.$nc_f->id.' || '.'id'.$nc_f->id,
        nodemetric_rule_state => 'enabled'
    );

    my $r2 = NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => 'id'.$nc_f->id.' || '.'id'.$nc_t->id,
        nodemetric_rule_state => 'enabled'
    );

    my $r3 = NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => 'id'.$nc_t->id.' || '.'id'.$nc_f->id,
        nodemetric_rule_state => 'enabled'
    );

    my $r4 = NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => 'id'.$nc_t->id.' || '.'id'.$nc_t->id,
        nodemetric_rule_state => 'enabled'
    );

    $orchestrator->manage_aggregates();

    dies_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node->id,
            verified_noderule_nodemetric_rule_id => $r1->id,
            verified_noderule_state              => 'verified',
        })
    } 'Check node 0 || 0';

    lives_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node->id,
            verified_noderule_nodemetric_rule_id => $r2->id,
            verified_noderule_state              => 'verified',
        })
    } 'Check node 0 || 1';

    lives_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node->id,
            verified_noderule_nodemetric_rule_id => $r3->id,
            verified_noderule_state              => 'verified',
        })
    } 'Check node 1 || 0';

    lives_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node->id,
            verified_noderule_nodemetric_rule_id => $r4->id,
            verified_noderule_state              => 'verified',
        })
    } 'Check node 1 || 1';
}

sub test_or {
    my $rule1 = AggregateRule->new(
        aggregate_rule_service_provider_id => $service_provider->id,
        aggregate_rule_formula => 'id'.$ac_t->id.' || id'.$ac_t->id,
        aggregate_rule_state => 'enabled'
    );

    my $rule2 = AggregateRule->new(
        aggregate_rule_service_provider_id => $service_provider->id,
        aggregate_rule_formula => 'id'.$ac_t->id.' || id'.$ac_f->id,
        aggregate_rule_state => 'enabled'
    );

    my $rule3 = AggregateRule->new(
        aggregate_rule_service_provider_id => $service_provider->id,
        aggregate_rule_formula => 'id'.$ac_f->id.' || id'.$ac_t->id,
        aggregate_rule_state => 'enabled'
    );

    my $rule4 = AggregateRule->new(
        aggregate_rule_service_provider_id => $service_provider->id,
        aggregate_rule_formula => 'id'.$ac_f->id.' || id'.$ac_f->id,
        aggregate_rule_state => 'enabled'
    );

    $orchestrator->manage_aggregates();
    is($rule1->eval, 1, 'Check 1 || 1 rule');
    is($rule2->eval, 1, 'Check 1 || 0 rule');
    is($rule3->eval, 1, 'Check 0 || 1 rule');
    is($rule4->eval, 0, 'Check 0 || 0 rule');
}

sub test_not_n {

    my $r1 = NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => '! id'.$nc_f->id,
        nodemetric_rule_state => 'enabled'
    );

    my $r2 = NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => '! id'.$nc_t->id,
        nodemetric_rule_state => 'enabled'
    );

    my $r3 = NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => 'not ! id'.$nc_f->id,
        nodemetric_rule_state => 'enabled'
    );

    my $r4 = NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => 'not ! id'.$nc_t->id,
        nodemetric_rule_state => 'enabled'
    );

    $orchestrator->manage_aggregates();
    lives_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node->id,
            verified_noderule_nodemetric_rule_id => $r1->id,
            verified_noderule_state              => 'verified',
        })
    } 'Check node rule ! 0';

    lives_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node2->id,
            verified_noderule_nodemetric_rule_id => $r1->id,
            verified_noderule_state              => 'undef',
        })
    } 'Check node rule ! undef';

    dies_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node->id,
            verified_noderule_nodemetric_rule_id => $r2->id,
            verified_noderule_state              => 'verified',
        });
    } 'Check node rule ! 1';

    dies_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node->id,
            verified_noderule_nodemetric_rule_id => $r3->id,
            verified_noderule_state              => 'verified',
        })
    } 'Check node rule not ! 0';

    lives_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node->id,
            verified_noderule_nodemetric_rule_id => $r4->id,
            verified_noderule_state              => 'verified',
        });
    } 'Check node rule not ! 1';

}


sub test_not{
    my $rule1 = AggregateRule->new(
        aggregate_rule_service_provider_id => $service_provider->id,
        aggregate_rule_formula => 'id'.$ac_t->id,
        aggregate_rule_state => 'enabled'
    );

    my $rule2 = AggregateRule->new(
        aggregate_rule_service_provider_id => $service_provider->id,
        aggregate_rule_formula => '! id'.$ac_t->id,
        aggregate_rule_state => 'enabled'
    );

    my $rule3 = AggregateRule->new(
        aggregate_rule_service_provider_id => $service_provider->id,
        aggregate_rule_formula => 'id'.$ac_f->id,
        aggregate_rule_state => 'enabled'
    );

    my $rule4 = AggregateRule->new(
        aggregate_rule_service_provider_id => $service_provider->id,
        aggregate_rule_formula => '! id'.$ac_f->id,
        aggregate_rule_state => 'enabled'
    );

    my $rule5 = AggregateRule->new(
        aggregate_rule_service_provider_id => $service_provider->id,
        aggregate_rule_formula => 'not ! id'.$ac_t->id,
        aggregate_rule_state => 'enabled'
    );

    my $rule6 = AggregateRule->new(
        aggregate_rule_service_provider_id => $service_provider->id,
        aggregate_rule_formula => '! not ! id'.$ac_t->id,
        aggregate_rule_state => 'enabled'
    );

    $orchestrator->manage_aggregates();
    is($rule1->eval, 1, 'Check 1 rule');
    is($rule2->eval, 0, 'Check ! 1 rule');
    is($rule3->eval, 0, 'Check 0 rule');
    is($rule4->eval, 1, 'Check ! 0 rule');
    is($rule5->eval, 1, 'Check not ! 1 rule');
    is($rule6->eval, 0, 'Check ! not ! 1 rule');
}

sub test_big_formulas_n {

    my $r1 = NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => '(!('.'id'.$nc_t->id.' && (!'.'id'.$nc_f->id.') && '.'id'.$nc_t->id.')) || ! ('.'id'.$nc_t->id.' && '.'id'.$nc_f->id.')',
        nodemetric_rule_state => 'enabled'
    );

    $orchestrator->manage_aggregates();

   lives_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node->id,
            verified_noderule_nodemetric_rule_id => $r1->id,
            verified_noderule_state              => 'verified',
        })
    } 'Check node (!(1 && (!0) && 1)) || ! (1 && 0)';

}

sub test_big_formulas {
    my $rule1 = AggregateRule->new(
        aggregate_rule_service_provider_id => $service_provider->id,
        aggregate_rule_formula => '(!! ('.'id'.$ac_t->id.' || '.'id'.$ac_f->id.')) && ('.'id'.$ac_t->id.' && '.'id'.$ac_t->id.')',
        aggregate_rule_state => 'enabled'
    );

    my $rule2 = AggregateRule->new(
        aggregate_rule_service_provider_id => $service_provider->id,
        aggregate_rule_formula => '(('.'id'.$ac_f->id.' || '.'id'.$ac_f->id.') || ('.'id'.$ac_f->id.' || '.'id'.$ac_t->id.')) && ! ( (! ('.'id'.$ac_f->id.' || '.'id'.$ac_t->id.')) || ! ('.'id'.$ac_t->id.' && '.'id'.$ac_t->id.'))',
        aggregate_rule_state => 'enabled'
    );

    $orchestrator->manage_aggregates();
    is($rule1->eval, 1, 'Check (!! (1 || 0)) && (1 && 1) rule');
    is($rule2->eval, 1, 'Check ((0 || 0) || (0 || 1)) && ! ( (! (0 || 1)) || ! (1 && 1)) rule');
}
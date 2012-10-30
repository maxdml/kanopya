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
    use Combination::AggregateCombination;
    use AggregateRule;
    use Combination::NodemetricCombination;
    use NodemetricCondition;
    use NodemetricRule;
    use VerifiedNoderule;
} 'All uses';

Administrator::authenticate( login =>'admin', password => 'K4n0pY4' );
my $adm = Administrator->new;
$adm->beginTransaction;

my ($indic1,$indic2);
my ($ac_f, $ac_t);
my ($ac_left, $ac_right, $ac_both);
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
    $indic1 = CollectorIndicator->find (
        hash => {
            collector_manager_id        => $mock_monitor->id,
            'indicator.indicator_oid'   => 'Memory/PercentMemoryUsed'
        }
    );

    $indic2 = ScomIndicator->find (
        hash => {
            service_provider_id => $service_provider->id,
            indicator_oid => 'Memory/Pool Paged Bytes'
        }
    );


    test_aggregate_combination();
    test_aggregate_rules();
    test_two_combinations_on_nodemetric_condition();
    test_aggregate_combination_on_nodemetric_condition();
    test_nodemetric_condition();
    test_nodemetric_rules();

    $adm->rollbackTransaction;
    #$adm->commitTransaction();
};
if($@) {
    $adm->rollbackTransaction;
    my $error = $@;
    print $error."\n";
}

sub test_nodemetric_condition {
    # Clustermetric
    my $cm = Clustermetric->new(
        clustermetric_service_provider_id => $service_provider->id,
        clustermetric_indicator_id => ($indic1->id),
        clustermetric_statistics_function_name => 'mean',
        clustermetric_window_time => '1200',
    );

    #  Nodemetric combination
    my $ncomb = Combination::NodemetricCombination->new(
        nodemetric_combination_service_provider_id => $service_provider->id,
        nodemetric_combination_formula => 'id'.($indic1->id),
    );

    # Aggregate Combination
    my $comb = Combination::AggregateCombination->new(
        aggregate_combination_service_provider_id   =>  $service_provider->id,
        aggregate_combination_formula               => 'id'.($cm->id),
    );

    my $nc_agg_th_right = NodemetricCondition->new(
        nodemetric_condition_service_provider_id => $service_provider->id,
        left_combination_id             => $comb->id,
        nodemetric_condition_comparator => '>',
        nodemetric_condition_threshold  => '-1.2',
    );

    my $nc_agg_th_left = NodemetricCondition->new(
        nodemetric_condition_service_provider_id => $service_provider->id,
        nodemetric_condition_threshold  => '-1.4',
        nodemetric_condition_comparator => '<',
        right_combination_id            => $comb->id,
    );

    my $nc_mix_1 = NodemetricCondition->new(
        nodemetric_condition_service_provider_id => $service_provider->id,
        left_combination_id             => $ncomb->id,
        nodemetric_condition_comparator => '<',
        right_combination_id            => $comb->id,
    );

    my $nc_mix_2 = NodemetricCondition->new(
        nodemetric_condition_service_provider_id => $service_provider->id,
        left_combination_id             => $comb->id,
        nodemetric_condition_comparator => '<',
        right_combination_id            => $ncomb->id,
    );

    my $comb_th_left;
    lives_ok {
        $comb_th_left = Combination::ConstantCombination->get(id => $nc_agg_th_right->right_combination_id),
    } 'Verify ConstantCombiantion creation on the right';

    my $comb_th_right;
    lives_ok {
        $comb_th_right = Combination::ConstantCombination->get(id => $nc_agg_th_left->left_combination_id),
    } 'Verify ConstantCombiantion creation on the left';

    $service_provider->addManagerParameter(
        manager_type    => 'collector_manager',
        name            => 'mockmonit_config',
        value           =>  "{'default':{'const':50},'nodes':{'node_1':{'const':1.234}, 'node_2':{'const':2.345}}}",
    );

    is ($comb_th_left->computeValueFromMonitoredValues(),-1.2,'Check left theshold value of nodemetric condition');
    is ($comb_th_right->computeValueFromMonitoredValues(),-1.4,'Check right theshold value of nodemetric condition');

    sleep(2);
    $aggregator->update();
    is($comb->computeValueFromMonitoredValues(),0.5*(1.234+2.345),'Check aggregate combination of nodemetric condition');


    my $r1 = NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => 'id'.$nc_agg_th_left->id,
        nodemetric_rule_state => 'enabled'
    );

    my $r2 = NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => 'id'.$nc_agg_th_left->id,
        nodemetric_rule_state => 'enabled'
    );

    my $r3 = NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => 'id'.$nc_mix_1->id,
        nodemetric_rule_state => 'enabled'
    );

    my $r4 = NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => 'id'.$nc_mix_2->id,
        nodemetric_rule_state => 'enabled'
    );

    sleep(2);
    $aggregator->update();
    $orchestrator->manage_aggregates();

    lives_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node->id,
            verified_noderule_nodemetric_rule_id => $r1->id,
            verified_noderule_state              => 'verified',
        })
    } 'Check nodemetric rule threshold on the right';

    lives_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node->id,
            verified_noderule_nodemetric_rule_id => $r2->id,
            verified_noderule_state              => 'verified',
        })
    } 'Check nodemetric rule threshold on the left';

    lives_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node->id,
            verified_noderule_nodemetric_rule_id => $r3->id,
            verified_noderule_state              => 'verified',
        })
    } 'Check mixed nodemetric rule node 1 (a)';

    dies_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node2->id,
            verified_noderule_nodemetric_rule_id => $r3->id,
        })
    } 'Check mixed nodemetric rule node 2 (a)';

    dies_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node->id,
            verified_noderule_nodemetric_rule_id => $r4->id,
        })
    } 'Check mixed nodemetric rule node 1 (b)';

    lives_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node2->id,
            verified_noderule_nodemetric_rule_id => $r4->id,
            verified_noderule_state              => 'verified',
        })
    } 'Check mixed nodemetric rule node 2 (b)';

    is ($nc_agg_th_right->toString(),'mean(RAM used)>-1.2','Check to String (a)');
    is ($nc_agg_th_left->toString(),'-1.4<mean(RAM used)','Check to String (b)');
    is ($nc_mix_1->toString(),'RAM used<mean(RAM used)','Check to String (c)');
    is ($nc_mix_2->toString(),'mean(RAM used)<RAM used','Check to String (d)');
}

sub test_two_combinations_on_nodemetric_condition {

    # Create nodemetric rule objects
    my $ncomb_left = Combination::NodemetricCombination->new(
        nodemetric_combination_service_provider_id => $service_provider->id,
        nodemetric_combination_formula => 'id'.($indic1->id),
    );

    # Create nodemetric rule objects
    my $ncomb_right = Combination::NodemetricCombination->new(
        nodemetric_combination_service_provider_id => $service_provider->id,
        nodemetric_combination_formula => 'id'.($indic2->id),
    );

    my $nc1 = NodemetricCondition->new(
        nodemetric_condition_service_provider_id => $service_provider->id,
        left_combination_id => $ncomb_left->id,
        right_combination_id => $ncomb_right->id,
        nodemetric_condition_comparator => '>',
    );

    my $nc2 = NodemetricCondition->new(
        nodemetric_condition_service_provider_id => $service_provider->id,
        left_combination_id => $ncomb_left->id,
        right_combination_id => $ncomb_right->id,
        nodemetric_condition_comparator => '<',
    );

    my $r1 = NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => 'id'.$nc1->id,
        nodemetric_rule_state => 'enabled'
    );

    my $r2 = NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => 'id'.$nc2->id,
        nodemetric_rule_state => 'enabled'
    );

    $service_provider->addManagerParameter(
        manager_type    => 'collector_manager',
        name            => 'mockmonit_config',
        value           =>  "{
                                  'default':{ 'const':50 },
                                  'indics' : {
                                 'Memory/PercentMemoryUsed' : { 'const':51 },
                                 'Memory/Pool Paged Bytes' : { 'const':50 }
                                  }
                             }",
    );

    sleep(2);
    $aggregator->update();
    $orchestrator->manage_aggregates();

    lives_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node->id,
            verified_noderule_nodemetric_rule_id => $r1->id,
            verified_noderule_state              => 'verified',
        })
    } 'Check 2 combinations on a nodemetric condition case verified';

    dies_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node->id,
            verified_noderule_nodemetric_rule_id => $r2->id,
            verified_noderule_state              => 'verified',
        })
    } 'Check 2 combinations on a nodemetric condition case not verified';
}

sub test_aggregate_combination_on_nodemetric_condition {
    # Clustermetric
    my $cm = Clustermetric->new(
        clustermetric_service_provider_id => $service_provider->id,
        clustermetric_indicator_id => ($indic1->id),
        clustermetric_statistics_function_name => 'sum',
        clustermetric_window_time => '1200',
    );

    # Combination
    my $comb = Combination::AggregateCombination->new(
        aggregate_combination_service_provider_id   =>  $service_provider->id,
        aggregate_combination_formula               => 'id'.($cm->id),
    );

    $nc_t = NodemetricCondition->new(
        nodemetric_condition_service_provider_id => $service_provider->id,
        left_combination_id => $comb->id,
        nodemetric_condition_comparator => '>',
        nodemetric_condition_threshold => '0',
    );

    my $r1 = NodemetricRule->new(
        nodemetric_rule_service_provider_id => $service_provider->id,
        nodemetric_rule_formula => 'id'.$nc_t->id,
        nodemetric_rule_state => 'enabled'
    );

    sleep(2);
    $aggregator->update();
    $orchestrator->manage_aggregates();

    lives_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node->id,
            verified_noderule_nodemetric_rule_id => $r1->id,
            verified_noderule_state              => 'verified',
        })
    } 'Check aggregate combination on aggregate condition node 1';

    lives_ok {
        VerifiedNoderule->find(hash => {
            verified_noderule_externalnode_id    => $node2->id,
            verified_noderule_nodemetric_rule_id => $r1->id,
            verified_noderule_state              => 'verified',
        })
    } 'Check aggregate combination on aggregate condition node 1';
}

sub test_nodemetric_rules {

    # Create nodemetric rule objects
    my $ncomb = Combination::NodemetricCombination->new(
        nodemetric_combination_service_provider_id => $service_provider->id,
        nodemetric_combination_formula => 'id'.($indic1->id),
    );

    $nc_f = NodemetricCondition->new(
        nodemetric_condition_service_provider_id => $service_provider->id,
        left_combination_id => $ncomb->id,
        nodemetric_condition_comparator => '<',
        nodemetric_condition_threshold => '0',
    );

    $nc_t = NodemetricCondition->new(
        nodemetric_condition_service_provider_id => $service_provider->id,
        left_combination_id => $ncomb->id,
        nodemetric_condition_comparator => '>',
        nodemetric_condition_threshold => '0',
    );

    $service_provider->addManagerParameter(
        manager_type    => 'collector_manager',
        name            => 'mockmonit_config',
        value           =>  "{'default':{'const':50},'nodes':{'node_2':{'const':null}}}",
    );

    sleep(2);
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

sub test_aggregate_combination {
    # Clustermetric
    my $cm = Clustermetric->new(
        clustermetric_service_provider_id => $service_provider->id,
        clustermetric_indicator_id => ($indic1->id),
        clustermetric_statistics_function_name => 'sum',
        clustermetric_window_time => '1200',
    );

    # Combination
    my $comb = Combination::AggregateCombination->new(
        aggregate_combination_service_provider_id   =>  $service_provider->id,
        aggregate_combination_formula               => 'id'.($cm->id),
    );

    # Combination
    my $comb2 = Combination::AggregateCombination->new(
        aggregate_combination_service_provider_id   =>  $service_provider->id,
        aggregate_combination_formula               => '2*id'.($cm->id),
    );

    # Condition
    $ac_left = AggregateCondition->new(
        aggregate_condition_service_provider_id => $service_provider->id,
        left_combination_id => $comb->id,
        comparator => '<',
        threshold => '12.34',
        state => 'enabled'
    );

    $ac_right = AggregateCondition->new(
        aggregate_condition_service_provider_id => $service_provider->id,
        threshold => '-43.21',
        comparator => '<',
        right_combination_id => $comb->id,
        state => 'enabled'
    );

    $ac_both = AggregateCondition->new(
        aggregate_condition_service_provider_id => $service_provider->id,
        left_combination_id  => $comb->id,
        comparator => '<',
        right_combination_id => $comb2->id,
        state => 'enabled'
    );

    $service_provider->addManagerParameter(
        manager_type    => 'collector_manager',
        name            => 'mockmonit_config',
        value           =>  "{'default':{'const':50},'nodes':{'node_1':{'const':1.234}, 'node_2':{'const':2.345}}}",
    );

    my $cc1;
    my $cc2;
    lives_ok {
        $cc1 = Combination->get(id => $ac_left->right_combination_id),
        $cc2 = Combination->get(id => $ac_right->left_combination_id),
    } 'Verify ConstantCombiantion creation';

    sleep(2);
    $aggregator->update();

    is ($cc1->computeLastValue(),12.34,'Check aggregate condition right theshold value');
    is ($cc2->computeLastValue(),-43.21,'Check aggregate condition left theshold value');
    is ($comb->computeLastValue(),3.579, 'Check aggregate condition mock monitor combination value (a)');
    is ($comb2->computeLastValue(),2*3.579, 'Check aggregate condition mock monitor combination value (b)');

    is ($ac_left->eval,1, 'Check condition combi left');
    is ($ac_right->eval,1, 'Check condition combi right');
    is ($ac_both->eval,1, 'Check condition combi both');


    is ($ac_left->toString(),'sum(RAM used)<12.34','Check to string (a)');
    is ($ac_right->toString(),'-43.21<sum(RAM used)','Check to string (b)');
    is ($ac_both->toString(),'sum(RAM used)<2*sum(RAM used)','Check to string (c)');
    # Condition are not verified when not linked to a rule
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
    my $comb = Combination::AggregateCombination->new(
        aggregate_combination_service_provider_id   =>  $service_provider->id,
        aggregate_combination_formula               => 'id'.($cm->id),
    );

    # Condition
    $ac_t = AggregateCondition->new(
        aggregate_condition_service_provider_id => $service_provider->id,
        left_combination_id => $comb->id,
        comparator => '>',
        threshold => '0',
        state => 'enabled'
    );

    $ac_f = AggregateCondition->new(
        aggregate_condition_service_provider_id => $service_provider->id,
        right_combination_id => $comb->id,
        comparator => '>',
        threshold => '0',
        state => 'enabled'
    );

    # No node responds
    $service_provider->addManagerParameter(
        manager_type    => 'collector_manager',
        name            => 'mockmonit_config',
        value           =>  "{'default':{'const':50},'nodes':{'node_2':{'const':null}}}",
    );

    sleep(2);
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


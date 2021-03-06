#!/usr/bin/perl -w

=pod
=begin classdoc

Triggering and return of sco workflow using node and cluster rules

=end classdoc
=cut

use strict;
use warnings;

use Test::More 'no_plan';
use Test::Exception;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init({
    level=>'INFO',
    file=>'sco_workflow_triggered_by_rule.log',
    layout=>'%d [ %H - %P ] %p -> %M - %m%n'
});

use Kanopya::Database;

use Daemon::RulesEngine;
use Daemon::Aggregator;
use Entity::CollectorIndicator;
use Entity::ServiceProvider::Externalcluster;
use Entity::Component::MockMonitor;
use Entity::Component::Sco;
use Entity::Component::KanopyaExecutor;
use Entity::Workflow;
use Entity::Operation;
use Entity::Metric::Combination;
use Entity::Metric::Combination::NodemetricCombination;
use Entity::NodemetricCondition;
use Entity::Rule::NodemetricRule;
use VerifiedNoderule;
use WorkflowNoderule;
use Entity::Metric::Clustermetric;
use Entity::AggregateCondition;
use Entity::Metric::Combination::AggregateCombination;
use Entity::Rule::AggregateRule;
use Kanopya::Test::Execution;
use Kanopya::Test::TestUtils 'expectedException';
use Entity::Node;

use TryCatch;

my $testing = 0;

my $service_provider;
my @all_objects = ();

try {
    main();
}
catch ($err) {
    clean_infra();
    throw Kanopya::Exception::Internal(error => "$err");
}

sub main {

    if ($testing == 1) {
        Kanopya::Database::beginTransaction;
    }

    Kanopya::Test::Execution->purgeQueues();

    sco_workflow_triggered_by_rule();
    clean_infra();

    Kanopya::Test::Execution->purgeQueues();

    if ($testing == 1) {
        Kanopya::Database::rollbackTransaction;
    }
}

sub sco_workflow_triggered_by_rule {
    my $aggregator = Daemon::Aggregator->new();

    my $external_cluster_mockmonitor = Entity::ServiceProvider::Externalcluster->new(
            externalcluster_name => 'Test Monitor',
    );
    push @all_objects, $external_cluster_mockmonitor;

    my $mock_monitor = Entity::Component::MockMonitor->new(
            service_provider_id => $external_cluster_mockmonitor->id,
    );
    push @all_objects, $mock_monitor;

    $service_provider = Entity::ServiceProvider::Externalcluster->new(
            externalcluster_name => 'Test Service Provider',
    );
    push @all_objects, $service_provider;

    # Create one node
    my $node = Entity::Node->new(
        node_hostname => 'test_node',
        service_provider_id   => $service_provider->id,
        monitoring_state    => 'up',
    );
    push @all_objects, $node;

    diag('Add mock monitor to service provider');
    my $manager = $service_provider->addManager(
        manager_id      => $mock_monitor->id,
        manager_type    => 'CollectorManager',
        no_default_conf => 1,
    );
    push @all_objects, $manager;

    my @indicators = Entity::CollectorIndicator->search(hash => {collector_manager_id => $mock_monitor->id});

    my $agg_rules  = _service_rule_objects_creation(indicators => \@indicators);
    my $node_rules = _node_rule_objects_creation(indicators => \@indicators);

    sleep 2;
    $aggregator->update();

    # Launch orchestrator with no workflow to trigger
    my $rulesengine = Daemon::RulesEngine->new();
    $rulesengine->_component->time_step(2);
    $rulesengine->refreshConfiguration();

    $rulesengine->oneRun();

    diag('Check rules verification');
    check_rule_verification(
            agg_rule1_id  => $agg_rules->{agg_rule1}->id,
            agg_rule2_id  => $agg_rules->{agg_rule2}->id,
            node_rule1_id => $node_rules->{node_rule1}->id,
            node_rule2_id => $node_rules->{node_rule2}->id,
            node_id       => $node->id,
    );

    #Create a SCO workflow
    my $external_cluster_sco = Entity::ServiceProvider::Externalcluster->new(
            externalcluster_name => 'Test SCO Workflow Manager',
    );

    push @all_objects, $external_cluster_sco;

    my $sco = Entity::Component::Sco->new(
            service_provider_id => $external_cluster_sco->id,
            executor_component_id => Entity::Component::KanopyaExecutor->find->id
    );

    push @all_objects, $sco;

    diag('Add workflow manager to service provider');
    my $manager2 = $service_provider->addManager(
        manager_id   => $sco->id,
        manager_type => 'WorkflowManager',
    );
    push @all_objects, $manager2;

    diag('Create a new node workflow');
    my $node_wf = $sco->createWorkflowDef(
        workflow_name => 'Test Workflow',
        params => {
            internal => {
                scope_id   => 1,
                output_dir => '/tmp',
                period => 5,
            },
            data => {
                template_content => '[% node_hostname %]',
            },
        }
    );
    push @all_objects, $node_wf;

    diag('Create a new service workflow');
    my $service_wf = $sco->createWorkflowDef(
        workflow_name => 'Test service Workflow',
        params => {
            internal => {
                scope_id   => 2,
                output_dir => '/tmp',
                period => 5,
            },
            data => {
                template_content => '[% service_provider_name %] [% specific_attribute %]',
            },
        }
    );
    push @all_objects, $service_wf;


    diag('Associate node workflow to node rule 2');
    my $aw1 = $node_rules->{node_rule2}->associateWorkflow(workflow_def_id => $node_wf->id);
    push @all_objects, Entity::Rule->get(id => $node_rules->{node_rule2}->id);

    diag('Associate service workflow to service rule 2');
    my $aw2 = $agg_rules->{agg_rule2}->associateWorkflow(workflow_def_id => $service_wf->id,
                                                         specific_params => { specific_attribute => 'hello world!' });

    push @all_objects, Entity::Rule->get(id => $agg_rules->{agg_rule2}->id);

    #Launch orchestrator a workflow must be enqueued
    $rulesengine->oneRun();


    my ($node_workflow, $service_workflow, $sco_operation, $service_sco_operation);
    lives_ok {
        # diag('Check triggered node workflow');

        my @trigered_node_workflows = $node_rules->{node_rule2}->workflow_noderules;
        if (scalar(@trigered_node_workflows) != 1) {
            die ("The node rule node_rule2 should have trigered exactly 1 workflow, " . scalar(@trigered_node_workflows) .  "found.");
        }
        $node_workflow = (pop @trigered_node_workflows)->workflow;

        diag('Check triggered service workflow');
        $service_workflow = $agg_rules->{agg_rule2}->reload->workflow;

        diag('Check WorkflowNoderule creation');
        WorkflowNoderule->find(hash=>{
            node_id => $node->id,
            nodemetric_rule_id  => $node_rules->{node_rule2}->id,
            workflow_id => $node_workflow->id,
        });

        # diag('Check triggered node enqueued operation');
        my $op_node = Entity::Operation->find( hash => {
                          'operationtype.operationtype_name' => 'LaunchSCOWorkflow',
                           state                             => 'pending',
                           workflow_id                       => $node_workflow->id,
                      });

        diag('Check triggered service enqueued operation');
        my $op_sco = Entity::Operation->find( hash => {
                         'operationtype.operationtype_name' => 'LaunchSCOWorkflow',
                          state                             => 'pending',
                          workflow_id                       => $service_workflow->id,
                     });

        # Execute operation 4 times (1 time per trigerred rule * 2 (op confirmation + op workflow))
        # Warning, excecutor may execute twice a postreported operation then the test may fail
        # with 8 executions we decrease the probability a bit but the problem is not solved
        # TODO try to use executeOperation + handleResult like the followed commented part

        # Run the both workflows
        Kanopya::Test::Execution->_executor->oneRun(cbname => 'run_workflow', duration => 1);
        Kanopya::Test::Execution->_executor->oneRun(cbname => 'run_workflow', duration => 1);

        # Execute and handle result of both first ProcessRule operations
        Kanopya::Test::Execution->_executor->oneRun(cbname => 'execute_operation', duration => 1);
        Kanopya::Test::Execution->_executor->oneRun(cbname => 'execute_operation', duration => 1);
        Kanopya::Test::Execution->_executor->oneRun(cbname => 'handle_result', duration => 1);
        Kanopya::Test::Execution->_executor->oneRun(cbname => 'handle_result', duration => 1);

        # Execute and handle result of both second LaunchSCOWorkflow operations,
        Kanopya::Test::Execution->_executor->oneRun(cbname => 'execute_operation', duration => 1);
        Kanopya::Test::Execution->_executor->oneRun(cbname => 'execute_operation', duration => 1);
        # Kee the connection after fetvch the first operation result as the first operation will be reported
        # and if the connection rest for the next fetch, the operation has been re inserted in queue and
        # will be fetched infinitly.
        Kanopya::Test::Execution->_executor->oneRun(cbname => 'handle_result', duration => 1, keep_connection => 1);
        Kanopya::Test::Execution->_executor->oneRun(cbname => 'handle_result', duration => 1);

#        my $executor = Executor->new(duration => 'SECOND');
#        my @processes_rules = Entity::Operation->search(hash => {'operationtype.operationtype_name' => 'ProcessRule'});
#        my $p1 = (pop @processes_rules);
#        $executor->executeOperation(operation_id => $p1->id);
#        $executor->handleResult(operation_id => $p1->id, status => $p1->state);

        #  Check node rule output
        diag('Check postreported operation');
        $sco_operation = Entity::Operation->find( hash => {
                             state                              => 'postreported',
                             workflow_id                        => $node_workflow->id,
                             'operationtype.operationtype_name' => 'LaunchSCOWorkflow',
                         });

        my $output_file = '/tmp/'.($sco_operation->unserializeParams->{output_file});
        my $return_file = $sco_operation->unserializeParams->{return_file};

        diag('Open the output file');
        open(FILE,$output_file);

        my @lines;
        while (<FILE>) {
            push @lines, $_;
        }

        diag('Check if node file contain line 1');
        die 'Node file does not contain line 1' if ( $lines[0] ne $node->node_hostname."\n");

        diag('Check if node file contain line 2');
        die 'Node file does not contain line 2' if ( $lines[1] ne $return_file);

        close(FILE);

        diag('Rename the output sco node file');
        chdir "/tmp";
        rename($output_file,$return_file);
        open(FILE,$return_file);
        close(FILE);

        #  Check service rule output
        diag('Check postreported service sco operation');
        $service_sco_operation = Entity::Operation->find( hash => {
                                     'operationtype.operationtype_name' => 'LaunchSCOWorkflow',
                                      state                             => 'postreported',
                                      workflow_id                       => $service_workflow->id,
                                 });

        $output_file = '/tmp/'.($service_sco_operation->unserializeParams->{output_file});
        $return_file = $service_sco_operation->unserializeParams->{return_file};

        diag('Open the output service file');
        open(FILE,$output_file);

        @lines= ();
        while (<FILE>) {
            push @lines, $_;
        }

        diag('Check if service file contain line 1');
        die 'Service file does not contain line 1' if ($lines[0] ne $service_provider->externalcluster_name." hello world!\n");

        diag('Check if service file contain line 2');
        die 'Service file does not contain line 2' if ($lines[1] ne $return_file);

        close(FILE);

        diag('Rename the output sco service file');
        chdir "/tmp";
        rename($output_file,$return_file);
        open(FILE,$return_file);
        close(FILE);
    } 'Triggering of SCO workflow using rule (node and service scope)';


    lives_ok {

        # Warning : the hoped_execution_time modification does not decrease the postreported
        # time anymore. So the test has to wait the delay of the postreported operation
        # (currently 600 seconds)
        # TODO Find another way to decrease the time

        # Modify hoped_execution_time in order to avoid waiting for the delayed time
        $sco_operation->setAttr( name => 'hoped_execution_time', value => time() - 1);
        $sco_operation->save();

        # Modify hoped_execution_time in order to avoid waiting for the delayed time
        $service_sco_operation->setAttr( name => 'hoped_execution_time', value => time() - 1);
        $service_sco_operation->save();

        Kanopya::Test::Execution->executeAll(timeout => 660);

        expectedException {
            Entity::Operation->find( hash => {
                'operationtype.operationtype_name' => 'LaunchSCOWorkflow',
                workflow_id => $node_workflow->id,
            });
        } 'Kanopya::Exception::Internal::NotFound',
        'Check node operation has been deleted';

        expectedException {
            Entity::Operation->find( hash => {
                'operationtype.operationtype_name' => 'LaunchSCOWorkflow',
                workflow_id => $service_workflow->id,
            });
        } 'Kanopya::Exception::Internal::NotFound',
        'Check service operation has been deleted';

        diag('Check if node workflow is done');
        $node_workflow = Entity::Workflow->find(hash=>{
            workflow_id => $node_workflow->id,
            state => 'done',
        });

        diag('Check if service workflow is done');
        $service_workflow = Entity::Workflow->find(hash=>{
            workflow_id => $service_workflow->id,
        });

        # Modify node rule2 to avoid a new triggering
        my $node_rule2 = Entity::Rule::NodemetricRule->get(id => $node_rules->{node_rule2}->id);
        $node_rule2->setAttr(name => 'formula', value => '! ('.$node_rule2->formula.')');
        $node_rule2->save();

        # Modify service rule2 to avoid a new triggering
        my $agg_rule2 = Entity::Rule::AggregateRule->get(id => $agg_rules->{agg_rule2}->id);
        $agg_rule2->setAttr(name => 'formula', value => 'not ('.$agg_rule2->formula.')');
        $agg_rule2->save();

        # Launch Orchestrator
        $rulesengine->oneRun();

        expectedException {
            VerifiedNoderule->find(hash => {
                verified_noderule_node_id    => $node->id,
                verified_noderule_nodemetric_rule_id => $node_rules->{node_rule2}->id,
                verified_noderule_state              => 'verified',
            });
        } 'Kanopya::Exception::Internal::NotFound',
        'Check node rule 2 is not verified after formula has changed';

        diag('Check if service rule 2 is not verified after formula has changed');
        Entity::Rule::AggregateRule->find(hash => {
            aggregate_rule_id => $agg_rules->{agg_rule2}->id,
            aggregate_rule_last_eval => 0,
        });

        expectedException {
            WorkflowNoderule->find(hash=>{
                node_id => $node->id,
                nodemetric_rule_id  => $node_rule2->id,
                workflow_id => $node_workflow->id,
            });
        } 'Kanopya::Exception::Internal::NotFound',
        'Check node WorkflowNoderule has been deleted';

        expectedException {
            WorkflowNoderule->find(hash=>{
                node_id => $node->id,
                nodemetric_rule_id  => $agg_rule2->id,
                workflow_id => $service_workflow->id,
            });
        } 'Kanopya::Exception::Internal::NotFound',
        'Check service WorkflowNoderule has been deleted';

        diag('Check node metric workflow def');
        my $wf1 = Entity->get(id=>$node_rule2->id)->workflow_def;

        diag('Check service metric workflow def');
        my $wf2 = Entity->get(id=>$agg_rule2->id)->workflow_def;

        $node_rule2->delete();
        $agg_rule2->delete();
    } 'Ending of triggered SCO workflow (node and service scope)';
}

sub check_rule_verification {
    my %args = @_;

    diag('# Service rule 1 verification');
    Entity::Rule::AggregateRule->find(hash => {
        aggregate_rule_id => $args{agg_rule1_id},
        aggregate_rule_last_eval => 0,
    });

    diag('# Service rule 2 verification');
    Entity::Rule::AggregateRule->find(hash => {
        aggregate_rule_id => $args{agg_rule2_id},
        aggregate_rule_last_eval => 1,
    });

    diag('# Node rule 1 verification');
    expectedException {
        VerifiedNoderule->find(hash => {
            verified_noderule_node_id    => $args{node_id},
            verified_noderule_nodemetric_rule_id => $args{node_rule1_id},
            verified_noderule_state              => 'verified',
        });
    } 'Kanopya::Exception::Internal::NotFound', 'Node rule 1 is not verified';

    diag('# Node rule 2 verification');
    VerifiedNoderule->find(hash => {
        verified_noderule_node_id    => $args{node_id},
        verified_noderule_nodemetric_rule_id => $args{node_rule2_id},
        verified_noderule_state              => 'verified',
    });
}

sub clean_infra {

    my $service_provider_id = $service_provider ? $service_provider->id : undef;

    while (@all_objects) {
        my $object = (pop @all_objects);
        try {
            $object->delete();
        }
        catch ($err) {
            print $err;
        }
    }

    if (defined $service_provider_id) {
        my @cms = Entity::Metric::Clustermetric->search (hash => {
                      clustermetric_service_provider_id => $service_provider->id
                  });
        my @cm_ids = map {$_->id} @cms;

        diag('Check if all aggregrate combinations have been deleted');
        my @acs = Entity::Metric::Combination::AggregateCombination->search (hash => {
                      service_provider_id => $service_provider->id
                  });
        if ( scalar @acs == 0 ) {
            diag('-> checked');
        }
        else {
            die 'All aggregate combinations have not been deleted';
        }

        diag('Check if all aggregrate rules have been deleted');
        my @ars = Entity::Rule::AggregateRule->search (hash => {
            service_provider_id => $service_provider->id
        });
        if ( scalar @ars == 0 ) {
            diag('-> checked');
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
            diag('-> checked');
        }
        else {
             die "All rrd have not been removed, still $one_rrd_remove rrd";
        }
    }



}

sub _service_rule_objects_creation {
    my %args = @_;
    my @indicators = @{$args{indicators}};

    my $rule1;
    my $rule2;

    my $service_provider = Entity::ServiceProvider::Externalcluster->find(
        hash => {externalcluster_name => 'Test Service Provider'}
    );

    my $cm1 = Entity::Metric::Clustermetric->new(
                  clustermetric_service_provider_id => $service_provider->id,
                  clustermetric_indicator_id => ((pop @indicators)->id),
                  clustermetric_statistics_function_name => 'mean',
              );

    my $cm2 = Entity::Metric::Clustermetric->new(
                  clustermetric_service_provider_id => $service_provider->id,
                  clustermetric_indicator_id => ((pop @indicators)->id),
                  clustermetric_statistics_function_name => 'std',
              );

    my $acomb1 = Entity::Metric::Combination::AggregateCombination->new(
                     service_provider_id             =>  $service_provider->id,
                     aggregate_combination_formula   => 'id' . ($cm1->id) . ' + id' . ($cm2->id),
                 );

    my $acomb2 = Entity::Metric::Combination::AggregateCombination->new(
                     service_provider_id             =>  $service_provider->id,
                     aggregate_combination_formula   => 'id' . ($cm1->id) . ' + id' . ($cm1->id),
                 );

    my $ac1 = Entity::AggregateCondition->new(
        aggregate_condition_service_provider_id => $service_provider->id,
        left_combination_id => $acomb1->id,
        comparator => '>',
        threshold => '0',
    );

    my $ac2 = Entity::AggregateCondition->new(
        aggregate_condition_service_provider_id => $service_provider->id,
        left_combination_id => $acomb2->id,
        comparator => '<',
        threshold => '0',
    );

    $rule1 = Entity::Rule::AggregateRule->new(
        service_provider_id => $service_provider->id,
        formula => 'id'.$ac1->id.' && id'.$ac2->id,
        state => 'enabled'
    );

    $rule2 = Entity::Rule::AggregateRule->new(
        service_provider_id => $service_provider->id,
        formula => 'id'.$ac1->id.' || id'.$ac2->id,
        state => 'enabled'
    );

    return {
        agg_rule1 => $rule1,
        agg_rule2 => $rule2,
    };
}

sub _node_rule_objects_creation {
    my %args = @_;
    my @indicators = @{$args{indicators}};
    my $rule1;
    my $rule2;

    my $service_provider = Entity::ServiceProvider::Externalcluster->find(
        hash => {externalcluster_name => 'Test Service Provider'}
    );

    # Create nodemetric rule objects
    my $ncomb1 = Entity::Metric::Combination::NodemetricCombination->new(
                     service_provider_id             => $service_provider->id,
                     nodemetric_combination_formula  => 'id' . ($indicators[0]->id)
                                                        . ' + id' . ($indicators[1]->id),
                 );

    my $ncomb2 = Entity::Metric::Combination::NodemetricCombination->new(
                     service_provider_id             => $service_provider->id,
                     nodemetric_combination_formula  => 'id' . ($indicators[2]->id)
                                                        . ' + id' . ($indicators[3]->id),
                 );

    my $nc1 = Entity::NodemetricCondition->new(
        nodemetric_condition_service_provider_id => $service_provider->id,
        left_combination_id => $ncomb1->id,
        nodemetric_condition_comparator => '>',
        nodemetric_condition_threshold => '0',
    );

    my $nc2 = Entity::NodemetricCondition->new(
        nodemetric_condition_service_provider_id => $service_provider->id,
        left_combination_id => $ncomb2->id,
        nodemetric_condition_comparator => '<',
        nodemetric_condition_threshold => '0',
    );

    $rule1 = Entity::Rule::NodemetricRule->new(
        service_provider_id => $service_provider->id,
        formula => 'id'.$nc1->id.' && id'.$nc2->id,
        state => 'enabled'
    );

    $rule2 = Entity::Rule::NodemetricRule->new(
        service_provider_id => $service_provider->id,
        formula => 'id'.$nc1->id.' || id'.$nc2->id,
        state => 'enabled'
    );

    return {
        node_rule1 => $rule1,
        node_rule2 => $rule2,
    };
}

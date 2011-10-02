#    Copyright © 2011 Hedera Technology SAS
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
package Controller;

use strict;
use warnings;
use Data::Dumper;
use Administrator;
use XML::Simple;

use Monitor::Retriever;
use Entity::Cluster;
use CapacityPlanning::IncrementalSearch;
use Model::MVAModel;

use Log::Log4perl "get_logger";

my $log = get_logger("orchestrator");

sub new {
    my $class = shift;
    my %args = @_;
    
    my $self = {};
    bless $self, $class;
    
    $self->_authenticate();
    
    $self->init();
    
    return $self;
}

sub _authenticate {
    my $self = shift;
    
    $self->{config} = XMLin("/opt/kanopya/conf/orchestrator.conf");
    if ( (! defined $self->{config}{user}{name}) ||
         (! defined $self->{config}{user}{password}) ) { 
        throw Kanopya::Exception::Internal::IncorrectParam(error => "needs user definition in config file!");
    }
    Administrator::authenticate( login => $self->{config}{user}{name},
                                 password => $self->{config}{user}{password});
                                 
    
    return;
}

sub init {
    my $self = shift;
    
    my $admin = Administrator->new();
    $self->{data_manager} = $admin->{manager}{rules};
    
    $self->{_monitor} = Monitor::Retriever->new( );
    
    $self->{_time_step} = 30; # controller update frequency
    $self->{_time_laps} = 60; # metrics retrieving laps
    
    my $cap_plan = CapacityPlanning::IncrementalSearch->new();
    my $model = Model::MVAModel->new();
    $self->{_model} = $model;
    $cap_plan->setModel(model => $model);
    #$cap_plan->setConstraints(constraints => { max_latency => 22, max_abort_rate => 0.3 } );
    
    $self->{_cap_plan} = $cap_plan;

    
}

sub getControllerRRD {
    my $self = shift;
    my %args = @_;
    
    # RRD

    my $cluster_id = $args{cluster}->getAttr('name' => 'cluster_id');

    my $rrd_file = "/tmp/cluster" . $cluster_id .  "_controller.rrd";
    my $rrd = RRDTool::OO->new( file =>  $rrd_file );
    if ( not -e $rrd_file ) {    
        
        $rrd->create(
                     step        => $self->{_time_step},  # interval
                     data_source => { name    => "workload_amount",
                                       type     => "GAUGE" },
                    data_source => { name      => "latency",
                                       type     => "GAUGE" },
                      data_source => { name    => "abort_rate",
                                       type      => "GAUGE" },
                    data_source => { name      => "throughput",
                                       type      => "GAUGE" },
                     archive     => { rows      => 500 }
                     );
    }
    
    return $rrd;
}

sub getClusterConf {
    my $self = shift;
    my %args = @_;

    my $cluster = $args{cluster};
    
    my @hosts = values %{ $cluster->getMotherboards( ) };
    my @in_nodes = grep { $_->getNodeState() =~ '^in' } @hosts; 

    # TODO get mpl from cluster/component
    return {nb_nodes => scalar(@in_nodes), mpl => 1000};
}

sub getWorkload {
    my $self = shift;
    my %args = @_;

    #my $cluster = $args{cluster};

    my $service_info_set = "haproxy_conn"; #"apache_workers";
    my $load_metric = "Active"; #"BusyWorkers";


    my $cluster_name = $args{cluster}->getAttr('name' => 'cluster_name');
    my $cluster_id = $args{cluster}->getAttr('name' => 'cluster_id');

    my $cluster_data_aggreg = $self->{_monitor}->getClusterData( cluster => $cluster_name,
                                                                 set => $service_info_set,
                                                                 time_laps => $self->{_time_laps});

    print Dumper $cluster_data_aggreg;
        
        
    if (not defined $cluster_data_aggreg->{$load_metric} ) {
#        throw Kanopya::Exception::Internal( error => "Can't get workload amount from monitoring" );    
    }
    
    my $workload_amount = $cluster_data_aggreg->{$load_metric};

    # Get model parameters for this cluster (tier)
    my $cluster_workload_class = $self->{data_manager}->getClusterModelParameters( cluster_id =>  $cluster_id );
    # Compute workload class (i.e we put param for each cluster in an array representing each tiers) to be used by model 
    my %workload_class = (  visit_ratio => [ $cluster_workload_class->{visit_ratio} ],
                            service_time => [ $cluster_workload_class->{service_time} ],
                            delay => [ $cluster_workload_class->{delay} ],
                            think_time => $cluster_workload_class->{think_time} );
    

    return { workload_class => \%workload_class, workload_amount => $workload_amount };
}


sub getMonitoredPerfMetrics {
    my $self = shift;
    my %args = @_;
    
    my $cluster_name = $args{cluster}->getAttr('name' => 'cluster_name');
    
    my $cluster_data_aggreg = $self->{_monitor}->getClusterData( cluster => $cluster_name,
                                                                 set => "haproxy_timers",
                                                                 time_laps => $self->{_time_laps});

    print Dumper $cluster_data_aggreg;
    
    return {
      latency => $cluster_data_aggreg->{Tt},
      abort_rate => 0,
      throughput => 0,
    };
}

sub updateModelInternaParameters {
    my $self = shift;
    my %args = @_;
    
    my $cluster_id = $args{cluster}->getAttr('name' => 'cluster_id');
    
    $log->debug("update parameters: D = " . (Dumper $args{delay}) . " ## S = " . (Dumper $args{service_time}) );
    
    # We update parameters for one cluster (considering only one tier for the moment, no infra entity yet)
    $self->{data_manager}->setClusterModelParameters( 
                                                        cluster_id =>  $cluster_id,
                                                        delay => $args{delay}[0],
                                                        service_time => $args{service_time}[0]  );
}

sub manageCluster {
    my $self = shift;
    my %args = @_;

    General::checkParams args => \%args, required => ['cluster'];

    my $cluster = $args{cluster};
    my $cluster_id = $args{cluster}->getAttr('name' => 'cluster_id');

    # Refresh qos constraints
    my $constraints = $self->{data_manager}->getClusterQoSConstraints( cluster_id => $cluster_id );
    $self->{_cap_plan}->setConstraints(constraints => $constraints );    

    my $cluster_conf = $self->getClusterConf( cluster => $cluster );
    my $mpl = $cluster_conf->{mpl};
    
    $self->{_cap_plan}->setSearchSpaceForTiers( search_spaces =>     [ 
                                                                    {   min_node => $cluster->getAttr(name => 'cluster_min_node'), 
                                                                        max_node => $cluster->getAttr(name => 'cluster_max_node'),
                                                                        min_mpl => $mpl,
                                                                        max_mpl => $mpl,}
                                                                    ]
                                                );
    
    $self->{_cap_plan}->setNbTiers( tiers => 1);
    
    my $workload = $self->getWorkload( cluster => $cluster);
    
    # Manage internal parameters tuning
    my $best_params = $self->modelTuning( workload => $workload, cluster_conf => $cluster_conf, cluster => $cluster );
    $self->updateModelInternaParameters( cluster => $cluster, delay => $best_params->{D}, service_time => $best_params->{S});
    
    $self->validateModel( workload => $workload, cluster_conf => $cluster_conf, cluster => $cluster );
    #$self->store( workload => $workload );
    
    
    my $conf = $self->{_cap_plan}->calculate(   workload_amount => $workload->{workload_amount},
                                                workload_class => $workload->{workload_class} );
    
    $self->applyConf( conf => $conf, cluster => $cluster);
}

=head2 modelTuning

    Desc : compute model internal parmaters (Si, Di) according to simulated output and measured output
    
    Args :

    Return :
    
=cut

sub modelTuning {
    my $self = shift;
    my %args = @_;
    
    my $M = 1; #nb tiers
    my $infra_conf = {  M => $M,
                        AC => [$args{cluster_conf}->{nb_nodes}],
                        LC => [$args{cluster_conf}->{mpl}]
                      };
    my $workload = $args{workload};
    
    my $NB_STEPS = 15;
    my $INIT_STEP_SIZE = 5;
    my $INIT_POINT_POSITION = 6;
    
    my @best_S = ($INIT_POINT_POSITION) x $M;
    my @best_D = ($INIT_POINT_POSITION) x $M;
    $best_D[0] = 1;
    my $best_gain = 0;
    my $dim_best_gain = 0;
    my $evo_best_gain = 0;
    
    my $evo_step = $INIT_STEP_SIZE;
    
    my $curr_perf = $self->getMonitoredPerfMetrics( cluster => $args{cluster});
    
    for my $step (0..($NB_STEPS-1)) {
        
        # For each space dimension (internal parameters except D1)
        for my $dim (0..(2*$M-1-1)) { # -1 for D1 and -1 because we start at 0
            
            # Evolution direction for this dimension
            EVO:
            for (my $evo = -$evo_step; $evo < $evo_step; $evo += 2*$evo_step ) {
                
                my @S = @best_S;
                my @D = @best_D;
                
                if ($dim < $M) {
                    $S[$dim] += $evo;
                    next EVO if ($S[$dim] <= 0); # Prevent null or negative Si
                } else {
                    $D[$dim - $M + 1] += $evo;
                    next EVO if ($S[$dim] < 0); # Null delay allowed
                }
                
                
                my %model_params = (
                        configuration => $infra_conf,
                        workload_amount => $workload->{workload_amount},
                        workload_class => {
                                            visit_ratio => $workload->{workload_class}{visit_ratio},
                                            think_time  => $workload->{workload_class}{think_time},
                                            service_time => \@S,
                                            delay => \@D,
                                           }
                );
                
                my %new_out = $self->{_model}->calculate( %model_params );
                
                $model_params{workload_class}{service_time} = \@best_S;
                $model_params{workload_class}{delay} = \@best_D;
                
                my %best_out = $self->{_model}->calculate( %model_params );
                
                my $gain =  $self->computeDiff( model_output => \%best_out, monitored_perf => $curr_perf )
                            - $self->computeDiff( model_output => \%new_out, monitored_perf => $curr_perf );
                
                if ($gain > $best_gain) {
                    $best_gain = $gain;
                    $dim_best_gain = $dim;
                    $evo_best_gain = $evo;
                }
                
            } # end evo
        } #end dim
        if ($dim_best_gain < $M) {
            $best_S[$dim_best_gain] += $evo_best_gain;
        } else {
            $best_D[$dim_best_gain - $M + 1] += $evo_best_gain;
        }
        
        # Avoid oscillations around optimal
        if ($best_gain <= 0) {
            $evo_step /= 2;
        }
    } # end step
    
    return { D => \@best_D, S => \@best_S };
}

sub computeDiff {
    my $self = shift;
    my %args = @_;
    
    my $curr_perf = $args{monitored_perf};
    my $model_perf = $args{model_output};
    
    # weight of each parameters
    my %weights = ( latency => 1, abort_rate => 1, throughput => 1);

    my %deviations  = ( latency => 0, abort_rate => 0, throughput => 0);
    
    my $weight = 0;
    for my $metric ('latency', 'abort_rate', 'throughput') {
        if ($curr_perf->{$metric} > 0) {
            $deviations{$metric} = abs( $model_perf->{$metric} - $curr_perf->{$metric} ) * 100 / $curr_perf->{$metric}; 
            $weight += $weights{$metric};
        }
    }
    
    # Here J.Arnaud process a sqrt(pow(dev,2)). Seems useless.
    
    my $dev = 0;
    for my $metric ('latency', 'abort_rate', 'throughput') {
        $dev += $deviations{$metric} * $weights{$metric}; 
    }
    $dev /= $weight if ($weight > 0);
    
    $log->debug("* Deviation * " . (Dumper \%deviations));
    $log->debug("==> $dev");
    
    return $dev;
}

sub validateModel {
    my $self = shift;
    my %args = @_;
    
    my $workload = $args{workload};
    my $cluster_conf = $args{cluster_conf};
    
    my %perf = $self->{_model}->calculate(  configuration => {  M => 1,
                                                                AC => [$cluster_conf->{nb_nodes}],
                                                                LC => [$cluster_conf->{mpl}]
                                                                },
                                            workload_class => $workload->{workload_class},
                                            workload_amount => $workload->{workload_amount}
                                            );
    
    # Store model output
    my $rrd = $self->getControllerRRD( cluster => $args{cluster} );
    $rrd->update( time => time(), values => [   $workload->{workload_amount},
                                                $perf{latency} * 1000,
                                                $perf{abort_rate},
                                                $perf{throughput},
                                            ] );
    # Update graph
    $self->genGraph( cluster => $args{cluster} );
}

sub genGraph {
    my $self = shift;
    my %args = @_;
    
    my $rrd = $self->getControllerRRD( cluster => $args{cluster} );
    
    my $cluster_id = $args{cluster}->getAttr('name' => 'cluster_id');
    my $graph_file_prefix = "cluster$cluster_id" . "_controller_server_";
    
    # Quick trick to display in the same graph the modelised metric and the measurement (temporary)
    my %profil_latency_draw = ();
    my %profil_throughput_draw = ();
    my $cluster_public_ips = $args{cluster}->getPublicIps();
    if (defined $cluster_public_ips->[0]) {
        my $profil_rrd_name = "perf_" . $cluster_public_ips->[0]{address} . ".rrd";
        if ( -e "/tmp/$profil_rrd_name") {
            %profil_latency_draw = ( draw => {  type => 'line', color => '0000FF',
                                                dsname  => "latency", legend => "latency(profil)",
                                                file => "/tmp/$profil_rrd_name" } );
            %profil_throughput_draw = ( draw => {   type => 'line', color => '0000FF',
                                                    dsname  => "throughput", legend => "throughput(profil)",
                                                    file => "/tmp/$profil_rrd_name" } );    
        }
    }
        
    # LOAD
    $rrd->graph(
      image          => "/tmp/" . $graph_file_prefix . "load.png",
      vertical_label => 'req',
      start => time() - 3600,
      title => "Load",
      draw    => {
            type    => 'line',
            color   => 'FF0000',
            dsname  => "workload_amount",
            legend  => "load amount (concurrent connections)"
        },
    );
    
    
    # LATENCY
    
    $rrd->graph(
      image          => "/tmp/" . $graph_file_prefix . "latency.png",
      vertical_label => 'ms',
      start => time() - 3600,
      title => "Latency",
      draw  => {
            type    => 'line',
            color   => '00FF00', 
            dsname  => "latency",
            legend  => "latency"
        },
      %profil_latency_draw,
    );
    
    $rrd->graph(
      image          => "/tmp/" . $graph_file_prefix . "abortrate.png",
      vertical_label => 'rate',
      start => time() - 3600,
      title => "Abort rate",
      draw  => {
        type    => 'area',
        color   => '00FF00', 
        dsname  => "abort_rate",
        legend  => "abortRate"},
    );

    $rrd->graph(
      image          => "/tmp/" . $graph_file_prefix . "throughput.png",
      vertical_label => 'req/sec',
      start => time() - 3600,
      title => "Throughput",
      draw  => {
        type    => 'area',
        color   => '00FF00', 
        dsname  => "throughput",
        legend  => "throughput"
      },
      %profil_throughput_draw,
    );
        
}

sub applyConf {
    my $self = shift;
    my %args = @_;

    my $cluster = $args{cluster};
    
    print "############ APPLY conf #####################\n";
    print Dumper $args{conf};
}

sub update {
    my $self = shift;
    my %args = @_;

    my @clusters = Entity::Cluster->getClusters( hash => { cluster_state => {-like => 'up:%'} } );
    for my $cluster (@clusters) {
        my $cluster_name = $cluster->getAttr('name' => 'cluster_name');
        print "CLUSTER: " . $cluster_name . "\n ";
        #if($cluster->getAttr('name' => 'active')) 
        {
            # TODO get controller/orchestration conf for this cluster and init this controller
            # $cluster->getCapPlan(); $cluster->getModel()
            eval {
                $self->manageCluster( cluster => $cluster );
            };
            if ($@) {
                my $error = $@;
                $log->error("While orchestrating cluster '$cluster_name' : $error");
            }
        }    
    }
    
}

sub run {
    my $self = shift;
    my $running = shift;
    
    #$self->{_admin}->addMessage(from => 'Orchestrator', level => 'info', content => "Kanopya Orchestrator started.");
    
    while ( $$running ) {

        my $start_time = time();

        $self->update();

        my $update_duration = time() - $start_time;
        $log->info( "Manage duration : $update_duration seconds" );
        if ( $update_duration > $self->{_time_step} ) {
            $log->warn("update duration > update time step (conf)");
        } else {
            sleep( $self->{_time_step} - $update_duration );
        }

    }
    
    #$self->{_admin}->addMessage(from => 'Orchestrator', level => 'warning', content => "Kanopya Orchestrator stopped");
}

1;
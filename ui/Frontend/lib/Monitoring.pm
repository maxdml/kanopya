=pod
=begin classdoc

TODO

=end classdoc
=cut

package Monitoring;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Data::Dumper;

use Entity::Metric::Combination::NodemetricCombination;
use Entity::Metric::Combination::AggregateCombination;
use DateTime::Format::Strptime;
use Log::Log4perl "get_logger";

my $log = get_logger("");

prefix '/monitoring';


=pod
=begin classdoc

Get the values corresponding to the selected combination for the currently monitored cluster,
return to the monitor.js an 2D array containing the timestamped values for the combination,
plus a start time and a stop time

=end classdoc
=cut


ajax '/serviceprovider/:spid/clustersview' => sub {
    my $cluster_id    = params->{spid} || 0;
    my $combination_id = params->{'id'};
    my $start = params->{'start'};
    my $start_timestamp;
    my $stop = params->{'stop'};
    my $stop_timestamp;
    my $date_parser = DateTime::Format::Strptime->new( pattern => '%m-%d-%Y %H:%M' );

    content_type('application/json');

    #If user didn't fill start and stop time, we set them at (now) to (now - 1 hour)
    if ($start eq '') {
        $start = DateTime->now->set_time_zone('local');
        $start->subtract( days => 1 );
        $start_timestamp = $start->epoch();
        $start = $start->mdy('-') . ' ' .$start->hour_1().':'.$start->minute();
    } else {
        my $start_dt = $date_parser->parse_datetime($start);
        $start_dt->set_time_zone('local');
        $start_timestamp = $start_dt->epoch();
    }

    if ($stop eq '') {
        $stop = DateTime->now->set_time_zone('local');
        $stop_timestamp = $stop->epoch();
        $stop = $stop->mdy('-') . ' ' .$stop->hour_1().':'.$stop->minute();
    } else {
        my $stop_dt = $date_parser->parse_datetime($stop);
        $stop_dt->set_time_zone('local');
        $stop_timestamp = $stop_dt->epoch() ;
    }

    #we get the combination values and return them to the javascript
    my $compute_result = _computeClustermetricCombination (combination_id => $combination_id, start_tms => $start_timestamp, stop_tms => $stop_timestamp);

    if ($compute_result->{'error'}) {
        return to_json {error => $compute_result->{'error'}};
    } else {
        my $histovalues = $compute_result->{'histovalues'};
        return to_json {first_histovalues => $histovalues, min => $start, max => $stop, unit => $compute_result->{'unit'}};
    }
};


=pod
=begin classdoc

Get the values corresponding to the selected nodemetric combination for the currently monitored cluster,
return to the monitor.js an array containing the nodes names for the combination, and another one containing
the values for the nodes, plus the label of the node combination unit

=end classdoc
=cut

get '/serviceprovider/:spid/nodesview/bargraph' => sub {
    my $cluster_id    = params->{spid} || 0;
    my $nodemetric_combination_id = params->{'id'};

    content_type('application/json');

    my $compute_result = _computeNodemetricCombination (cluster_id => $cluster_id, combination_id => $nodemetric_combination_id);

    if ($compute_result->{'error'}) {
        return to_json {error => $compute_result->{'error'}};
    }

    my $nodelist = [ @{$compute_result->{'nodes'}}, @{$compute_result->{'undef'}} ];
    my $values = $compute_result->{'values'};

    # Add an undef value in the list for each node without value
    push @$values, (undef) x (scalar @{$compute_result->{'undef'}});

    return to_json {values => $values, nodelist => $nodelist, unit => $compute_result->{'unit'}};
};

=pod
=begin classdoc

Create a frequency distribution from the values computed to the selected nodemetric combination
return to the monitor.js a scalar containing the quantity of nodes, an array containing
the number of nodes per partitions and another array containing the partitions (interval) of values

=end classdoc
=cut

ajax '/serviceprovider/:spid/nodesview/histogram' => sub {
    my $cluster_id    = params->{spid} || 0;
    my $nodemetric_combination_id = params->{'id'};
    my $part_number = params->{'pn'};

    content_type('application/json');

    #we gather computation result for the nodemetric combination
    my $compute_result = _computeNodemetricCombination(cluster_id => $cluster_id, combination_id => $nodemetric_combination_id);

    if ($compute_result->{'error'}) {
        return to_json {error => $compute_result->{'error'}};
    }

    #we define the number of nodes
    my $nodes_quantity = scalar(@{$compute_result->{'nodes'}}) + scalar(@{$compute_result->{'undef'}});
    my $values_number = scalar(@{$compute_result->{'values'}});
    my $min = 0;
    my @partitions_scopes;
    my @nbof_nodes_per_partition;

    #We catch the case where only one value is returned: statistics::descriptive cannot create a distribution from only one value.
    if ($values_number == 1) {
        #we push into the array the only node value
        push @partitions_scopes, sprintf('%.2f',$min) . ' - ' . sprintf('%.2f',$compute_result->{'values'}[0]);
        push @nbof_nodes_per_partition, 1;

        #then we push into the array the number of undef nodes values
        push @partitions_scopes, 'no value';
        push @nbof_nodes_per_partition, scalar(@{$compute_result->{'undef'}});

        return to_json {partitions => \@partitions_scopes, nbof_nodes_in_partition => \@nbof_nodes_per_partition, nodesquantity => $nodes_quantity};
    } else {
        #we get the combination values and give them to statistics descriptive
        my $all_values = Statistics::Descriptive::Full->new();
        $all_values->add_data($compute_result->{'values'});
        my $partitioned_values = $all_values->frequency_distribution_ref($part_number);

        #we build two arrays, one containing the partition "label", and the other containing the related values
        foreach my $partition_scope ( sort { $a <=> $b } keys %$partitioned_values) {
            push @partitions_scopes, sprintf('%.2f',$min) . ' - ' . sprintf('%.2f',$partition_scope);
            push @nbof_nodes_per_partition, $partitioned_values->{$partition_scope};
            $min = $partition_scope;
        }

        #we add to the lists the undef values
        push @partitions_scopes, 'no value';
        push @nbof_nodes_per_partition, scalar(@{$compute_result->{'undef'}});

        return to_json {partitions => \@partitions_scopes, nbof_nodes_in_partition => \@nbof_nodes_per_partition, nodesquantity => $nodes_quantity};
    }
};


=pod
=begin classdoc

Compute the clustermetric combination for the cluster and return a reference
to an array containing the corresponding values and related times
@return Array ref histovalues

=end classdoc
=cut

sub _computeClustermetricCombination () {
    my %args = @_;
    my $combination_id = $args{combination_id};
    my $start_timestamp = $args{start_tms};
    my $stop_timestamp = $args{stop_tms};
    my $combination = Entity::Metric::Combination::AggregateCombination->get('id' => $combination_id);
    my $error;
    my %aggregate_combination;
    my @histovalues;
    my %rep;

    eval {
        %aggregate_combination = $combination->evaluateTimeSerie(start_time => $start_timestamp, stop_time => $stop_timestamp);
        #$log->info('values returned by compute values: '.Dumper \%aggregate_combination);
    };
    if ($@) {
        $error="$@";
        $log->error($error);
        $rep{'error'} = $error;
        return \%rep;
    } elsif (!%aggregate_combination || scalar(keys %aggregate_combination) == 0) {
        $error='no values could be computed for this combination';
        $log->error($error);
        $rep{'error'} = $error;
        return \%rep;
    } else {
        my $undef_count = 0;
        my $res_number = scalar(keys %aggregate_combination);
        while (my ($date, $value) = each %aggregate_combination) {
            my $dt = DateTime->from_epoch(epoch => $date)->set_time_zone('local');
            my $date_string = $dt->strftime('%m-%d-%Y %H:%M');
            push @histovalues, [$date_string,$value];
            # we reference the undef values in order to throw an error if all values are undef
            if (!defined $value) {
                $undef_count++;
            }
        }
        if ($res_number == $undef_count) {
            $error = 'all values retrieved for the selected time windows were undefined';
            $log->error($error);
            $rep{'error'} = $error;
            return \%rep;
        }

        $rep{'histovalues'} = \@histovalues;
        $rep{'unit'}        = $combination->getUnit();
        return \%rep;
    }
}


=pod
=begin classdoc

Compute the nodemetric combination for each node of the cluster and return a reference
to a hash containing references to 2 arrays, the first containing the node list,
the second containing the corresponding values

@return hashref

=end classdoc
=cut

sub _computeNodemetricCombination {
    my %args = @_;

    my $comb = Entity::Metric::Combination::NodemetricCombination->get(id => $args{combination_id});

    my %rep;
    my $error;
    my $evaluation = {};

    eval {

        my $cluster = Entity::ServiceProvider->get(id => $args{cluster_id});

        for my $node ($cluster->nodes) {
            my $nodename = $node->node_hostname;
            $nodename =~ s/\..*//;
            $evaluation->{$nodename} = $comb->evaluate(node => $node);
        }

        $log->debug('[Cluster id '.$args{cluster_id}.']: Requested combination value for each node: '.Dumper $evaluation);
    };
    if ($@) {
        $error="$@";
        $log->error($error);
        $rep{'error'} = $error;
    # we catch the fact that there is no value available for the selected nodemetric
    }
    elsif (scalar(keys %{$evaluation}) == 0) {
        $error='No indicator values returned by monitored nodes';
        $log->error($error);
        $rep{'error'} = $error;
    }
    else {
        #we create an array containing the values, to be sorted
        my @nodes_values_to_sort;
        my @nodes_undef;
        while (my ($node, $metric) = each %{$evaluation}) {
            if (defined $metric) {
            push @nodes_values_to_sort, { node => $node, value => $metric };
            } else {
                push @nodes_undef, $node;
            }
        }
        if (scalar(@nodes_values_to_sort) == 0) {
            $error = "no value could be retrieved for this metric";
            $log->error($error);
            $rep{'error'} = $error;
            return \%rep;
        }
        #we now sort this array
        my @sorted_nodes_values =  sort { $b->{value} <=> $a->{value} } @nodes_values_to_sort;
        # we split the array into 2 distincts one, that will be returned to the monitor.js
        my @nodes = map { $_->{node} } @sorted_nodes_values;
        my @values = map { $_->{value} } @sorted_nodes_values;

        $rep{'nodes'}   = \@nodes;
        $rep{'values'}  = \@values;
        $rep{'undef'}   = \@nodes_undef;
        $rep{'unit'}    = $comb->getUnit();
    }
    return \%rep;
}

1;

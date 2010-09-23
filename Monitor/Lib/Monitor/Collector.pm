package Monitor::Collector;

use strict;
use warnings;
use threads;
#use threads::shared;
use Net::Ping;

use Data::Dumper;

use base "Monitor";

# logger
use Log::Log4perl "get_logger";
#Log::Log4perl->init('/workspace/mcs/Monitor/Conf/log.conf');
my $log = get_logger("collector");

# Constructor

sub new {
    my $class = shift;
    my %args = @_;
	
	my $self = $class->SUPER::new( %args );
    return $self;
}


=head2 _manageHostState
	
	Class : Private
	
	Desc : update the state of host in db if necessary (depending if this host is reachable or not and on the state time)
	
	Args :
		host: ip of the host
		reachable: 0 (false) or 1 (true): tell if we have succeeded in retrieving information from this host (i.e reachable or not)

=cut

sub _manageHostState {
	my $self = shift;
	my %args = @_;
	
	my $starting_max_time = $self->{_node_states}{starting_max_time};
		
	my $adm = $self->{_admin_wrap};
	my $reachable = $args{reachable};
	my $host_ip = $args{host};

	eval {
		
		#TODO 	On peut éviter de refaire une requête si on conserve l'état lors de la recupération des hosts au début
		#		Mais risque de ne plus être à jour..
		
		# Retrieve motherboard
		my @mb_res = $adm->getEntities( type => "Motherboard", hash => { motherboard_internal_ip => $host_ip } );	
		my $mb = shift @mb_res;

		die "motherboard '$host_ip' no more in DB" if (not defined $mb);

		# Retrieve mb state and state time
		my ($state, $state_time) = $self->_mbState( state_info => $mb->getAttr( name => "motherboard_state" ) );
		my $new_state = $state;
		
		# Manage new state
		if ( $reachable ) {					# if reachable, node is now 'up', don't care of what was the last state
			$new_state = "up";
		} elsif ( $state eq "up" ) {		# if unreachable and last state was 'up', node is considered 'broken'
				$new_state = 'broken';
		} else {							# else we check if node is not 'starting' for too long, if it is, node is 'broken'
			my $diff_time = 0;
			if ($state_time) {
				$diff_time = time() - $state_time;	
			}
			if ( ( $state eq "starting" ) && ( $diff_time > $starting_max_time ) ) {
				$new_state = 'broken';
				my $mess = "'$host_ip' is in state '$state' for $diff_time seconds, it's too long (see monitor conf), considered as broken."; 
				print $mess . "\n";
				$adm->addMessage( type => "warning", content => $mess );
			}
		}
		
		# Update state in DB if changed
		if ( $state ne $new_state ) {
			print "===========> ($host_ip) last state : $state  =>  new state : $new_state \n";
			$mb->setAttr( name => "motherboard_state", value => $new_state );
			$mb->save();
			$adm->addMessage( type => "statechanged", content => "[$host_ip] State changed : $state => $new_state" );
		}
	};
	if ($@) {
		my $error = $@;
		print "===> $error";
		$log->error( $error );
	}
}

=head2 _manageStoppingHost
	
	Class : Private
	
	Desc : Try to reach a stopping host and update its state depending on the result (and stopping time)
	
	Args :
		host: Entity::Motherboard : the stopping host to manage

=cut

sub _manageStoppingHost {
	my $self = shift;
	my %args = @_;
	
	my $adm = $self->{_admin_wrap};
	my $host = $args{host};
	
	my $stopping_max_time = $self->{_node_states}{stopping_max_time};
	
	eval {
		my ($state, $state_time) = $self->_mbState( state_info => $host->getAttr( name => "motherboard_state" ) );
		my $new_state = $state;
		
		my $host_ip = $host->getAttr( name => 'motherboard_internal_ip' );
		# we check if host is stopped (unpingable)
		my $p = Net::Ping->new();
		my $pingable = $p->ping($host_ip);
		$p->close();
		if ( not $pingable ) {
			$new_state = 'down';
		}
		
		# compute diff time between state time and now
		my $diff_time = 0;
		if ($state_time) {
			$diff_time = time() - $state_time;	
		}
		
		if ( $diff_time > $stopping_max_time ) {
			$new_state = 'broken';
			my $mess = "'$host_ip' is in state '$state' for $diff_time seconds, it's too long (see monitor conf), considered as broken."; 
			print $mess . "\n";
			$adm->addMessage( type => "warning", content => $mess );
		} 
		
		# Update state in DB if changed
		if ( $state ne $new_state ) {
			print "===========> ($host_ip) last state : $state  =>  new state : $new_state \n";
			$host->setAttr( name => "motherboard_state", value => $new_state );
			$host->save();
			$adm->addMessage( type => "statechanged", content => "[$host_ip] State changed : $state => $new_state" );
		}
	};
	if ($@) {
		my $error = $@;
		print "===> $error";
		$log->error( $error );
	}
}

=head2 updateHostData
	
	Class : Public
	
	Desc : For a host, retrieve value of all monitored data (snmp var defined in conf) and store them in corresponding rrd
	
	Args :
		host : the host name

=cut

sub updateHostData {
	my $self = shift;
	my %args = @_;

	my $host = $args{host};
	
	my %all_values = ();
	#my $session = $self->createSNMPSession( host => $host );
	my $host_reachable = 1;
	my $error_happened = 0;	
	eval {
		#For each set of var defined in conf file
		foreach my $set ( @{ $self->{_monitored_data} } ) {

			###################################################
			# Build the required var map: ( var_name => oid ) #
			###################################################
			my %var_map = map { $_->{label} => $_->{oid} } @{ General::getAsArrayRef( data => $set, tag => 'ds') };
			
			#################################
			# Get the specific DataProvider #
			#################################
			# TODO vérifier que c'est pas trop moche (possibilité plusieurs fois le même require,...)
			my $provider_class = $set->{'data_provider'} || "SnmpProvider";
			require "DataProvider/$provider_class.pm";
			my $data_provider = $provider_class->new( host => $host );
			
			################################################################################
			# Retrieve the map ref { var_name => value } corresponding to required var_map #
			################################################################################
			my ($time, $update_values);
			eval {
				($time, $update_values) = $data_provider->retrieveData( var_map => \%var_map );
			};
			if ($@) {
				my $error = $@;
				#print  "[$host] Error collecting data set  ===> $error";
				$log->warn( "[", threads->tid(), "][$host] Collecting data set '$set->{label}' => $provider_class : $error" );
				#TODO find a better way to detect unreachable host (grep error string is not very safe)
				if ( "$error" =~ "No response" ) {
					$log->info( "Unreachable host '$host' => we stop collecting data.");
					$host_reachable = 0;
					last; # we stop collecting data sets
				} else {
					$error_happened = 1;
				}
				next; # continue collecting the other data sets
			}
			
			# DEBUG print values
			print "[", threads->tid(), "][$host] $time : ", join( " | ", map { "$_: $update_values->{$_}" } keys %$update_values ), "\n";
	
			$all_values{ $set->{label} } = $update_values;
	
			#############################################
			# Store new values in the corresponding RRD #
			#############################################
			my $rrd_name = $self->rrdName( set_name => $set->{label}, host_name => $host );
			$self->updateRRD( rrd_name => $rrd_name, ds_type => $set->{ds_type}, time => $time, data => $update_values );
		}
		# Update host state
		$self->_manageHostState( host => $host, reachable => $host_reachable );
	};
	if ($@) {
		my $error = $@;
		print "===> $error";
		$log->error( $error );
		$error_happened = 1;
		#TODO gérer $host_state dans ce cas (error)
		
	}
	
	print "[$host] => some errors happened collecting data\n" if ($error_happened);
	
	return \%all_values;
}


# TEST
sub thread_test {
	my $self = shift;
	my %args = @_;
		
	
	my $tid = threads->tid();
	my $admin = $self->{_admin_wrap};
	print "[$tid] ==> ADMIN: ", $admin, "    res : ", %{$admin->{_ref}} , "\n";
	
	#while (1) {
	for (1..10) {
		$self->{_num} = $self->{_num} + 1; 
		print "($tid) : ", $self->{_num}, "\n";
		
		
		
		sleep(2 - $tid);
	}
	print "($tid) : bye\n";
	return $tid;
}

# TEST
sub update_test {
	my $self = shift;
	
	$self->{_num} = 2;
	
	my $admin = $self->{_admin_wrap};
	print "==> ADMIN: ", $admin, "    res : ", %{$admin->{_ref}}  , "\n";
	
	{#for (1..2) { 
		print "create thread\n";
		my $thr = threads->create('thread_test', $self);
		my $thr2 = threads->create('thread_test', $self);
		my $tid = $thr->join();
		print "============> $tid\n";
		$tid = $thr2->join();
		print "============> $tid\n";
	}
	
	while (threads->list(threads::running) > 0) {
		my $count =threads->list(threads::running);
		print "count: $count\n";
		sleep(1);
	}
	
	print "THREADS: ", threads->list(threads::running), "\n";
	#while (1) {
	#	sleep(60);
	#}
}

=head2 udpate
	
	Class : Public
	
	Desc : Create a thread to update data for every monitored host
	
=cut

sub update {
	my $self = shift;
	
	my $start_time = time();
	
	print "#### UPDATE start : $start_time\n";
	
	eval {
		#my @hosts = $self->retrieveHostsIp();
		my %hosts_by_cluster = $self->retrieveHostsByCluster();
		my @all_hosts_info = map { values %$_ } values %hosts_by_cluster;
		
		#############################
		# Update data for each host #
		#############################
		my %threads = ();
		for my $host_info (@all_hosts_info) {
			# We create a thread for each host to don't block update if a host is unreachable
			#TODO vérifier les perfs et l'utilisation memoire (duplication des données pour chaque thread), comparer avec fork
			my $thr = threads->create('updateHostData', $self, host => $host_info->{ip});
			$threads{$host_info->{ip}} = $thr;
			#push @threads, $thr;
		}
		
		#########################
		# Manage stopping hosts	#	
		#########################
		my $adm = $self->{_admin_wrap};
		my @stoppingHosts = $adm->getEntities( type => "Motherboard", hash => { motherboard_state => { like => "stopping%" } } );
		foreach my $host (@stoppingHosts) {
			my $thr = threads->create('_manageStoppingHost', $self, host => $host);
			#push @threads, $thr;
			my $host_ip = $host->getAttr( name => "motherboard_internal_ip" );
			$threads{$host_ip} = $thr;
		}
		
		############################
		# Wait end of all threads  #
		############################
		my %hosts_values = ();
		while ( my ($host_ip, $thr) = each %threads ) {
		#foreach my $thr (@threads) {
			my $ret = $thr->join();
			$hosts_values{ $host_ip } = $ret;
			#$thr->join();
		}
		
		################################
		# update hosts state if needed #
		################################
	#	my $adm = $self->{_admin};
	#	for my $host_info (@all_hosts_info) {
	#		my $host_state = $hosts_state{ $host_info->{ip} };
	#		if ( $host_info->{state} ne $host_state ) {
	#				my @mb_res = $adm->getEntities( type => "Motherboard", hash => { motherboard_internal_ip => $host_info->{ip} } );
	#				my $mb = shift @mb_res;
	#				if ( defined $mb ) {
	#					$mb->setAttr( name => "motherboard_state", value => $host_state );
	#					$mb->save();
	#				} else {
	#					print "===> Error: can't find motherboard in DB : ip = $host_info->{ip}\n";
	#				}
	#		}
	#	}
		
		
		######################################################
		# update clusters base (nodes count and mean values) #
		######################################################
		#TODO ici on retrieve une nouvelle fois alors qu'on le fait au début de la fonction
		# (mais entre temps l'état des noeuds à eventuellement été modifié). Il y a surement mieux à faire.
		%hosts_by_cluster = $self->retrieveHostsByCluster();
		while ( my ($cluster_name, $cluster_info) = each %hosts_by_cluster ) {
			
			############################## Update cluster rrd #########################################
			my @nodes_ip = map { $_->{ip} } values %$cluster_info;
			
			my %sets;
			foreach my $host_ip (@nodes_ip) {
				my @sets_name = keys %{ $hosts_values{ $host_ip } };
				foreach my $set_name ( @sets_name ) {	
					push @{$sets{$set_name}}, $hosts_values{ $host_ip }{$set_name};
				}
			}
			
			my %sets_aggreg;
			while ( my ($set_name, $sets_list) = each %sets ) {
				my %aggreg = $self->aggregate( hash_list => $sets_list, f => 'mean' );
				$sets_aggreg{ $set_name } = \%aggreg;
				#my $rrd_name = "monitor_$cluster_name" . "_$set_name";
				my $rrd_name = $self->rrdName( set_name => $set_name, host_name => $cluster_name );

				$self->updateRRD( rrd_name => $rrd_name, ds_type => 'GAUGE', time => $start_time, data => \%aggreg);
			} 
			
			
			################################# update cluster node count ##########################################
			
			
			my @nodes_state = map { $_->{state} } values %$cluster_info;
			
			# print nodes state
			my %infos = map { $_->{ip} => $_->{state} } values %$cluster_info;
			print "### $cluster_name ###\n", Dumper \%infos;
			
			# RRD for node count
			my $rrd_file = "$self->{_rrd_base_dir}/nodes_$cluster_name.rrd";
			my $rrd = RRDTool::OO->new( file =>  $rrd_file );
			if ( not -e $rrd_file ) {	
				print "Info: create nodes rrd for '$cluster_name'\n";
				$rrd->create( 	'step' => $self->{_time_step}, 'archive' => { rows => 500 },
								'data_source' => { 	name => 'up', type => 'GAUGE' },
								'data_source' => { 	name => 'starting', type => 'GAUGE' },
								'data_source' => { 	name => 'stopping', type => 'GAUGE' },
								'data_source' => { 	name => 'broken', type => 'GAUGE' },
							);
				
			}
			
			my $up_count = scalar grep { $_ =~ 'up' } @nodes_state;
			my $starting_count = scalar grep { $_ =~ 'starting' } @nodes_state;
			my $stopping_count = scalar grep { $_ =~ 'stopping' } @nodes_state;
			my $broken_count = scalar grep { $_ =~ 'broken' } @nodes_state;
	
			$rrd->update( time => $start_time, values => { 	'up' => $up_count, 'starting' => $starting_count,
														'stopping' => $stopping_count, 'broken' => $broken_count } );
		}
	};
	if ($@) {
		my $error = $@;
		print "update() ===> $error";
		$log->error( $error );
	}
	
	my $duration = time() - $start_time;
	print "#### Update duration = $duration ###\n";	
	if ( $duration > $self->{_time_step} ) {
		print "=> Warn: update duration > collector time step (conf)\n";
	}
}


=head2 run
	
	Class : Public
	
	Desc : Launch an update every time_step (configuration)
	
=cut

#TODO with threading we have a "Scalars leaked: 1" printed, harmless, don't worry 
sub run {
	my $self = shift;
	
	while ( 1 ) {
		my $thr = threads->create('update', $self);
		$thr->detach();
		#$self->update();
		
		$self->{_t} += 0.1;
		sleep( $self->{_time_step} );
	}
}

1;

__END__

=head1 AUTHOR

Copyright (c) 2010 by Hedera Technology Dev Team (dev@hederatech.com). All rights reserved.
This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
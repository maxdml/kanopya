package Mcsui::Clusters;
use Data::Dumper;
use base 'CGI::Application';
use Log::Log4perl "get_logger";
use CGI::Application::Plugin::AutoRunmode;
use CGI::Application::Plugin::Redirect;
use strict;
use warnings;


my $log = get_logger("administrator");
my $closewindow = "<script type=\"text/javascript\">window.opener.location.reload();window.close();</script>";

sub setup {
	my $self = shift;
	$self->{'admin'} = Administrator->new(login => 'admin', password => 'admin');
}

# clusters listing page

sub view_clusters : StartRunmode {
    my $self = shift;
    my $tmpl =  $self->load_tmpl('Clusters/view_clusters.tmpl');
    # header / menu variables
    $tmpl->param('titlepage' => "Clusters - Clusters");
	$tmpl->param('mClusters' => 1);
	$tmpl->param('submClusters' => 1);
    
    my @eclusters = $self->{'admin'}->getEntities(type => 'Cluster', hash => {});
    my $clusters = [];
    	
    foreach my $n (@eclusters){
    	my $tmp = {};
    	$tmp->{link_activity} = 0;
    	
		$tmp->{cluster_id} = $n->getAttr(name => 'cluster_id');
		$tmp->{cluster_name} = $n->getAttr(name => 'cluster_name');
		my $minnode = $n->getAttr(name => 'cluster_min_node');
		my $maxnode = $n->getAttr(name => 'cluster_max_node');
		if($minnode == $maxnode) {
			$tmp->{type} = 'Static cluster';
			$tmp->{nbnodes} = "$minnode node";
			if($minnode > 1) { $tmp->{nbnodes} .= "s"; } 
		} else {
			$tmp->{type} = 'Dynamic cluster';
			$tmp->{nbnodes} = "$minnode to $maxnode nodes";
		}
		
		if($n->getAttr('name' => 'active')) {
			$tmp->{active} = 1;
			my $nodes = $n->getMotherboards(administrator => $self->{'admin'});
			my $nbnodesup = scalar(keys %$nodes); 
			if($nbnodesup > 0) {
				$tmp->{nbnodesup} = $nbnodesup;
				$tmp->{link_activity} = 1;
			} 
		} else { 
			$tmp->{active} = 0; 
		}
		$tmp->{cluster_desc} = $n->getAttr(name => 'cluster_desc');	
		push (@$clusters, $tmp);	
    }	
   
	$tmpl->param('clusters_list' => $clusters);
	  
    return $tmpl->output();
}

# cluster creation popup window
sub form_addcluster : Runmode {
	my $self = shift;
	my $errors = shift;
	my $tmpl = $self->load_tmpl('Clusters/form_addcluster.tmpl');
	
	my @ekernels = $self->{'admin'}->getEntities(type => 'Kernel', hash => {});
	my @esystemimages = $self->{'admin'}->getEntities(type => 'Systemimage', hash => {});
	my @emotherboards = $self->{'admin'}->getEntities(type => 'Motherboard', hash => {});
	
	my $count = scalar @emotherboards;
	my $c =[];
	for (my $i=1; $i<=$count; $i++) {
		my $tmp->{nodes}=$i;
		push(@$c, $tmp);
	}
	my $kmodels = [];
	foreach my $k (@ekernels) {
		my $tmp = { 
			kernel_id => $k->getAttr( name => 'kernel_id'),
			kernel_name => $k->getAttr(name => 'kernel_version')
		};
		push (@$kmodels, $tmp);	
	} 
	my $smodels = [];
	foreach my $s (@esystemimages){
		my $tmp = { 
			systemimage_id => $s->getAttr (name => 'systemimage_id'),
			systemimage_name => $s->getAttr(name => 'systemimage_name')
		};
		push (@$smodels, $tmp);
	}
	
	$tmpl->param('nodescount' => $c);
	$tmpl->param('kernels_list' => $kmodels);
	$tmpl->param('systemimages_list' => $smodels);
	$tmpl->param($errors) if $errors;
	
	return $tmpl->output();
}

# fields verification function to used with form_addcluster

sub _addcluster_profile {
	return {
    	required => ['name', 'systemimage_id', 'kernel_id', 'min_node', 'max_node', 'priority'],
        msgs => {
        	any_errors => 'some_errors',
            prefix => 'err_'
        },
	};
}

# form_addcluster processing

sub process_addcluster : Runmode {
        my $self = shift;
        use CGI::Application::Plugin::ValidateRM (qw/check_rm/);
        my ($results, $err_page) = $self->check_rm('form_addcluster', '_addcluster_profile');
        return $err_page if $err_page;

        my $query = $self->query();
        eval {
            my $params = {
				cluster_name => $query->param('name'),
				cluster_desc => $query->param('desc'),
				cluster_min_node => $query->param('min_node'),
				cluster_max_node => $query->param('max_node'),
				cluster_priority => $query->param('priority'),
				systemimage_id => $query->param('systemimage_id')
			};
			if($query->param('kernel_id') ne '0') { $params->{kernel_id} = $query->param('kernel_id'); }
			$self->{'admin'}->newOp(type =>"AddCluster", priority => '100', params => $params);
		};
        if($@) {
                my $error = $@;
                $self->{'admin'}->addMessage(type => 'error', content => $error);
	} else { 
		$self->{'admin'}->addMessage(type => 'newop', content => 'new cluster operation adding to execution queue'); 
	}
    	
    return $closewindow;
}

# cluster details page

sub view_clusterdetails : Runmode {
	my $self = shift;
	my $errors = shift;
	my $tmpl = $self->load_tmpl('Clusters/view_clusterdetails.tmpl');
	 # header / menu variables
	$tmpl->param('titlepage' => "Cluster's overview");
	$tmpl->param('mClusters' => 1);
	$tmpl->param('submClusters' => 1);
	
	# actions visibility
	$tmpl->param('link_delete' => 0);
	$tmpl->param('link_activate' => 0);
	$tmpl->param('link_start' => 0);
	$tmpl->param('link_addnode' => 0);
	
	my $query = $self->query();
	my $ecluster = $self->{'admin'}->getEntity(type => 'Cluster', id => $query->param('cluster_id'));
		
	$tmpl->param('cluster_id' => $ecluster->getAttr(name => 'cluster_id'));
	$tmpl->param('cluster_name' => $ecluster->getAttr(name => 'cluster_name'));
	$tmpl->param('cluster_desc' => $ecluster->getAttr(name => 'cluster_desc'));
	$tmpl->param('cluster_priority' => $ecluster->getAttr(name => 'cluster_priority'));
	
	my $minnode = $ecluster->getAttr(name => 'cluster_min_node');
	my $maxnode = $ecluster->getAttr(name => 'cluster_max_node');
	$tmpl->param('cluster_min_node' => $minnode);
	$tmpl->param('cluster_max_node' => $maxnode);
	if($minnode == $maxnode) {
		$tmpl->param('type' => 'Static cluster');
	} else {
		$tmpl->param('type' => 'Dynamic cluster');
	}
	
	my $systemimage_id = $ecluster->getAttr(name => 'systemimage_id');
	if($systemimage_id) {
		my $esystemimage = $self->{'admin'}->getEntity(type =>'Systemimage', id => $systemimage_id);
		$tmpl->param('systemimage_name' =>  $esystemimage->getAttr(name => 'systemimage_name'));
	} else {
		$tmpl->param('systemimage_name' => "no system image");
	}	
	
	my $kernel_id = $ecluster->getAttr(name =>'kernel_id');
	if($kernel_id) {
		my $ekernel = $self->{'admin'}->getEntity(type =>'Kernel', id => $kernel_id);
		$tmpl->param('kernel' => $ekernel->getAttr(name => 'kernel_version'));
	} else {
		$tmpl->param('kernel' => 'no specific kernel');
	}
	
	my $publicips = $ecluster->getPublicIps();
	$tmpl->param('publicip_list' => $publicips);
	$tmpl->param('nbpublicips' => scalar(@$publicips)+1);
	
	# state info
	
	my $motherboards = $ecluster->getMotherboards(administrator => $self->{'admin'});
	my $nbnodesup = scalar(keys(%$motherboards)); 
	my $nodes = [];
	
	if($ecluster->getAttr('name' => 'active')) {
		$tmpl->param('active' => 1);
		$tmpl->param('link_activate' => 0);
		
		if($nbnodesup > 0) {
			$tmpl->param('nbnodesup' => $nbnodesup+1);	
			if($minnode != $maxnode and $nbnodesup < $maxnode) { 
				$tmpl->param('link_addnode' => 1);
			}
		} else {
			$tmpl->param('link_start' => 1);	
		}
		
	} else { 
		$tmpl->param('active' => 0);
		$tmpl->param('link_activate' => 1);
		$tmpl->param('link_delete' => 1);
	}
	
	# components list
	
	my $components = $ecluster->getComponents(administrator => $self->{'admin'}, category => 'all');
	my $comps = [];
			
	while( my ($instance_id, $comp) = each %$components) {
		my $comphash = {};
		my $compAtt = $comp->getComponentAttr();
		$comphash->{component_instance_id} = $instance_id;
		$comphash->{component_name} = $compAtt->{component_name};
		$comphash->{component_version} = $compAtt->{component_version};
		$comphash->{component_category} = $compAtt->{component_category};
		push (@$comps, $comphash);
	}
	$tmpl->param('nbcomponents' => scalar(@$comps)+1);
	$tmpl->param('components_list' => $comps);
	
	# nodes list
	if($nbnodesup) {
		my $id =  $ecluster->getMasterNodeId();
		my $masternode = $motherboards->{ $id };
		my $tmp = {
			motherboard_hostname => $masternode->getAttr(name => 'motherboard_hostname'),
			motherboard_internal_ip => $masternode->getAttr(name => 'motherboard_internal_ip'),
			link_remove => 0
		};
		delete $motherboards->{ $id };
		push @$nodes, $tmp;
		
		foreach my $n (values %$motherboards) {
			$tmp = {};
			$tmp->{motherboard_hostname} = $n->getAttr(name => 'motherboard_hostname'); 	
			$tmp->{motherboard_internal_ip} = $n->getAttr(name => 'motherboard_internal_ip');
			push @$nodes, $tmp;
		}
	}
	
	$tmpl->param('nodes_list' => $nodes);
	return $tmpl->output();
}

# TODO cluster edition popup window

sub form_editcluster : Runmode {
	return "TODO";
}

# component addition popup window

sub form_addcomponenttocluster : Runmode {
	my $self = shift;
	my $tmpl = $self->load_tmpl('Clusters/form_addcomponenttocluster.tmpl');
	my $query = $self->query();
	my $cluster_id = $query->param('cluster_id');
	my $ecluster = $self->{'admin'}->getEntity(type => 'Cluster', id => $cluster_id);
	my $esystemimage = $self->{'admin'}->getEntity(type =>'Systemimage', id => $ecluster->getAttr(name => 'systemimage_id'));
	my $systemimage_components = $esystemimage->getInstalledComponents();
	my $cluster_components = $ecluster->getComponents(administrator => $self->{'admin'}, category => 'all');
	my $components = [];
	#$log->debug(Dumper $systemimage_components);
	 
	foreach my $c  (@$systemimage_components) {	
		my $found = 0;
		while(my ($instance_id, $component) = each %$cluster_components) {
			my $attrs = $component->getComponentAttr();
			if($attrs->{component_id} eq $c->{component_id}) { $found = 1; }
		}
		if(not $found) { push @$components, $c; };
	} 
	$tmpl->param('cluster_id' => $cluster_id);
	$tmpl->param('cluster_name' => $ecluster->getAttr(name => 'cluster_name'));
	$tmpl->param('components_list' => $components);
	
	return $tmpl->output();
}


# actions processing

sub process_activatecluster : Runmode {
    my $self = shift;
        
    my $query = $self->query();
    eval {
    $self->{'admin'}->newOp(type => "ActivateCluster", priority => '100', params => { 
		cluster_id => $query->param('cluster_id'), 
		});
    };
    if($@) { 
		my $error = $@;
		$self->{'admin'}->addMessage(type => 'error', content => $error); 
	} else { $self->{'admin'}->addMessage(type => 'newop', content => 'activate cluster operation adding to execution queue'); }
    $self->redirect('/cgi/mcsui.cgi/clusters/view_clusters');
}

sub process_deactivatecluster : Runmode {
    my $self = shift;
        
    my $query = $self->query();
    eval {
    $self->{'admin'}->newOp(type => "DeactivateCluster", priority => '100', params => { 
		cluster_id => $query->param('cluster_id'), 
		});
    };
    if($@) { 
		my $error = $@;
		$self->{'admin'}->addMessage(type => 'error', content => $error); 
	} else { $self->{'admin'}->addMessage(type => 'newop', content => 'deactivate cluster operation adding to execution queue'); }
    $self->redirect('/cgi/mcsui.cgi/clusters/view_clusters');
}

sub process_removecluster : Runmode {
    my $self = shift;
    my $query = $self->query();
    eval {
    $self->{'admin'}->newOp(type => "RemoveCluster", priority => '100', params => { 
		cluster_id => $query->param('cluster_id'), 
		});
    };
    if($@) { 
		my $error = $@;
		$self->{'admin'}->addMessage(type => 'error', content => $error); 
	} else { $self->{'admin'}->addMessage(type => 'newop', content => 'remove cluster operation adding to execution queue'); }
    $self->redirect('/cgi/mcsui.cgi/cluster/view_clusters');
}

sub form_setpubliciptocluster : Runmode {
	my $self = shift;
	my $errors = shift;
	my $tmpl =$self->load_tmpl('Clusters/form_setpubliciptocluster.tmpl');
	my $output = '';
	my $query = $self->query();	
	my $freepublicips = $self->{admin}->getFreePublicIPs();
	
	$tmpl->param('CLUSTER_ID' => $query->param('cluster_id'));
	$tmpl->param('FREEPUBLICIPS' => $freepublicips);
	
	$output .= $tmpl->output();
	return $output;
}

sub process_setpubliciptocluster : Runmode {
	my $self = shift;
    my $query = $self->query();
    eval {
    	$self->{admin}->setClusterPublicIP(
    		publicip_id => $query->param('publicip_id'),
    		cluster_id => $query->param('cluster_id'),
    	);
    };
    if($@) { 
		my $error = $@;
		$self->{'admin'}->addMessage(type => 'error', content => $error); 
	} else { $self->{'admin'}->addMessage(type => 'success', content => 'new public ip added to cluster.'); }
    return $closewindow;
}

sub process_startcluster : Runmode {
	my $self = shift;
	my $query = $self->query();
    eval {
	    $self->{'admin'}->newOp(type => "StartCluster", priority => '100', 
	    	params => { cluster_id => $query->param('cluster_id') } 
		);
    };
    if($@) { 
		my $error = $@;
		$self->{'admin'}->addMessage(type => 'error', content => $error); 
	} else { $self->{'admin'}->addMessage(type => 'newop', content => 'start cluster operation adding to execution queue'); }
    $self->redirect('/cgi/mcsui.cgi/clusters/view_clusters');
}

sub process_stopcluster : Runmode {
	my $self = shift;
	my $query = $self->query();
    eval {
	    $self->{'admin'}->newOp(type => "StopCluster", priority => '100', 
	    	params => { cluster_id => $query->param('cluster_id') } 
		);
    };
    if($@) { 
		my $error = $@;
		$self->{'admin'}->addMessage(type => 'error', content => $error); 
	} else { $self->{'admin'}->addMessage(type => 'newop', content => 'stop cluster operation adding to execution queue'); }
    $self->redirect('/cgi/mcsui.cgi/clusters/view_clusters');
}

sub process_removenode : Runmode {
	my $self = shift;
	my $query = $self->query();
    eval {
	    $self->{'admin'}->newOp(type => "StopNode", priority => '100', 
	    	params => { cluster_id => $query->param('cluster_id'), motherboard_id => $query->param('motherboard_id') } 
		);
    };
    if($@) { 
		my $error = $@;
		$self->{'admin'}->addMessage(type => 'error', content => $error); 
	} else { $self->{'admin'}->addMessage(type => 'newop', content => 'stop node operation adding to execution queue'); }
    $self->redirect('/cgi/mcsui.cgi/clusters/view_clusterdetails?cluster_id='.$query->param('cluster_id'));
}

sub process_addnode : Runmode {
	my $self = shift;
	my $query = $self->query();
	        
    eval {
	    my @free_motherboards = $self->{admin}->getEntities(type => 'Motherboard', hash => { active => 1, motherboard_state => 'down'});
	    if(not scalar @free_motherboards) {
	    	my $errmsg = 'no motherboard is available ; can\'t add a new node to this cluster';
	    	throw Mcs::Exception::Internal(error => $errmsg);
	    }
	    my $motherboard = pop @free_motherboards;
	    $self->{'admin'}->newOp(type => "AddMotherboardInCluster", priority => '100', 
	    	params => { cluster_id => $query->param('cluster_id'), motherboard_id => $motherboard->getAttr(name => 'motherboard_id') } 
		);
    };
    if($@) { 
		my $error = $@;
		$self->{'admin'}->addMessage(type => 'error', content => $error); 
	} else { $self->{'admin'}->addMessage(type => 'newop', content => 'AddMotherboardInCluster operation adding to execution queue'); }
    $self->redirect('/cgi/mcsui.cgi/clusters/view_clusterdetails?cluster_id='.$query->param('cluster_id'));
}

sub process_addcomponent : Runmode {
	my $self = shift;
	my $query = $self->query();
	eval {
	    my $ecluster = $self->{'admin'}->getEntity(type => 'Cluster', id => $query->param('cluster_id'));
	    $ecluster->addComponent(administrator => $self->{'admin'}, component_id => $query->param('component_id'));
	    
    };
    if($@) { 
		my $error = $@;
		$self->{'admin'}->addMessage(type => 'error', content => $error); 
	} else { $self->{'admin'}->addMessage(type => 'success', content => 'Component added sucessfully'); }
   	return $closewindow;

}

1;

#!/usr/bin/perl -w
use Test::More 'no_plan';
use Test::Exception;
use Test::Pod;
use Kanopya::Exceptions;


use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init({level=>'DEBUG', file=>'/tmp/test.log', layout=>'%F %L %p %m%n'});

use_ok ('Administrator');
use_ok ('Executor');
use_ok('Entity::Tier');
use Data::Dumper;
my $test_instantiation = "Instantiation test";

eval {
    Administrator::authenticate( login =>'admin', password => 'K4n0pY4' );
    my @args = ();
    note ("Execution begin");
    my $executor = new_ok("Executor", \@args, "Instantiate an executor");

    my $tier = Entity::Tier->new( tier_name => "TierTest",
				  tier_rank => 3,
				  tier_data_src => "git://tier_data_repo");

    isa_ok($tier, "Entity::Tier");
    
    $tier->save();
    # Test cluster->get
#    my $c2 = Entity::Cluster->getCluster(hash => {'cluster_name'=>'foobare'});
#    isa_ok($c2,Entity::Cluster,"l\'objet est bien un cluster");


};
if($@) {
	my $error = $@;
	print $error;
};


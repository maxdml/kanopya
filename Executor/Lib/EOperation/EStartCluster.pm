# EStartCluster.pm - Operation class implementing System image creation operation

# Copyright (C) 2009, 2010, 2011, 2012, 2013
#   Free Software Foundation, Inc.

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3, or (at your option)
# any later version.

# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; see the file COPYING.  If not, write to the
# Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301 USA.

# Maintained by Dev Team of Hedera Technology <dev@hederatech.com>.
# Created 14 july 2010

=head1 NAME

EEntity::EOperation::EStartCluster - Operation class implementing cluster starting operation

=head1 SYNOPSIS

This Object represent an operation.
It allows to implement cluster starting operation

=head1 DESCRIPTION



=head1 METHODS

=cut
package EOperation::EStartCluster;

use strict;
use warnings;
use Log::Log4perl "get_logger";
use vars qw(@ISA $VERSION);
use base "EOperation";
use lib qw(/workspace/mcs/Executor/Lib /workspace/mcs/Common/Lib);
use McsExceptions;

my $log = get_logger("executor");
my $errmsg;

$VERSION = do { my @r = (q$Revision: 0.1 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };

=head2 new

    my $op = EOperation::EStartCluster->new();

EOperation::EStartCluster->new creates a new EStartCluster operation.

=cut

sub new {
    my $class = shift;
    my %args = @_;
    
    my $self = $class->SUPER::new(%args);
    $self->_init();
    
    return $self;
}

=head2 _init

	$op->_init() is a private method used to define internal parameters.

=cut

sub _init {
	my $self = shift;

	return;
}

=head2 prepare

	$op->prepare();

=cut

sub prepare {
	my $self = shift;
	my %args = @_;
	$self->SUPER::prepare();

	if (! exists $args{internal_cluster} or ! defined $args{internal_cluster}) { 
		$errmsg = "EStartCluster->prepare need an internal_cluster named argument!";
		$log->error($errmsg);
		throw Mcs::Exception::Internal::IncorrectParam(error => $errmsg);
	}
	
	my $adm = Administrator->new();
	my $params = $self->_getOperation()->getParams();

	$self->{_objs} = {};
	
	# Get cluster to start from param
	$self->{_objs}->{cluster} = $adm->getEntity(type => 'Cluster', id => $params->{cluster_id});
}

sub execute {
	my $self = shift;
	$self->SUPER::execute();
	my $adm = Administrator->new();
		
	$log->info('getting minimum number of nodes to start');
	my $nodes_to_start = $self->{_objs}->{cluster}->getAttr(name => 'cluster_min_node');	
	$log->info('getting free motherboards');
	my @free_motherboards = $adm->getEntities(type => 'Motherboard', hash => { active => 1, motherboard_state => 'down'});
	
	my $priority = $self->_getOperation()->getAttr(attr_name => 'priority');
	

	for(my $i=0 ; $i < $nodes_to_start ; $i++) {
		my $motherboard = pop @free_motherboards;
		$adm->newOp(type => 'AddMotherboardInCluster',
					priority => $priority,
					params => {
						cluster_id => $self->{_objs}->{cluster}->getAttr(name => "cluster_id"),
						motherboard_id => $motherboard->getAttr(name => 'motherboard_id')
					}
		);
	} 	
	
	$self->{_objs}->{cluster}->setAttr(name => 'cluster_state', value => 'up');
	$self->{_objs}->{cluster}->save();
}

1;

__END__

=head1 AUTHOR

Copyright (c) 2010 by Hedera Technology Dev Team (dev@hederatech.com). All rights reserved.
This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
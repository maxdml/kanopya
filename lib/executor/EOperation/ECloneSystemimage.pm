# ECloneSystemimage.pm - Operation class implementing System image cloning operation

#    Copyright © 2010-2012 Hedera Technology SAS
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

# Maintained by Dev Team of Hedera Technology <dev@hederatech.com>.

=head1 NAME

EEntity::EOperation::ECloneSystemimage - Operation class implementing System image cloning operation

=head1 SYNOPSIS

This Object represent an operation.
It allows to implement System image cloning operation

=head1 DESCRIPTION



=head1 METHODS

=cut
package EOperation::ECloneSystemimage;
use parent 'EOperation';

use strict;
use warnings;

use Log::Log4perl 'get_logger';
use Data::Dumper;
use String::Random;
use Date::Simple (':all');

use Kanopya::Exceptions;
use Entity;
use EFactory;
use Entity::ServiceProvider;
use Entity::ServiceProvider::Inside::Cluster;
use Entity::Host;
use Template;

my $log = get_logger('executor');
my $errmsg;
our $VERSION = '1.00';

=head2 prepare

    $op->prepare();

=cut

sub prepare {
    my ($self, %args) = @_;
    
    $self->SUPER::prepare();

    $self->{_objs}    = {};
    $self->{executor} = {};
    
    my $params = $self->_getOperation()->getParams();

    my $imgsource_id     = General::checkParam(args => $params, name => 'systemimage_id');
    my $systemimage_name = General::checkParam(args => $params, name => 'systemimage_name');
    my $systemimage_desc = General::checkParam(args => $params, name => 'systemimage_desc');
    my $disk_manager_id  = General::checkParam(args => $params, name => 'disk_manager_id');
    
    # Get instance of Systemimage to clone
    eval {
       $self->{_objs}->{systemimage_source} = Entity::Systemimage->get(id => $imgsource_id);
    };
    if($@) {
        throw Kanopya::Exception::Internal::WrongValue(error => $@);
    }

    # Check if systemimage is not active
    $log->debug('Checking source systemimage active value <' .
                $self->{_objs}->{systemimage_source}->getAttr(name => 'systemimage_id') . '>');

    if($self->{_objs}->{systemimage_source}->getAttr(name => 'active')) {
        $errmsg = 'EOperation::ECloneSystemimage->checkop : systemimage <' .
                  $self->{_objs}->{systemimage_source}->getAttr(name => 'systemimage_id') .
                  '> is already active';
        $log->error($errmsg);
        throw Kanopya::Exception::Internal::WrongValue(error => $errmsg);
    }
    
    # Check if systemimage name does not already exist
    $log->debug('checking unicity of systemimage_name <' . $systemimage_name . '>');

    my $sysimg_exists = Entity::Systemimage->getSystemimage(
        hash => { systemimage_name => $systemimage_name }
    );

    if (defined $sysimg_exists){
        $errmsg = 'EOperation::ECloneSystemimage->prepare : systemimage_name ' .
                  $systemimage_name . ' already exist';
        $log->error($errmsg);
        throw Kanopya::Exception::Internal(error => $errmsg);
    }

    # Create new systemimage instance
    eval {
        $self->{_objs}->{systemimage} = Entity::Systemimage->new(
            systemimage_name      => $systemimage_name,
            systemimage_desc      => $systemimage_desc,
        );
    };
    if($@) {
        throw Kanopya::Exception::Internal::WrongValue(error => $@);
    }

    # Get the edisk manager for disk creation.
    eval {
        $self->{_objs}->{edisk_manager}
            = EFactory::newEEntity(data => Entity->get(id => $disk_manager_id));
    };
    if($@) {
        throw Kanopya::Exception::Internal::WrongValue(error => $@);
    }

    # Check if disk manager has enough free space
    my $neededsize = $self->{_objs}->{systemimage_source}->getDevice->getAttr(name => 'container_size');
    my $freespace  = $self->{_objs}->{edisk_manager}->_getEntity->getFreeSpace(%{$params});

    $log->debug("Size needed for systemimage device : $neededsize, freespace left : $freespace");

    # TODO: temporary disable freespace checking, cause some disk managers do not implement it.
    if(0 and $neededsize > $freespace) {
        $errmsg = "EOperation::ECloneSystemimage->prepare : not enough freespace on " .
                  "the disk manager ($freespace left, $neededsize required)";
        $log->error($errmsg);
        throw Kanopya::Exception::Internal(error => $errmsg);
    }

    # Get contexts
    my $exec_cluster
        = Entity::ServiceProvider::Inside::Cluster->get(id => $args{internal_cluster}->{'executor'});
    $self->{executor}->{econtext} = EFactory::newEContext(ip_source      => $exec_cluster->getMasterNodeIp(),
                                                          ip_destination => $exec_cluster->getMasterNodeIp());

    $self->{params} = $params;
}

sub execute {
    my $self = shift;

    my $esystemimage = EFactory::newEEntity(data => $self->{_objs}->{systemimage});
    my $esrc_container = EFactory::newEEntity(data => $self->{_objs}->{systemimage_source}->getDevice);

    $esystemimage->create(esrc_container => $esrc_container,
                          edisk_manager  => $self->{_objs}->{edisk_manager},
                          econtext       => $self->{executor}->{econtext},
                          erollback      => $self->{erollback},
                          %{$self->{params}}
    );

    $self->{_objs}->{systemimage}->cloneComponentsInstalledFrom(
        systemimage_source_id => $self->{_objs}->{systemimage_source}->getAttr(name => 'systemimage_id')
    );

    $log->info('System image <' . $self->{_objs}->{systemimage}->getAttr(name => 'systemimage_name') . '> is cloned');
}

1;

__END__

=head1 AUTHOR

Copyright (c) 2010-2012 by Hedera Technology Dev Team (dev@hederatech.com). All rights reserved.
This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

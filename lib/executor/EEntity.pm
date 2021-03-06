#    Copyright © 2011 Hedera Technology SAS
#
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

=pod
=begin classdoc

EEntity is the highest general execution object. Execution entities
provides method that execute commands on remote or local host.

=end classdoc
=cut

package EEntity;

use strict;
use warnings;

use Entity;
use Entity::Host;
use Kanopya::Exceptions;
use Kanopya::Config;
use EContext;

use TryCatch;
use Template;
use vars qw ( $AUTOLOAD );

use Log::Log4perl "get_logger";
use Data::Dumper;

my $log = get_logger("");
my $errmsg;


# Mock class to use at EEntity instanciatiation
my $mocks_classes = {};

# The host where execution code is running singleton
my $host;

# The executor component singleton to keep configuration
# TODO: Shoud be in EComponent only, by it is used in
#       opearations for instance.
my $executor;


=pod
=begin classdoc

@constructor

Factory to build an EEntity from an Entity. It try to build the
concreter execution class corresponding to the given entity, if the type
is not given in parameter.
A host shoudld be given in parameter if it is the first EEntity instanciated
in the current proccess, it will be retrieve from the singleton instead.

@param entity the entity to build the execution from.

@optional eclass the execution class to instanciate
@optional ehost the host where the execution code is running. 

@return the execution entity instance

=end classdoc
=cut

sub new {
    my ($class, %args) = @_;

    $args{entity} = $args{entity} || $args{data};

    General::checkParams(args     => \%args,
                         required => [ 'entity' ],
                         optional => { 'eclass' => $class->eclass(class => ref($args{entity})),
                                       'ehost'  => $host });

    # Check the EEntity type
    if (not $args{entity}->isa("Entity")) {
        throw Kanopya::Exception::Internal(error => "$args{entity} is not an Entity");
    }

    # Use a possibly defined mock for this execution class
    $args{eclass} = $mocks_classes->{$args{eclass}}
                        ? $args{eclass} . '::' . $mocks_classes->{$args{eclass}} : $args{eclass};

    while ($args{eclass} ne "EEntity") {
        my $location = General::getLocFromClass(entityclass => $args{eclass});
        try {
            require $location;
        }
        catch ($err) {
            # If file does not exists, use the parent package
            if ($err =~ m/Can't locate $location/) {
                $args{eclass} =~ s/\:\:[a-zA-Z0-9]+$//g;
                next;
            }
            else { die $err; }
        }
        last;
    }

    my $self = {
        _entity => $args{entity},
    };

    bless $self, $args{eclass};

    # Check the ehost definition
    if (not defined $args{ehost}) {
        # Chicken and egg situation, the first EEntity instanciated in a process
        # is the EHost to give in paramater to others EEntity.
        if ($self->isa('EEntity::EHost')) {
            $self->_host($self);
        }
        else {
            throw Kanopya::Exception::Internal(
                      error => "The ehost is neither given in parameter nor defined as singleton."
                  );
        }
    }
    elsif (not defined $self->_host) {
        # Set the singleton
        $self->_host($args{ehost});
    }

    return $self;
}


=pod
=begin classdoc

Forbid to call create on the encapsulated entity.

@return the created object instance

=end classdoc
=cut

sub create {
    my $class = shift;
    my %args = @_;

    throw Kanopya::Exception::Internal(
              error => "Cannot call create on a EEntity instance, you must implement this method in sub classes."
          );
}


=pod
=begin classdoc

Forbid to call remove on the encapsulated entity.

=end classdoc
=cut

sub remove {
    my $self = shift;
    my %args = @_;

    $self->delete();
}


=pod
=begin classdoc

Build the execution class name correspondinf to the class
given in parameter.

@param class the class name

@return the corresponding execution class name

=end classdoc
=cut

sub eclass {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'class' ]);
    
    $args{class} =~s/\:\:/\:\:E/g;
    return "E" . $args{class};
}


=pod
=begin classdoc

Build the econtext instance to execute commands.

@param dst_ip the destination host ip on which execute commands.

@return the econtext instance

=end classdoc
=cut

sub getEContext {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'dst_ip' ]);

    return EContext->new(src_ip => $self->_host->adminIp,
                         dst_ip => $args{dst_ip},
                         key    => $self->_executor->private_directory . "/kanopya_rsa");
}


=pod
=begin classdoc

Build a notification message with a given Operation

@param operation hte operation that is executing
@state the state of the operation

@return notification message

=end classdoc
=cut

sub notificationMessage {
    my $self    = shift;
    my %args    = @_;

    General::checkParams(args     => \%args,
                         required => [ 'operation', 'state', 'subscriber' ],
                         optional => { 'reason' => undef });

    my $template = Template->new(General::getTemplateConfiguration());
    my $templatedata = { operation       => $args{operation}->label,
                         operation_id    => $args{operation}->id,
                         workflow        => $args{operation}->workflow->label,
                         workflow_id     => $args{operation}->workflow->id,
                         operation_state => $args{state},
                         reason          => $args{reason} };

    my $message = "";
    $template->process('notificationmail.tt', $templatedata, \$message)
        or throw Kanopya::Exception::Internal(
             error => "Error when processing template notificationmail.tt"
         );

    my $subject = "";
    $template->process('notificationmailsubject.tt', $templatedata, \$subject)
        or throw Kanopya::Exception::Internal(
             error => "Error when processing template notificationmailsubject.tt"
         );

    return ($subject, $message);
}


=pod
=begin classdoc

Reload entity from database

@return the reloaded instance

=end classdoc
=cut

sub reload {
    my $self = shift;
    return EEntity->new(entity => $self->_entity->reload);
}


=pod
=begin classdoc

Set mock classes to override standards class/eclass matching.
Usefull for test and dummy infrastructures.

@optional mock the mock class

=end classdoc
=cut

sub setMock {
    my ($self, %args) = @_;
    my $class = ref($self) || $self;

    General::checkParams(args => \%args, optional => { 'mock' => undef });

    $mocks_classes->{$class} = $args{mock};
}


sub _host {
    my ($self, @args) = @_;

    if (scalar(@args)) {
        $host = pop @args;
    }
    else {
        return $host;
    }
}

sub _executor {
    my $self = shift;
    my %args = @_;

    return $executor if defined $executor;

    $executor = $self->_host->node->getComponent(name => 'KanopyaExecutor');

    return $executor;
}

sub _entity {
    my $self = shift;
    return $self->{_entity};
}


sub AUTOLOAD {
    my $self = shift;

    my @autoload = split(/::/, $AUTOLOAD);
    my $method = $autoload[-1];

    try {
        return $self->_entity->$method(@_);
    }
    catch (Kanopya::Exception $err) {
        $err->rethrow();
    }
    catch ($err) {
        throw Kanopya::Exception::Internal(error => "$err");
    }
}

sub DESTROY {
    my $self = shift;
    my %args = @_;
}

1;

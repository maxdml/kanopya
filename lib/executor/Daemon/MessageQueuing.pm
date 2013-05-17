#    Copyright © 2013 Hedera Technology SAS
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

=pod

=begin classdoc

Base class to manage internal daemons that communicate between them.

@since    2013-Mar-28
@instance hash
@self     $self

=end classdoc

=cut

package Daemon::MessageQueuing;
use base Daemon;
use base MessageQueuing::RabbitMQ::Receiver;

use strict;
use warnings;

use Data::Dumper;

use Log::Log4perl "get_logger";
my $log = get_logger("");


use constant CALLBACKS => {};

sub getCallbacks { return CALLBACKS; }


=pod
=begin classdoc

@constructor

Base method to configure the daemon to use the message queuing middleware,
bind callback methods to the corresponing queues.

=end classdoc
=cut

sub new {
    my ($class, %args) = @_;

    my $self = $class->SUPER::new(%args);

    # Connect the component as the connection can not be done
    # within a message callback.
    eval {
        $self->_component->connect(%{$self->{config}->{amqp}});
    };
    if ($@) {
        my $err = $@;
        if (ref($err) and $err->isa('Kanopya::Exception::Internal::NotFound')) {
            $log->warn("Can not connect the sender component <Kanopya" . $self->{name} .
                       "> as it can not be found.");
        }
        elsif (ref($err)) { $err->rethrow(); }
        else {
            throw Kanopya::Exception(
                      error => "Unable to connect to the broker: $err \n"
                  );
        }
    }

    # Force the duration if defined
    my $duration = {};
    if (defined $args{duration}) {
        $duration->{duration} = $args{duration};
    }

    # Get the callback related amqp conf
    my $cbconf = $self->{config}->{amqp}->{callbacks};

    # Register the callback for used channels
    CALLBACK:
    for my $cbname (keys %{ $self->getCallbacks }) {
        my $callback = $self->getCallbacks->{$cbname};

        # Handle the callbacks conf if defined
        if (defined $cbconf) {
            # If callbacks specified in the conf, skip not defined ones
            if (not defined $cbconf->{$cbname}) {
                $self->log(
                    level => "info",
                    msg   => "Skiping callback <$cbname> on channel <$callback->{channel}>",
                );
                next CALLBACK;
            }
            # If the number of instance is specified in conf,
            # override the callback definition
            if (defined $cbconf->{$cbname}->{instances}) {
                $callback->{instances} = $cbconf->{$cbname}->{instances};
            }
        }

        # Define a closure that call the specified callaback within eval
        my $cbmethod = sub {
            my %cbargs = @_;
            my $ack = 0;
            eval {
                $ack = $callback->{callback}->($self, %cbargs);
            };
            if ($@) { $self->log(level => 'error', msg => "$@"); }
            return $ack;
        };

        # Register worker/subscriber in function of the type
        my $instances = defined $callback->{instances} ? $callback->{instances} : 1;

        $self->log(
            level => "info",
            msg   => "Registering $instances callback(s) <$cbname> on channel <$callback->{channel}>",
        );

        if ($callback->{type} eq 'queue') {
            $self->registerWorker(callback  => \&$cbmethod,
                                  channel   => $callback->{channel},
                                  instances => $instances,
                                  %$duration);
        }
        else {
            $self->registerSubscriber(callback  => \&$cbmethod,
                                      channel   => $callback->{channel},
                                      instances => $instances,
                                      %$duration);
        }
    }
    if (not defined $self->_receivers) {
        throw Kanopya::Exception(
            error => "Could not start daemon $self->{name}, no callback defined..."
        );
    }
    return $self;
}


=pod
=begin classdoc

Register the daemon as a worker on a specific channel.
Produced data is distributed among workers, each data is delivered to exactly one worker.

@param channel the channel on which the callback is resistred
@param callback the classback method to call when data is produced on the channel

=end classdoc
=cut

sub registerWorker {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'channel', 'callback' ]);

    # Set up the daemon as receiver worker on the queue corresponding to the
    # specified channel name.
    $self->register(type => 'queue', %args);
}


=pod
=begin classdoc

Register the daemon as a subscriber on a specific channel.
Produced data is delivred to each subscribers.

@param channel the channel on which the callback is resistred
@param callback the classback method to call when data is produced on the channel

=end classdoc
=cut

sub registerSubscriber {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'channel', 'callback' ]);

    # Set up the daemon as receiver subscriber on the topic corresponding to the
    # specified channel name.
    $self->register(type => 'topic', %args);
}


=pod
=begin classdoc

Base method to run the daemon.
Override the parent method, create a child process for each registration on channels.

@param condvar the condition variable on which the daemon wait for termination

=end classdoc
=cut

sub run {
    my ($self, %args) = @_;

    General::checkParams(args     => \%args,
                         optional => { 'condvar' => AnyEvent->condvar });

    Message->send(
        from    => $self->{name},
        level   => 'info',
        content => "Kanopya $self->{name} started."
    );

    # Disconnect possibly connected session, as we must do
    # the connection inside the childs created for each channel.
    if ($self->connected) {
        $self->disconnect();
    }

    # Wait on all channel of all types
    $self->receiveAll(condvar => $args{condvar});

    # Never should aprear as the parent process loop on the running
    # pointer only, to properly stop the childs jobs at daemon stopping.
    if ($self->connected) {
        $self->disconnect();
    }

    Message->send(
        from    => $self->{name},
        level   => 'warning',
        content => "Kanopya $self->{name} stopped"
    );
}


=pod
=begin classdoc

Receive messages from the channels on which the daemon is registred,
and call the corresponding callbacks.

=end classdoc
=cut

sub oneRun {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'channel', 'type' ]);

    # Blocking call
    $self->receive(type => $args{type}, channel => $args{channel});
}

1;

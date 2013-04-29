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

Base class to becomme a message queuing sender.
Provide methods to send message on queues or topics.

@since    2013-Avr-19
@instance hash
@self     $self

=end classdoc

=cut

package MessageQueuing::RabbitMQ::Sender;
use base MessageQueuing::RabbitMQ;

use strict;
use warnings;

use Hash::Merge;
use Data::Dumper;
use vars qw($AUTOLOAD);

use Log::Log4perl "get_logger";
my $log = get_logger("");

sub methods {
    return {
        send => {
            description     => 'Produce a message to the specified channel',
            message_queuing => {}
        },
    };
}

my $senders = {};

my $merge = Hash::Merge->new('LEFT_PRECEDENT');

=pod
=begin classdoc

We define an AUTOLOAD to handle the same way method that implicitly send a message.

=end classdoc
=cut

sub AUTOLOAD {
    my ($self, %args) = @_;

    my @autoload = split(/::/, $AUTOLOAD);
    my $accessor = $autoload[-1];

    my $method = $self->methods()->{$accessor};
    if ((not defined $method) or not defined ($method->{message_queuing})) {
        # The called method is not a defined message queuing method.
        $method = 'SUPER::' . $accessor;
        return $self->$method();
    }

    # Merge the arguments with possibly prefined for this method.
    %args = %{ $merge->merge(\%args, $method->{message_queuing}) };

    General::checkParams(args => \%args, required => [ 'channel' ]);

    my $channel = delete $args{channel};
    if (not defined $senders->{$channel}) {
        if (not $self->connected) {
            throw Kanopya::Exception::Internal::IncorrectParam(
                      error => "You must to connect to the message queuing server before sending."
                  );
        }

        # Declare the exchange for the subscribers
        $self->_session->declare_exchange(exchange => $channel, type => 'fanout');
        # Declare the queue for the workers
        $self->_session->declare_queue(queue => $channel, durable => 1);

        # Keep the session to known if the exchange and the queue are created for this channel
        $senders->{$channel} = $self->_session;
    }

    # Serialize arguments
    my $data = JSON->new->utf8->encode(\%args);

    # Send message for the workers
    $senders->{$channel}->publish(exchange    => '',
                                  routing_key => $channel,
                                  body        => $data);

    # Send message for the subscribers
    $senders->{$channel}->publish(exchange    => $channel,
                                  routing_key => '',
                                  body        => $data);
}


=pod
=begin classdoc

Method called at the object deletion.

=end classdoc
=cut

sub DESTROY {}

1;
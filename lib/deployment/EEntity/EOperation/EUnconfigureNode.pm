#    Copyright © 2011-2013 Hedera Technology SAS
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

Remove the node from the dhcp server.

@since    2012-Aug-20
@instance hash
@self     $self

=end classdoc
=cut

package EEntity::EOperation::EUnconfigureNode;
use base EEntity::EOperation;

use Kanopya::Exceptions;


use strict;
use warnings;

use TryCatch;
use Log::Log4perl "get_logger";
use Data::Dumper;

my $log = get_logger("");


=pod
=begin classdoc

@param node the node to release

=end classdoc
=cut

sub check {
    my $self = shift;
    my %args = @_;

    General::checkParams(args     => $self->{context},
                         required => [ "deployment_manager", "node", "boot_manager", "network_manager" ]);
}


=pod
=begin classdoc

Remove the node from dhcp.

=end classdoc
=cut

sub execute {
    my $self = shift;

    $self->{context}->{deployment_manager}->unconfigureNode(
        node            => $self->{context}->{node},
        boot_manager    => $self->{context}->{boot_manager},
        network_manager => $self->{context}->{network_manager},
        %{ $self->{params} }
    );
}


1;

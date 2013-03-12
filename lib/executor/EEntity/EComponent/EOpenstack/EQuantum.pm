#    Copyright © 2013 Hedera Technology SAS
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

package EEntity::EComponent::EOpenstack::EQuantum;
use base "EEntity::EComponent";

use strict;
use warnings;

use EEntity;

sub postStartNode {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'cluster', 'host' ]);

    # The Puppet manifest is compiled a first time and requests the creation
    # of the database on the database cluster
    $args{cluster}->reconfigure();

    # We ask :
    # - the database cluster to create databases and users
    # - Keystone to create endpoints, users and roles
    for my $component ($self->mysql5, $self->nova_controller->amqp, $self->nova_controller->keystone) {
        if ($component) {
            EEntity->new(entity => $component->service_provider)->reconfigure();
        }
    }

    # Now that the database is created, apply the manifest again
    $args{cluster}->reconfigure();
}

1;

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

# Maintained by Dev Team of Hedera Technology <dev@hederatech.com>.

package Entity::Component::SwiftProxy;
use base "Entity::Component";

use strict;
use warnings;

use Hash::Merge qw(merge);
use Log::Log4perl "get_logger";
my $log = get_logger("");

use constant ATTR_DEF => {};

sub getAttrDef { return ATTR_DEF; }

sub getNetConf {
    return {
        swiftproxy => {
            port => 8080,
            protocols => ['tcp']
        }
    };
}

sub getPuppetDefinition {
    my ($self, %args) = @_;

    return merge($self->SUPER::getPuppetDefinition(%args), {
        swiftproxy => {
            classes => {
                "kanopya::openstack::swift::proxy" => {
                    secret => "swift",
                    password => "swift"
                }
            },
            dependencies => [ $self->keystone ]
        }
    } );
}

1;

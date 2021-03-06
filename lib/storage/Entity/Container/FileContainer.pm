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

=pod

=begin classdoc

Concrete class for file image disks localized on a container access, usualy
an Nfs export. It extends base container by specifying the container access id on
wich the file image can be accessed after mount.

@since    2012-Feb-23
@instance hash
@self     $self

=end classdoc

=cut

package Entity::Container::FileContainer;
use base "Entity::Container";

use strict;
use warnings;

use constant ATTR_DEF => {
    container_access_id => {
        pattern         => '^[0-9\.]*$',
        is_mandatory    => 1,
        is_extended     => 0,
        description     => 'The host uses this system for accessing the volume.',
    },
};

sub getAttrDef { return ATTR_DEF; }

1;

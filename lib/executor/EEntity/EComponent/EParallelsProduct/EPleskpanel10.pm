#    Copyright © 2011 Hedera Technology SAS
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
package EEntity::EComponent::EParallelsProduct::EPleskpanel10;

use strict;
use Template;
use String::Random;
use base "EEntity::EComponent::EParallelsProduct";
use Log::Log4perl "get_logger";

my $log = get_logger("executor");
my $errmsg;

# contructor

sub new {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::new( %args );
    return $self;
}



sub preStartNode {
    my $self = shift;
    my %args = @_;
    my $pleskpanel = $self->_getEntity();
    my $conf = $pleskpanel->getConf();
    my $motherboard = $args{motherboard};
    $motherboard->setAttr(name => 'motherboard_hostname', value => $conf->{pleskpanel10_hostname});
    $motherboard->save();
}

1;

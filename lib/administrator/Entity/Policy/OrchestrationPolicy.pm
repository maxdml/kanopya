# Copyright © 2011-2012 Hedera Technology SAS
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Maintained by Dev Team of Hedera Technology <dev@hederatech.com>.

package Entity::Policy::OrchestrationPolicy;
use base 'Entity::Policy';

use strict;
use warnings;

use Data::Dumper;
use Log::Log4perl 'get_logger';

my $log = get_logger("");

use constant ATTR_DEF => {};

sub getAttrDef { return ATTR_DEF; }

use constant POLICY_ATTR_DEF => {};

sub getPolicyAttrDef { return POLICY_ATTR_DEF; }


sub getPatternFromParams {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ 'params' ]);

    my $pattern = $self->SUPER::getPatternFromParams(params => $args{params});

    if (defined $args{params}->{orchestration_service_provider_id}) {
        $pattern->{orchestration}->{service_provider_id} = delete $args{params}->{orchestration_service_provider_id};
    }
    return $pattern;
}

1;


#    Copyright © 2009-2013 Hedera Technology SAS
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

package EEntity::EOperation::ECreateExport;
use base EEntity::EOperation;

use strict;
use warnings;

use Kanopya::Exceptions;
use Entity::Container;
use EEntity;

use Log::Log4perl "get_logger";
use Data::Dumper;

my $log = get_logger("");
my $errmsg;

sub check {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => $self->{context}, required => [ "export_manager", "container" ]);

    General::checkParams(args => $self->{params}, required => [ "manager_params" ]);
}


sub execute {
    my $self = shift;

    # Check state of the export manager
    if (! $self->{context}->{export_manager}->isAvailable()) {
        $errmsg = "Export manager has to be up !";
        $log->error($errmsg);
        throw Kanopya::Exception::Execution(error => $errmsg);
    }

    $self->{context}->{export_manager}->createExport(container => $self->{context}->{container},
                                                     erollback => $self->{erollback},
                                                     %{$self->{params}->{manager_params}});
}

1;

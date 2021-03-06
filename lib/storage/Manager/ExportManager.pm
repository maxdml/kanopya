# Copyright © 2012-2013 Hedera Technology SAS
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

=pod
=begin classdoc

TODO

=end classdoc
=cut

package Manager::ExportManager;
use base "Manager";

use strict;
use warnings;

use Kanopya::Exceptions;

use Log::Log4perl "get_logger";
use Data::Dumper;

my $log = get_logger("");
my $errmsg;

sub exportType {
    return '';
}


sub checkExportManagerParams {}


=pod
=begin classdoc

@return the managers parameters as an attribute definition. 

=end classdoc
=cut

sub getExportManagerParams {
    my $self = shift;
    my %args  = @_;

    return {};
}

sub getReadOnlyParameter {
    throw Kanopya::Exception::NotImplemented();
}


=pod
=begin classdoc

Enqueue a CreateExport operation

@param container the container from which the export must be created

@return the created workflow

=end classdoc
=cut

sub createExport {
    my $self = shift;
    my %args = @_;

    General::checkParams(args     => \%args,
                         required => [ "container" ]);

    $log->debug("New Operation CreateExport with attrs : " . %args);
    return $self->executor_component->execute(
        type     => 'CreateExport',
        params   => {
            context => {
                export_manager => $self,
                container      => $args{container},
            },
            manager_params => {},
        },
    );
}


=pod
=begin classdoc

Enqueue a RemoveExport operation

@param container_access the container access to remove

@return the created workflow

=end classdoc
=cut

sub removeExport {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ "container_access" ]);

    $log->debug("New Operation RemoveExport with attrs : " . %args);
    return $self->executor_component->enqueue(
        type     => 'RemoveExport',
        params   => {
            context => {
                export_manager   => $self,
                container_access => $args{container_access},
            }
        },
    );
}

1;

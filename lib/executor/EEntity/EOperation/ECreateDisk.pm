#    Copyright © 2012-2013 Hedera Technology SAS
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

package EEntity::EOperation::ECreateDisk;
use base "EEntity::EOperation";

use strict;
use warnings;

use EEntity;
use Kanopya::Exceptions;

use Entity::ServiceProvider;

use Log::Log4perl "get_logger";
use Data::Dumper;

my $log = get_logger("");
my $errmsg;


sub prepare {
    my ($self, %args) = @_;
    $self->SUPER::prepare(%args);

    General::checkParams(args => $self->{context}, required => [ "disk_manager" ]);

    General::checkParams(args     => $self->{params},
                         required => [ "name", "size" ]);

    # Check service provider state
    my $storage_provider = $self->{context}->{disk_manager}->service_provider;
    my ($state, $timestamp) = $storage_provider->getState();
    if ($state ne 'up'){
        $errmsg = "Service provider has to be up !";
        $log->error($errmsg);
        throw Kanopya::Exception::Internal::IncorrectParam(error => $errmsg);
    }
}

sub execute {
    my ($self, %args) = @_;
    $self->SUPER::execute(%args);

    my $container = $self->{context}->{disk_manager}->createDisk(
                        name       => $self->{params}->{name},
                        size       => $self->{params}->{size},
                        filesystem => $self->{params}->{filesystem},
                        erollback  => $self->{erollback},
                        %{ $self->{params} }
                    );

    $log->info("New container <" . $container->container_name . "> created");
}

1;

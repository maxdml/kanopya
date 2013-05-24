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

# Maintained by Dev Team of Hedera Technology <dev@hederatech.com>.

package EEntity::EOperation::EMigrateHost;
use base EEntity::EOperation;

use strict;
use warnings;

use Log::Log4perl "get_logger";
use Data::Dumper;
use Kanopya::Exceptions;
use Entity::ServiceProvider;
use Entity::Host;
use CapacityManagement;

my $log = get_logger("");
my $errmsg;

sub check {
    my ($self, %args) = @_;

    General::checkParams(args => $self->{context}, required => [ "host", "vm" ]);
}

sub prerequisites {
    my ($self, %args) = @_;

    if (not defined $self->{context}->{cloudmanager_comp}) {
        $self->{context}->{cloudmanager_comp} = $self->{context}->{vm}->getHostManager();
    }

    my $diff_infra_db = $self->{context}->{cloudmanager_comp}
                             ->checkHypervisorVMPlacementIntegrity(host => $self->{context}->{host});
    eval {
        $diff_infra_db = $self->{context}->{cloudmanager_comp}
                              ->checkVMPlacementIntegrity(host          => $self->{context}->{vm},
                                                          diff_infra_db => $diff_infra_db);
    };
    if ($@) {
        my $error = $@;

        # Vm is not found in infrastructure
        # Enqueue synchronization in *new* workflow to repair DB
        # Throw exception to stop migration
        $self->_executor->enqueue(
            priority => 200,
            type     => 'SynchronizeInfrastructure',
            params   => {
                context => {
                    hypervisor => $self->{context}->{host},
                    vm         => $self->{context}->{vm},
                },
                diff_infra_db => $diff_infra_db,
            }
        );
        throw Kanopya::Exception(error => $error);
    }

    if (! $self->{context}->{cloudmanager_comp}->isInfrastructureSynchronized(hash => $diff_infra_db)) {

        # Repair infra before retrying AddNode

        $self->workflow->enqueueBefore(
            operation => {
                priority => 200,
                type     => 'SynchronizeInfrastructure',
                params   => {
                    context => {
                        hypervisor => $self->{context}->{host},
                        vm         => $self->{context}->{vm},
                    },
                    diff_infra_db => $diff_infra_db,
                }
            }
        );
        return -1;
    }

}

sub prepare {
    my ($self, %args) = @_;
    $self->SUPER::prepare(%args);

    General::checkParams(args => $self->{context}, required => [ "host", "vm" ]);

    # check if host is deactivated
    if ($self->{context}->{host}->active == 0) {
        throw Kanopya::Exception::Internal(error => 'hypervisor is not active');
    }

    # check if host is up
    if (not $self->{context}->{host}->checkUp()) {
        throw Kanopya::Exception::Internal(error => 'hypervisor is not up');
    }

    # check if VM is up
    if (not $self->{context}->{vm}->checkUp()) {
        throw Kanopya::Exception::Internal(error => 'VM is not up');
    }

    # Check if host is on the hypervisors cluster
    if ($self->{context}->{host}->getClusterId() !=
        $self->{context}->{vm}->hypervisor->getClusterId()) {
        throw Kanopya::Exception::Internal::WrongValue(error => "VM is not on the hypervisor cluster");
    }

    # Check if the destination differs from the source
    my $vm_state = $self->{context}->{cloudmanager_comp}->getVMState(
        host => $self->{context}->{vm},
    );

    $log->info('Destination hv <' . $self->{context}->{host}->node->node_hostname .
               '> vs cloud manager hv <' . $vm_state->{hypervisor} . '>');

    if ($self->{context}->{host}->node->node_hostname eq $vm_state->{hypervisor}) {
        $log->info('VM is on the same hypervisor, no need to migrate');
        $self->{params}->{no_migration} = 1;
    }
    else {
        # Check if there is enough resource in destination host
        my $vm_id      = $self->{context}->{vm}->getAttr(name => 'entity_id');
        my $cluster_id = $self->{context}->{vm}->getClusterId();
        my $hv_id      = $self->{context}->{'host'}->getId();

        my $cm = CapacityManagement->new(
                     cloud_manager => $self->{context}->{cloudmanager_comp},
                 );

        my $check = $cm->isMigrationAuthorized(vm_id => $vm_id, hv_id => $hv_id);

        if ($check == 0) {
            my $errmsg = "Not enough resource in HV $hv_id for VM $vm_id migration";
            $log->warn($errmsg);
            throw Kanopya::Exception::Internal(error => $errmsg);
        }
    }
}

sub execute {
    my ($self, %args) = @_;
    $self->SUPER::execute(%args);

    if (defined $self->{params}->{no_migration}) {
        delete $self->{params}->{no_migration};
    }
    else {
        $self->{context}->{cloudmanager_comp}->migrateHost(
            host               => $self->{context}->{vm},
            hypervisor_dst     => $self->{context}->{host},
        );

        $log->info("VM <" . $self->{context}->{vm}->id .
                   "> is migrating to <" . $self->{context}->{host}->id . ">");
    }
}

sub finish{
    my ($self, %args) = @_;
    $self->SUPER::execute(%args);

    delete $self->{context}->{vm};
    delete $self->{context}->{host};
}

sub postrequisites {
    my $self = shift;

    my $migr_state = $self->{context}->{cloudmanager_comp}->getVMState(
                         host => $self->{context}->{vm},
                     );

    $log->info('Virtual machine <' . $self->{context}->{vm}->id . '> state: <'. $migr_state->{state} .
               '>, current hypervisor: <' . $migr_state->{hypervisor} .
               '>, dest hypervisor: <' . $self->{context}->{host}->node->node_hostname . '>');

    if ($migr_state->{state} eq 'runn') {
        # On the targeted hv
        if ($migr_state->{hypervisor} eq $self->{context}->{host}->node->node_hostname) {

            # After checking migration -> store migration in DB
            $self->{context}->{cloudmanager_comp}->_entity->migrateHost(
                host               => $self->{context}->{vm},
                hypervisor_dst     => $self->{context}->{host},
            );
            return 0;
        }
        else {
            # Vm is running but not on its hypervisor
            my $error = 'Migration of vm <' . $self->{context}->{vm}->id . '> failed, but still running...';
            $log->warn($error);
            Message->send(
                from    => 'EMigrateHost',
                level   => 'error',
                content => $error,
            );
            throw Kanopya::Exception(error => $error);
        }
    }
    elsif ($migr_state->{state} eq 'migr') {
        # vm is still migrating
        return 15;
    }
}

1;

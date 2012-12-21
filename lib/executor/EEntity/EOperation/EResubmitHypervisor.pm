# EResubmitHypervisor.pm - Operation class implementing

#    Copyright © 2012 Hedera Technology SAS
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
# Created 26 sept 2012

=head1 NAME

EEntity::Operation::EResubmitHypervisor - Operation class implementing

=head1 SYNOPSIS

This Object represent an operation.
It allows to implement

=head1 DESCRIPTION

Component is an abstract class of operation objects

=head1 METHODS

=cut
package EEntity::EOperation::EResubmitHypervisor;
use base "EEntity::EOperation";

use strict;
use warnings;
use Entity;

use Log::Log4perl "get_logger";
use Data::Dumper;

my $log = get_logger("");
my $errmsg;

sub check {
    my $self = shift;
    General::checkParams(args => $self->{context}, required => [ "host" ]);
}

sub prepare {
    my $self = shift;

    $self->SUPER::prepare();

    if (not $self->{context}->{host}->isa('EEntity::EHost::EHypervisor')) {
        my $error = 'Operation can only be applied to an hypervisor';
        throw Kanopya::Exception(error => $error);
    }

    $self->{context}->{host}->setAttr(name => 'active', value => 0);
    $self->{context}->{host}->save();
}

sub execute {
    my $self = shift;

    $self->{context}->{cloud_manager} = EFactory::newEEntity(
                                            data => $self->{context}->{host}->getCloudManager(),
                                        );

    my @vms = $self->{context}->{host}->virtual_machines;
    my %vms_wanted_values;

    for my $vm (@vms) {
        $vms_wanted_values{$vm->id} = {ram => $vm->host->host_ram, cpu => $vm->host->host_core};
    }

    my $cm = CapacityManagement->new( cloud_manager => $self->{context}->{cloud_manager} );

    my $resubmition_hv_ids = $cm->getHypervisorIdsForVMs(vms_wanted_values => \%vms_wanted_values);

    my $workflow = $self->workflow;

    while (my ($vm_id, $hv_id) = each %{$resubmition_hv_ids}) {

        my $vm_host = Entity->get(id => $vm_id)->host;
        my $hv = Entity->get(id => $hv_id);

        $log->info("Plan to move vm <".$vm_host->id."> on hypervisor <$hv_id>");

        my $workflow_to_enqueue = {
             name   => 'ResubmitNode',
             params => {
                 context => {
                     host        => $vm_host,
                     hypervisor  => $hv,
                 }
             }
        };

        $workflow->enqueueNow(workflow => $workflow_to_enqueue);

    }
    $self->SUPER::execute();
}

sub finish {
    my ($self) = @_;
    $self->{context}->{host}->setAttr(name => 'active', value => 1);
    $self->{context}->{host}->save();
    delete $self->{context}->{host};
}

1;

__END__

=head1 AUTHOR

Copyright (c) 2010 by Hedera Technology Dev Team (dev@hederatech.com). All rights reserved.
This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

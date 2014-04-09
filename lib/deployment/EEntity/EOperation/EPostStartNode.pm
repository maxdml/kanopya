#    Copyright © 2011-2013 Hedera Technology SAS
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

=pod
=begin classdoc

Ensure the components are up on the new node, and configure them.

@since    2012-Aug-20
@instance hash
@self     $self

=end classdoc
=cut

package EEntity::EOperation::EPostStartNode;
use base "EEntity::EOperation";

use strict;
use warnings;

use Kanopya::Exceptions;
use EEntity;
use Entity::ServiceProvider;
use Entity::ServiceProvider::Cluster;
use Entity::Host;

use Log::Log4perl "get_logger";
use Data::Dumper;
use String::Random;
use Date::Simple (':all');
use Template;

my $log = get_logger("");
my $errmsg;


=pod
=begin classdoc

@param cluster the cluster to add node
@param host    the host selected registred as node

=end classdoc
=cut

sub check {
    my ($self, %args) = @_;

    General::checkParams(args => $self->{context}, required => [ "cluster", "host" ]);
}


=pod
=begin classdoc

Wait for the to be up.

=end classdoc
=cut

sub prerequisites {
    my ($self, %args) = @_;

    # Duration to wait before retrying prerequistes
    my $delay = 10;

    # Duration to wait for setting host broken
    my $broken_time = 240;

    my $host_id = $self->{context}->{host}->id;

    # Check how long the host is 'starting'
    my @state = $self->{context}->{host}->getState;
    my $starting_time = time() - $state[1];
    if($starting_time > $broken_time) {
        $self->{context}->{host}->timeOuted();
    }

    my $node_ip = $self->{context}->{host}->adminIp;
    if (not $node_ip) {
        throw Kanopya::Exception::Internal(error => "Host <$host_id> has no admin ip.");
    }

    if (! $self->{context}->{host}->checkUp()) {
        $log->info("Host <$host_id> not yet reachable at <$node_ip>");
        return $delay;
    }

    # Check if all host components are up.
    if (not $self->{context}->{cluster}->checkComponents(host => $self->{context}->{host})) {
        return $delay;
    }

    # Node is up
    $self->{context}->{host}->setState(state => "up");
    $self->{context}->{host}->setNodeState(state => "in");

    $log->info("Host <$host_id> is 'up'");

    return 0;
}


=pod
=begin classdoc

Configure the component as the new node is up.

=end classdoc
=cut

sub execute {
    my ($self, %args) = @_;

    $self->{context}->{cluster}->postStartNode(
        host      => $self->{context}->{host},
        erollback => $self->{erollback},
    );

    eval {
        my $eagent = EEntity->new(
                         entity => $self->{context}->{cluster}->getComponent(category => "Configurationagent")
                     );
        # And apply the configuration on every node of the cluster
        $eagent->applyConfiguration(cluster => $self->{context}->{cluster},
                                    tags    => [ "kanopya::operation::poststartnode" ]);
    };
    if ($@) {
        my $err = $@;
        if (! $err->isa("Kanopya::Exception::Internal::NotFound")) {
           $err->rethrow();
        }
    }

    $self->{context}->{host}->postStart();

    # Update the user quota on ram and cpu
    $self->{context}->{cluster}->owner->consumeQuota(
        resource => 'ram',
        amount   => $self->{context}->{host}->host_ram,
    );
    $self->{context}->{cluster}->owner->consumeQuota(
        resource => 'cpu',
        amount   => $self->{context}->{host}->host_core,
    );
}


=pod
=begin classdoc

Set the cluster as up if all node started, start the other nodes instead.

=end classdoc
=cut

sub finish {
    my ($self, %args) = @_;

    if (defined $self->{params}->{needhypervisor}) {
        $log->debug('Do not finish addNode workflow in case of automatic hypervisor scaleout');

        # TODO: Definitly design a mechanism to bind output params to input one in workflows
        $self->{context}->{cluster} = $self->{context}->{vm_cluster}; # Used in case of automatic hypervisor scaleout
        delete $self->{params}->{needhypervisor};
        return 0;
    }

    # Add another node in a embedded workflow if required
    my @nodes = $self->{context}->{cluster}->nodes;
    if (scalar(@nodes) < $self->{context}->{cluster}->cluster_min_node) {
        $self->workflow->enqueueNow(workflow => {
            name       => 'AddNode',
            related_id => $self->{context}->{cluster}->id,
            params     => {
                context => {
                    cluster => $self->{context}->{cluster}->_entity,
                },
            },
        });
    }
    # Set the cluster up instead
    else {
        $self->{context}->{cluster}->setState(state => "up");
        $self->{context}->{cluster}->removeState(consumer => $self->workflow);
    }

    if (defined $self->{context}->{host_manager_sp}) {
        $self->{context}->{host_manager_sp}->setState(state => 'up');
        $self->{context}->{host_manager_sp}->removeState(consumer => $self->workflow);
        delete $self->{context}->{host_manager_sp};
    }

    $self->{context}->{host}->removeState(consumer => $self->workflow);

    # Add state to hypervisor if defined
    if (defined $self->{context}->{hypervisor}) {
        $self->{context}->{hypervisor}->removeState(consumer => $self->workflow);
    }

    # WARNING: Do NOT delete $self->{context}->{host}, required in workflow addNode + VM migration
}

1;
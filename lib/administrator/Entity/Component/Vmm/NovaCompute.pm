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

# Maintained by Dev Team of Hedera Technology <dev@hederatech.com>.

package  Entity::Component::Vmm::NovaCompute;
use base "Entity::Component::Vmm";

use strict;
use warnings;

use Hash::Merge qw(merge);
use Log::Log4perl "get_logger";
my $log = get_logger("");

use constant ATTR_DEF => {
    iaas_id => {
        label        => 'Openstack controller',
        type         => 'relation',
        relation     => 'single',
        pattern      => '^\d*$',
        is_mandatory => 0,
        is_editable  => 1,
        specialized  => 'nova_controller'
    },
};

sub getAttrDef { return ATTR_DEF; }

sub nova_controller {
    return shift->iaas;
}

sub getPuppetDefinition {
    my ($self, %args) = @_;

    General::checkParams(args     => \%args,
                         required => [ 'cluster', 'host' ]);

    # The support of network is very limited
    # We create only one bridge for all the networks with no VLAN
    # and a bridge for all the networks with VLAN

    my $bridge_vlan;
    my $bridge_flat;

    IFACE:
    for my $iface ($args{host}->getIfaces()) {
        next IFACE if $iface->hasRole(role => 'admin');

        for my $netconf ($iface->netconfs) {
            if (scalar $netconf->vlans) {
                $bridge_vlan = $iface->iface_name if not $bridge_vlan;
                next IFACE;
            }
        }

        $bridge_flat = $iface->iface_name if not $bridge_flat;
    }

    my $glance = join(",", map { $_->getMasterNode->fqdn . ":9292" } $self->nova_controller->glances);
    my $keystone = $self->nova_controller->keystone->getMasterNode->fqdn;
    my $quantum = ($self->nova_controller->quantums)[0];
    my $amqp = $self->nova_controller->amqp->getMasterNode->fqdn;
    my $name = "nova-" . $self->nova_controller->id;

    my @uplinks;

    if ($bridge_flat) {
        push @uplinks, "br-flat:" . $bridge_flat;
    }

    if ($bridge_vlan) {
        push @uplinks, "br-vlan:" . $bridge_vlan;
    }

    return merge($self->SUPER::getPuppetDefinition(%args), {
        novacompute => {
            manifest => $self->instanciatePuppetResource(
                            name => "kanopya::openstack::nova::compute",
                            params => {
                                glance => $glance,
                                keystone => $keystone,
                                quantum => $quantum->getMasterNode->fqdn,
                                bridge_uplinks => \@uplinks,
                                email => $self->nova_controller->service_provider->user->user_email,
                                libvirt_type => 'kvm',
                                rabbit_user => $name,
                                rabbit_virtualhost => 'openstack-' . $self->nova_controller->id
                            }
                        ),
            dependencies => [ $self->nova_controller->amqp ]
        }
    } );
}

sub getHostsEntries {
    my $self = shift;

    my @entries;
    for my $glance ($self->nova_controller->glances) {
        @entries = (@entries, $glance->service_provider->getHostEntries());
    }

    @entries = ($self->nova_controller->keystone->service_provider->getHostEntries(),
                $self->nova_controller->amqp->service_provider->getHostEntries());

    return \@entries;
}

sub checkConfiguration {
    shift->checkAttribute(attribute => "iaas");
}

1;

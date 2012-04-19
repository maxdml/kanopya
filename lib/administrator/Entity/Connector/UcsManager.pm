#    UCSManager.pm - Cisco UCS connector
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

package Entity::Connector::UcsManager;
use base "Entity::Connector";
use base "Entity::HostManager";

use Administrator;
use Entity::HostManager;
use Data::Dumper;

use warnings;

use Cisco::UCS;
use Cisco::UCS::VLAN;

use constant ATTR_DEF => {};

my ($schema, $config, $oneinstance);

sub getAttrDef { return ATTR_DEF; }

sub getBootPolicies {
    return (Entity::HostManager->BOOT_POLICIES->{pxe_iscsi},
            Entity::HostManager->BOOT_POLICIES->{pxe_nfs},
            Entity::HostManager->BOOT_POLICIES->{boot_on_san});
}

sub getHostType {
    return "UCS blade";
}

sub get {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::get(%args);

    $self->init();

    return $self;
}

sub init {
    my $self = shift;

    my $ucs = Entity->get(id => $self->getAttr(name => "service_provider_id"));

    $self->{api} = Cisco::UCS->new(
                       proto    => "http",
                       port     => 80,
                       cluster  => $ucs->getAttr(name => "ucs_addr"),
                       username => $ucs->getAttr(name => "ucs_login"),
                       passwd   => $ucs->getAttr(name => "ucs_passwd")
                   );

    $self->{state} = ($self->{api}->login() ? "up" : "down");
    $self->{ou} = $ucs->getAttr(name => "ucs_ou");
    $self->{ucs} = $ucs;
}

sub AUTOLOAD {
    my $self = shift;
    my %args = @_;

    my @autoload = split(/::/, $AUTOLOAD);
    my $method = $autoload[-1];

    return $self->{api}->$method(%args);
}

sub DESTROY {
    my $self = shift;

    if (defined $self->{api}) {
        $self->{api}->logout();
        $self->{api} = undef;
    }
}

=head2 synchronize

    Desc: synchronize ucs information with kanopya database
    
=cut

sub synchronize {
    my $self = shift;
    my %args = @_;

    $self->login();
    
    my @blades = $self->get_blades();   

    # Get a "random" kernel for his id :
    my $kernelhash =  Entity::Kernel->find(hash => {});
    my $kernelid = $kernelhash->getAttr('name' => 'kernel_id');

    # Get a "random" host model for his id :
    my $hostmodelhash = Entity::Hostmodel->find(hash => {});
    my $hostmodelid = $hostmodelhash->getAttr('name' => 'hostmodel_id');

    # Get a "random" processor model for his id :
    my $processormodelhash = Entity::Processormodel->find(hash => {});
    my $processormodelid = $processormodelhash->getAttr('name' => 'processormodel_id');

    # Get the hostmanager for his id :
    my $hostmanagerid = $self->getAttr('name' => 'entity_id');
    my $adm = Administrator->new;

    foreach my $blade (@blades) {
        # Add the blade to the host table :
        my %parameters = (
                kernel_id           => $kernelid,
                host_serial_number  => $blade->{dn},
                host_ram            => $blade->{totalMemory} * 1024 * 1024,
                host_core           => $blade->{numOfCores},
                hostmodel_id        => $hostmodelid,
                processormodel_id   => $processormodelid,
                host_desc           => $blade->{dn},
                active              => "1",
                host_manager_id     => $hostmanagerid,
        );

        # Check if an entry with the same serial number exist in table
        my $serial_number_exist = Entity::Host->search( hash => { host_serial_number => $blade->{dn} } );
        my $nb_sn_occurences = scalar($serial_number_exist);
        if( $nb_sn_occurences == '0' ) {
            Entity::Host->new(%parameters);
        }
    }
    
    # Synchronize VLANs from UCS to Kanopya :
    my @ucsvlans = $self->get_vlans();

    foreach my $ucsvlan (@ucsvlans) {
        my $ucsvlan_name = $ucsvlan->{name};
        my $ucsvlan_nb = $ucsvlan->{id};
        %parameters = (
            network_name => $ucsvlan_name,
            vlan_number  => $ucsvlan_nb,
        );

        # Get Vlans existing in Kanopya :
        my $existingvlans = Entity::Network->search(hash => { network_name => $ucsvlan_name });
        my $existingvlan = scalar($existingvlans);

        # If the vlan not exist in Kanopya, create it :
        if ($existingvlan eq "0") {
            Entity::Network::Vlan->new(%parameters);
        }
    }

    # Synchronize VLANs from Kanopya to UCS :
    # Get all VLANs on Kanopya :
    my @vlans = Entity::Network::Vlan->search(hash => {});
    foreach my $vlan (@vlans) {
        my $vlan_nb = $vlan->getAttr('name' => 'vlan_number');
        my $vlan_name = $vlan->getAttr('name' => 'network_name');

        # We must ignore the VLAN 0 on Kanopya side, this is the default UCS Vlan too
        if ($vlan_nb ne "0") {
            %parameters = (
                ucs         => $self,
                defaultNet  => "no",
                id          => $vlan_nb,
                name        => $vlan_name,
                pubNwName   => "",
                sharing     => "none",
                status      => "created",
            );

            # Create VLANs on UCS :
            # Creation is encapsulated in an eval for avoid "already created" errors :
            eval {
                Cisco::UCS::VLAN->create(%parameters);
            };
        }
    }

    $self->logout();

    if($@) {
        print $@;
    }
}

1;

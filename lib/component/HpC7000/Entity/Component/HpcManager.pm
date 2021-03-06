# copyright © 2013 hedera technology sas
#
# this program is free software: you can redistribute it and/or modify
# it under the terms of the gnu affero general public license as
# published by the free software foundation, either version 3 of the
# license, or (at your option) any later version.
#
# this program is distributed in the hope that it will be useful,
# but without any warranty; without even the implied warranty of
# merchantability or fitness for a particular purpose.  see the
# gnu affero general public license for more details.
#
# you should have received a copy of the gnu affero general public license
# along with this program.  if not, see <http://www.gnu.org/licenses/>.

package Entity::Component::HpcManager;
use base "Entity::Component";
use base "Manager::HostManager";

use warnings;

use constant ATTR_DEF => {
    executor_component_id => {
        label        => 'Workflow manager',
        type         => 'relation',
        relation     => 'single',
        pattern      => '^[0-9\.]*$',
        is_mandatory => 1,
        is_editable  => 0,
    },
    virtualconnect_ip   => {
        label        => 'VirtualConnect IP',
        type         => 'string',
        is_mandatory => 1,
        is_editable  => 1,
        pattern      => '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$',
	description  => 'The IP of your HP VirtualConnect management interface',
    },
    virtualconnect_user => {
        label        => 'VirtualConnect User',
        type         => 'string',
        is_mandatory => 1,
        is_editable  => 1,
	description  => 'The user name for your HP VirtualConnect management account',
    },
    bladesystem_ip      => {
        label        => 'BladeSystem IP',
        type         => 'string',
        is_mandatory => 1,
        is_editable  => 1,
        pattern      => '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$',
	description  => 'The IP of your HP C7000 management interface',
    },
    bladesystem_user    => {
        label        => 'BladeSystem User',
        type         => 'string',
        is_mandatory => 1,
        is_editable  => 1,
	description  => 'The user name for your HP C7000 management account',
    },
    host_type           => {
        is_virtual => 1
    }
};

sub getAttrDef { return ATTR_DEF; }

sub getBootPolicies {
    return (Manager::HostManager->BOOT_POLICIES->{pxe_iscsi},
            Manager::HostManager->BOOT_POLICIES->{pxe_nfs});
}

sub hostType {
    return 'HP Blade';
}

sub methods {
    return { };
}

1;

#    Copyright © 2013 Hedera Technology SAS
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

package  Entity::Component::Openstack::Cinder;
use base "Entity::Component";
use base "Manager::DiskManager";

use strict;
use warnings;

use Entity::Container::LvmContainer;
use Entity::Component::Lvm2::Lvm2Lv;
use Entity::Component::Lvm2::Lvm2Vg;
use Entity::ContainerAccess::IscsiContainerAccess;

use Log::Log4perl "get_logger";
my $log = get_logger("");

use constant ATTR_DEF => {
};

sub getAttrDef { return ATTR_DEF; }

=head 2

=begin classdoc
Register a new logical volume into Kanopya

@param lvm2_lv_name the name of the logical volume
@param lv2_lv_size the size of the logical volume

@return the newly created lvmcontainer object

=end classdoc

=cut

sub lvcreate {
    my ($self, %args) = @_;

    General::checkParams(args     => \%args,
                         required => [ "lvm2_lv_name", "lvm2_lv_size", "volume_id" ],
                         optional => {container_device => undef });

    my $cinder_vg = Entity::Component::Lvm2::Lvm2Vg->find(hash => { lvm2_vg_name => 'cinder-volumes' });

    my $lv = Entity::Component::Lvm2::Lvm2Lv->new(
        lvm2_lv_name       => $args{lvm2_lv_name},
        lvm2_vg_id         => $cinder_vg->id,
        lvm2_lv_freespace  => 0,
        lvm2_lv_size       => $args{lvm2_lv_size},
    );

    my $container_device = '/dev' . $cinder_vg->lvm2_vg_name . '/' . $args{volume_id};

    my $container = Entity::Container::LvmContainer->new(
                        disk_manager_id      => $self->id,
                        container_name       => $lv->lvm2_lv_name, 
                        container_size       => $args{lvm2_lv_size}, 
                        container_freespace  => 0,
                        container_device     => $container_device ,
                        lv_id                => $lv->id 
                    );

    $self->createExport(container => $container);

    return $container;

}

=head 2

=begin classdoc
Register a new iscsi container access into Kanopya 

=end classdoc

=cut

sub createExport {
    my ($self, %args) = @_;

    General::checkParams(args     => \%args,
                         required => [ "container" ] );

    Entity::ContainerAccess::IscsiContainerAccess->new(
        container_id            => $args{container}->id,
        container_access_export =>,
        container_access_port   =>,
        container_access_ip     =>,
#        device_connected        =>,
#        partition_connected     =>,
        export_manager_id       => $self->id,
    );
}

=head2

=begin classdoc
Generate component manifest

@return content of the Cinder puppet manifest

=end classdoc

=cut

sub getPuppetDefinition {
    my ($self, %args) = @_;

    my $amqp = $self->nova_controller->amqp->getMasterNode->fqdn;
    my $sql  = $self->mysql5;
    my $keystone = $self->nova_controller->keystone;

    return "class { 'kanopya::openstack::cinder':\n" .
                "\tamqpserver => '" . $amqp . "',\n" .
                "\trabbits    => ['" . $amqp . "', '" . $amqp . "'],\n" .
                "\tdbpassword => 'cinder',\n" .
                "\tdbserver   => '" . $sql->getMasterNode->fqdn . "',\n" .
                "\trpassword  => 'cinder',\n" .
                "\tkpassword  => 'cinder',\n" .
                "\temail      => '" . $self->service_provider->user->user_email . "',\n" .
                "\tkeystone   => '" . $keystone->getMasterNode->fqdn ."',\n" .
           "}\n";
}

sub getHostsEntries {
    my $self = shift;

    my @entries = ($self->nova_controller->keystone->service_provider->getHostEntries(),
                   $self->nova_controller->amqp->service_provider->getHostEntries(),
                   $self->mysql5->service_provider->getHostEntries());

    return \@entries;
}

=head

=begin classdoc
Implement createDisk from DiskManager interface.
This function enqueue a ECreateDisk operation.

@param vg_id id of the vg from which the disk must be created
@param name name of the disk to be created
@param size size of the disk to be created

=end classdoc

=cut

sub createDisk {
    my ($self,%args) = @_;

    General::checkParams(args     => \%args,
                         required => [ "name", "size" ]);

    $log->debug("New Operation CreateDisk with attrs : " . %args);
    Entity::Operation->enqueue(
        priority => 200,
        type     => 'CreateDisk',
        params   => {
            name       => $args{name},
            size       => $args{size},
            context    => {
                disk_manager => $self,
            }
        },
    );
}

1;

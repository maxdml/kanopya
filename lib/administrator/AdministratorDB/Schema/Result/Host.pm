package AdministratorDB::Schema::Result::Host;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

AdministratorDB::Schema::Result::Host

=cut

__PACKAGE__->table("host");

=head1 ACCESSORS

=head2 host_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 hostmodel_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 1

=head2 processormodel_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 1

=head2 kernel_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=head2 host_serial_number

  data_type: 'char'
  is_nullable: 0
  size: 64

=head2 host_powersupply_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 1

=head2 host_ipv4_internal_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 1

=head2 host_desc

  data_type: 'char'
  is_nullable: 1
  size: 255

=head2 active

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 host_mac_address

  data_type: 'char'
  is_nullable: 0
  size: 18

=head2 host_initiatorname

  data_type: 'char'
  is_nullable: 1
  size: 64

=head2 host_internal_ip

  data_type: 'char'
  is_nullable: 1
  size: 15

=head2 host_hostname

  data_type: 'char'
  is_nullable: 1
  size: 32

=head2 etc_device_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 1

=head2 host_state

  data_type: 'char'
  default_value: 'down'
  is_nullable: 0
  size: 32

=cut

=head2 host_prev_state

  data_type: 'char'
  is_nullable: 1
  size: 32

=cut

__PACKAGE__->add_columns(
  "host_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "hostmodel_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 1,
  },
  "cloud_cluster_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 1,
  },

  "processormodel_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 1,
  },
  "kernel_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "host_serial_number",
  { data_type => "char", is_nullable => 0, size => 64 },
  "host_ram",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "host_core",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "host_powersupply_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 1,
  },
  "host_ipv4_internal_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 1,
  },
  "host_desc",
  { data_type => "char", is_nullable => 1, size => 255 },
  "active",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "host_mac_address",
  { data_type => "char", is_nullable => 0, size => 18 },
  "host_initiatorname",
  { data_type => "char", is_nullable => 1, size => 64 },
  "host_internal_ip",
  { data_type => "char", is_nullable => 1, size => 15 },
  "host_hostname",
  { data_type => "char", is_nullable => 1, size => 32 },
  "etc_device_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 1,
  },
  "host_state",
  { data_type => "char", default_value => "down", is_nullable => 0, size => 32 },
  "host_prev_state",
  { data_type => "char", is_nullable => 1, size => 32 },
);
__PACKAGE__->set_primary_key("host_id");
__PACKAGE__->add_unique_constraint("host_internal_ip_UNIQUE", ["host_internal_ip"]);
__PACKAGE__->add_unique_constraint("host_mac_address_UNIQUE", ["host_mac_address"]);

=head1 RELATIONS

=head2 harddisks

Type: has_many

Related object: L<AdministratorDB::Schema::Result::Harddisk>

=cut

__PACKAGE__->has_many(
  "harddisks",
  "AdministratorDB::Schema::Result::Harddisk",
  { "foreign.host_id" => "self.host_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 hostmodel

Type: belongs_to

Related object: L<AdministratorDB::Schema::Result::Hostmodel>

=cut

__PACKAGE__->belongs_to(
  "hostmodel",
  "AdministratorDB::Schema::Result::Hostmodel",
  { hostmodel_id => "hostmodel_id" },
  { on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 processormodel

Type: belongs_to

Related object: L<AdministratorDB::Schema::Result::Processormodel>

=cut

__PACKAGE__->belongs_to(
  "processormodel",
  "AdministratorDB::Schema::Result::Processormodel",
  { processormodel_id => "processormodel_id" },
  { on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 kernel

Type: belongs_to

Related object: L<AdministratorDB::Schema::Result::Kernel>

=cut

__PACKAGE__->belongs_to(
  "kernel",
  "AdministratorDB::Schema::Result::Kernel",
  { kernel_id => "kernel_id" },
  { on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 etc_device

Type: belongs_to

Related object: L<AdministratorDB::Schema::Result::Lvm2Lv>

=cut

__PACKAGE__->belongs_to(
  "etc_device",
  "AdministratorDB::Schema::Result::Lvm2Lv",
  { lvm2_lv_id => "etc_device_id" },
  { join_type => "LEFT", on_delete => "CASCADE", on_update => "CASCADE" },
);

############################################## TO CHECK
#__PACKAGE__->might_have(
#  "cloud_cluster",
#  "AdministratorDB::Schema::Result::Cluster",
#  { "foreign.cluster_id" => "self.cloud_cluster_id" },
#  { cascade_copy => 0, cascade_delete => 0 },
#);

__PACKAGE__->belongs_to(
  "cloud_cluster",
  "AdministratorDB::Schema::Result::Cluster",
  { cluster_id => "cloud_cluster_id" },
  { join_type => "LEFT", on_delete => "CASCADE", on_update => "CASCADE" },
);


=head2 host_powersupply

Type: belongs_to

Related object: L<AdministratorDB::Schema::Result::Powersupply>

=cut

__PACKAGE__->belongs_to(
  "host_powersupply",
  "AdministratorDB::Schema::Result::Powersupply",
  { powersupply_id => "host_powersupply_id" },
  { join_type => "LEFT", on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 host_ipv4_internal

Type: belongs_to

Related object: L<AdministratorDB::Schema::Result::Ipv4Internal>

=cut

__PACKAGE__->belongs_to(
  "host_ipv4_internal",
  "AdministratorDB::Schema::Result::Ipv4Internal",
  { ipv4_internal_id => "host_ipv4_internal_id" },
  { join_type => "LEFT", on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 host_entity

Type: might_have

Related object: L<AdministratorDB::Schema::Result::HostEntity>

=cut

__PACKAGE__->might_have(
  "host_entity",
  "AdministratorDB::Schema::Result::HostEntity",
  { "foreign.host_id" => "self.host_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 hostdetails

Type: has_many

Related object: L<AdministratorDB::Schema::Result::Hostdetail>

=cut

__PACKAGE__->has_many(
  "hostdetails",
  "AdministratorDB::Schema::Result::Hostdetail",
  { "foreign.host_id" => "self.host_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 node

Type: might_have

Related object: L<AdministratorDB::Schema::Result::Node>

=cut

__PACKAGE__->might_have(
  "node",
  "AdministratorDB::Schema::Result::Node",
  { "foreign.host_id" => "self.host_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2011-04-07 12:42:45
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:iUuAjMO1BsvP5NDmOroc3g


# You can replace this text with custom content, and it will be preserved on regeneration
__PACKAGE__->has_one(
  "entitylink",
  "AdministratorDB::Schema::Result::HostEntity",
    { "foreign.host_id" => "self.host_id" },
    { cascade_copy => 0, cascade_delete => 0 });
1;

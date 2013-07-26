use utf8;
package AdministratorDB::Schema::Result::Masterimage;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

AdministratorDB::Schema::Result::Masterimage

=cut

use strict;
use warnings;

=head1 BASE CLASS: L<DBIx::Class::IntrospectableM2M>

=cut

use base 'DBIx::Class::IntrospectableM2M';

=head1 LEFT BASE CLASSES

=over 4

=item * L<DBIx::Class::Core>

=back

=cut

use base qw/DBIx::Class::Core/;

=head1 TABLE: C<masterimage>

=cut

__PACKAGE__->table("masterimage");

=head1 ACCESSORS

=head2 masterimage_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=head2 masterimage_name

  data_type: 'char'
  is_nullable: 0
  size: 64

=head2 masterimage_file

  data_type: 'char'
  is_nullable: 0
  size: 255

=head2 masterimage_desc

  data_type: 'char'
  is_nullable: 1
  size: 255

=head2 masterimage_os

  data_type: 'char'
  is_nullable: 1
  size: 64

=head2 masterimage_size

  data_type: 'bigint'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 masterimage_cluster_type_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=head2 masterimage_defaultkernel_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "masterimage_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "masterimage_name",
  { data_type => "char", is_nullable => 0, size => 64 },
  "masterimage_file",
  { data_type => "char", is_nullable => 0, size => 255 },
  "masterimage_desc",
  { data_type => "char", is_nullable => 1, size => 255 },
  "masterimage_os",
  { data_type => "char", is_nullable => 1, size => 64 },
  "masterimage_size",
  { data_type => "bigint", extra => { unsigned => 1 }, is_nullable => 0 },
  "masterimage_cluster_type_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "masterimage_defaultkernel_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 1,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</masterimage_id>

=back

=cut

__PACKAGE__->set_primary_key("masterimage_id");

=head1 RELATIONS

=head2 clusters

Type: has_many

Related object: L<AdministratorDB::Schema::Result::Cluster>

=cut

__PACKAGE__->has_many(
  "clusters",
  "AdministratorDB::Schema::Result::Cluster",
  { "foreign.masterimage_id" => "self.masterimage_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 components_provided

Type: has_many

Related object: L<AdministratorDB::Schema::Result::ComponentProvided>

=cut

__PACKAGE__->has_many(
  "components_provided",
  "AdministratorDB::Schema::Result::ComponentProvided",
  { "foreign.masterimage_id" => "self.masterimage_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 masterimage

Type: belongs_to

Related object: L<AdministratorDB::Schema::Result::Entity>

=cut

__PACKAGE__->belongs_to(
  "masterimage",
  "AdministratorDB::Schema::Result::Entity",
  { entity_id => "masterimage_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 masterimage_cluster_type

Type: belongs_to

Related object: L<AdministratorDB::Schema::Result::ClusterType>

=cut

__PACKAGE__->belongs_to(
  "masterimage_cluster_type",
  "AdministratorDB::Schema::Result::ClusterType",
  { cluster_type_id => "masterimage_cluster_type_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 masterimage_defaultkernel

Type: belongs_to

Related object: L<AdministratorDB::Schema::Result::Kernel>

=cut

__PACKAGE__->belongs_to(
  "masterimage_defaultkernel",
  "AdministratorDB::Schema::Result::Kernel",
  { kernel_id => "masterimage_defaultkernel_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "CASCADE",
  },
);

=head2 component_types

Type: many_to_many

Composing rels: L</components_provided> -> component_type

=cut

__PACKAGE__->many_to_many("component_types", "components_provided", "component_type");


# Created by DBIx::Class::Schema::Loader v0.07024 @ 2013-07-25 17:17:33
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:QaQwly127Tfs/wjyHCjdkQ

__PACKAGE__->belongs_to(
  "parent",
  "AdministratorDB::Schema::Result::Entity",
  { entity_id => "masterimage_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

1;

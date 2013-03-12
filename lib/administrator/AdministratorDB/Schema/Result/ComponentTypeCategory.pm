use utf8;
package AdministratorDB::Schema::Result::ComponentTypeCategory;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

AdministratorDB::Schema::Result::ComponentTypeCategory

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

=head1 TABLE: C<component_type_category>

=cut

__PACKAGE__->table("component_type_category");

=head1 ACCESSORS

=head2 component_type_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=head2 component_category_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "component_type_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "component_category_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</component_type_id>

=item * L</component_category_id>

=back

=cut

__PACKAGE__->set_primary_key("component_type_id", "component_category_id");

=head1 RELATIONS

=head2 component_category

Type: belongs_to

Related object: L<AdministratorDB::Schema::Result::ComponentCategory>

=cut

__PACKAGE__->belongs_to(
  "component_category",
  "AdministratorDB::Schema::Result::ComponentCategory",
  { component_category_id => "component_category_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 component_type

Type: belongs_to

Related object: L<AdministratorDB::Schema::Result::ComponentType>

=cut

__PACKAGE__->belongs_to(
  "component_type",
  "AdministratorDB::Schema::Result::ComponentType",
  { component_type_id => "component_type_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07024 @ 2013-01-31 11:35:18
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:6j3cI91M8BFDr63kUiDZ3Q


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
use utf8;
package AdministratorDB::Schema::Result::Vsphere5Repository;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

AdministratorDB::Schema::Result::Vsphere5Repository

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

=head1 TABLE: C<vsphere5_repository>

=cut

__PACKAGE__->table("vsphere5_repository");

=head1 ACCESSORS

=head2 vsphere5_repository_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "vsphere5_repository_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</vsphere5_repository_id>

=back

=cut

__PACKAGE__->set_primary_key("vsphere5_repository_id");

=head1 RELATIONS

=head2 vsphere5_repository

Type: belongs_to

Related object: L<AdministratorDB::Schema::Result::Repository>

=cut

__PACKAGE__->belongs_to(
  "vsphere5_repository",
  "AdministratorDB::Schema::Result::Repository",
  { repository_id => "vsphere5_repository_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07035 @ 2013-05-10 11:31:14
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:cmINCqeoX2rWP9R1p5uI2w

__PACKAGE__->belongs_to(
  "parent",
  "AdministratorDB::Schema::Result::Repository",
  { repository_id => "vsphere5_repository_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;

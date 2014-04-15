use utf8;
package Kanopya::Schema::Result::Vmm;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Kanopya::Schema::Result::Vmm

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

=head1 TABLE: C<vmm>

=cut

__PACKAGE__->table("vmm");

=head1 ACCESSORS

=head2 vmm_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=head2 iaas_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "vmm_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "iaas_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 1,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</vmm_id>

=back

=cut

__PACKAGE__->set_primary_key("vmm_id");

=head1 RELATIONS

=head2 vmm

Type: belongs_to

Related object: L<Kanopya::Schema::Result::Component>

=cut

__PACKAGE__->belongs_to(
  "vmm",
  "Kanopya::Schema::Result::Component",
  { component_id => "vmm_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07033 @ 2014-06-27 11:45:21
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:HIDr2U4+hAc0uldwHPj1nQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;

use utf8;
package AdministratorDB::Schema::Result::Glance;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

AdministratorDB::Schema::Result::Glance

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

=head1 TABLE: C<glance>

=cut

__PACKAGE__->table("glance");

=head1 ACCESSORS

=head2 glance_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "glance_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</glance_id>

=back

=cut

__PACKAGE__->set_primary_key("glance_id");

=head1 RELATIONS

=head2 glance

Type: belongs_to

Related object: L<AdministratorDB::Schema::Result::Component>

=cut

__PACKAGE__->belongs_to(
  "glance",
  "AdministratorDB::Schema::Result::Component",
  { component_id => "glance_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07033 @ 2013-02-04 14:01:22
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:MIWp0CYWrFQi5il8gcDxPQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;

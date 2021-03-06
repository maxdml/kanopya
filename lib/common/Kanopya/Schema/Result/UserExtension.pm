use utf8;
package Kanopya::Schema::Result::UserExtension;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Kanopya::Schema::Result::UserExtension

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

=head1 TABLE: C<user_extension>

=cut

__PACKAGE__->table("user_extension");

=head1 ACCESSORS

=head2 user_extension_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 user_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=head2 user_extension_key

  data_type: 'char'
  is_nullable: 0
  size: 32

=head2 user_extension_value

  data_type: 'char'
  is_nullable: 1
  size: 255

=cut

__PACKAGE__->add_columns(
  "user_extension_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "user_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "user_extension_key",
  { data_type => "char", is_nullable => 0, size => 32 },
  "user_extension_value",
  { data_type => "char", is_nullable => 1, size => 255 },
);

=head1 PRIMARY KEY

=over 4

=item * L</user_extension_id>

=back

=cut

__PACKAGE__->set_primary_key("user_extension_id");

=head1 UNIQUE CONSTRAINTS

=head2 C<user_id>

=over 4

=item * L</user_id>

=item * L</user_extension_key>

=back

=cut

__PACKAGE__->add_unique_constraint("user_id", ["user_id", "user_extension_key"]);

=head1 RELATIONS

=head2 user

Type: belongs_to

Related object: L<Kanopya::Schema::Result::User>

=cut

__PACKAGE__->belongs_to(
  "user",
  "Kanopya::Schema::Result::User",
  { user_id => "user_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07033 @ 2013-11-20 15:15:44
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:wm/z0CGuCK7UOBXBeG51Bw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;

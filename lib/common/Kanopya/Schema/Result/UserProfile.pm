use utf8;
package Kanopya::Schema::Result::UserProfile;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Kanopya::Schema::Result::UserProfile

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

=head1 TABLE: C<user_profile>

=cut

__PACKAGE__->table("user_profile");

=head1 ACCESSORS

=head2 user_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=head2 profile_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "user_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "profile_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</profile_id>

=item * L</user_id>

=back

=cut

__PACKAGE__->set_primary_key("profile_id", "user_id");

=head1 RELATIONS

=head2 profile

Type: belongs_to

Related object: L<Kanopya::Schema::Result::Profile>

=cut

__PACKAGE__->belongs_to(
  "profile",
  "Kanopya::Schema::Result::Profile",
  { profile_id => "profile_id" },
  { is_deferrable => 1, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

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
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:bytd0wcwnsEK+nIF1DGwmQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;

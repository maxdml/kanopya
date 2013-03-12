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

=head2 mysql5_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 1

=head2 nova_controller_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "glance_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "mysql5_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 1,
  },
  "nova_controller_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 1,
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
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 mysql5

Type: belongs_to

Related object: L<AdministratorDB::Schema::Result::Mysql5>

=cut

__PACKAGE__->belongs_to(
  "mysql5",
  "AdministratorDB::Schema::Result::Mysql5",
  { mysql5_id => "mysql5_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "CASCADE",
  },
);

=head2 nova_controller

Type: belongs_to

Related object: L<AdministratorDB::Schema::Result::NovaController>

=cut

__PACKAGE__->belongs_to(
  "nova_controller",
  "AdministratorDB::Schema::Result::NovaController",
  { nova_controller_id => "nova_controller_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "CASCADE",
  },
);


# Created by DBIx::Class::Schema::Loader v0.07025 @ 2013-02-11 15:02:05
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:99M3DoALK6JfaVnHa4Dj7Q

__PACKAGE__->belongs_to(
  "parent",
  "AdministratorDB::Schema::Result::Component",
    { "foreign.component_id" => "self.glance_id" },
    { cascade_copy => 0, cascade_delete => 1 });

1;
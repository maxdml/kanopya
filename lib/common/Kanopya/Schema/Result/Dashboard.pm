use utf8;
package Kanopya::Schema::Result::Dashboard;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Kanopya::Schema::Result::Dashboard

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

=head1 TABLE: C<dashboard>

=cut

__PACKAGE__->table("dashboard");

=head1 ACCESSORS

=head2 dashboard_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 dashboard_config

  data_type: 'longtext'
  is_nullable: 0

=head2 dashboard_service_provider_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "dashboard_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "dashboard_config",
  { data_type => "longtext", is_nullable => 0 },
  "dashboard_service_provider_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</dashboard_id>

=back

=cut

__PACKAGE__->set_primary_key("dashboard_id");

=head1 UNIQUE CONSTRAINTS

=head2 C<dashboard_service_provider_id>

=over 4

=item * L</dashboard_service_provider_id>

=back

=cut

__PACKAGE__->add_unique_constraint(
  "dashboard_service_provider_id",
  ["dashboard_service_provider_id"],
);

=head1 RELATIONS

=head2 dashboard_service_provider

Type: belongs_to

Related object: L<Kanopya::Schema::Result::ServiceProvider>

=cut

__PACKAGE__->belongs_to(
  "dashboard_service_provider",
  "Kanopya::Schema::Result::ServiceProvider",
  { service_provider_id => "dashboard_service_provider_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07033 @ 2013-11-20 15:15:44
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:p0yVPDne9PPcx1O2qzcFjA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;

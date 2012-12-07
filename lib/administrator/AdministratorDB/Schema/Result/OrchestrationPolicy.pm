use utf8;
package AdministratorDB::Schema::Result::OrchestrationPolicy;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

AdministratorDB::Schema::Result::OrchestrationPolicy

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

=head1 TABLE: C<orchestration_policy>

=cut

__PACKAGE__->table("orchestration_policy");

=head1 ACCESSORS

=head2 orchestration_policy_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "orchestration_policy_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</orchestration_policy_id>

=back

=cut

__PACKAGE__->set_primary_key("orchestration_policy_id");

=head1 RELATIONS

=head2 orchestration_policy

Type: belongs_to

Related object: L<AdministratorDB::Schema::Result::Policy>

=cut

__PACKAGE__->belongs_to(
  "orchestration_policy",
  "AdministratorDB::Schema::Result::Policy",
  { policy_id => "orchestration_policy_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 service_templates

Type: has_many

Related object: L<AdministratorDB::Schema::Result::ServiceTemplate>

=cut

__PACKAGE__->has_many(
  "service_templates",
  "AdministratorDB::Schema::Result::ServiceTemplate",
  {
    "foreign.orchestration_policy_id" => "self.orchestration_policy_id",
  },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07024 @ 2012-12-06 10:18:24
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:6dpUyqpao6BOkI/fYIhn3Q

__PACKAGE__->belongs_to(
  "parent",
  "AdministratorDB::Schema::Result::Policy",
  { policy_id => "orchestration_policy_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

1;

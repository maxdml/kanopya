use utf8;
package AdministratorDB::Schema::Result::ParamPreset;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

AdministratorDB::Schema::Result::ParamPreset

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<param_preset>

=cut

__PACKAGE__->table("param_preset");

=head1 ACCESSORS

=head2 param_preset_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 name

  data_type: 'char'
  is_nullable: 1
  size: 128

=head2 value

  data_type: 'char'
  is_nullable: 1
  size: 128

=head2 relation

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "param_preset_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "name",
  { data_type => "char", is_nullable => 1, size => 128 },
  "value",
  { data_type => "char", is_nullable => 1, size => 128 },
  "relation",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 1,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</param_preset_id>

=back

=cut

__PACKAGE__->set_primary_key("param_preset_id");

=head1 RELATIONS

=head2 param_presets

Type: has_many

Related object: L<AdministratorDB::Schema::Result::ParamPreset>

=cut

__PACKAGE__->has_many(
  "param_presets",
  "AdministratorDB::Schema::Result::ParamPreset",
  { "foreign.relation" => "self.param_preset_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 policies

Type: has_many

Related object: L<AdministratorDB::Schema::Result::Policy>

=cut

__PACKAGE__->has_many(
  "policies",
  "AdministratorDB::Schema::Result::Policy",
  { "foreign.param_preset_id" => "self.param_preset_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 relation

Type: belongs_to

Related object: L<AdministratorDB::Schema::Result::ParamPreset>

=cut

__PACKAGE__->belongs_to(
  "relation",
  "AdministratorDB::Schema::Result::ParamPreset",
  { param_preset_id => "relation" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "CASCADE",
  },
);

=head2 service_provider_managers

Type: has_many

Related object: L<AdministratorDB::Schema::Result::ServiceProviderManager>

=cut

__PACKAGE__->has_many(
  "service_provider_managers",
  "AdministratorDB::Schema::Result::ServiceProviderManager",
  { "foreign.param_preset_id" => "self.param_preset_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 workflow_defs

Type: has_many

Related object: L<AdministratorDB::Schema::Result::WorkflowDef>

=cut

__PACKAGE__->has_many(
  "workflow_defs",
  "AdministratorDB::Schema::Result::WorkflowDef",
  { "foreign.param_preset_id" => "self.param_preset_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07024 @ 2012-06-07 19:20:36
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:takhS5485kJR5l4n+okQyA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;

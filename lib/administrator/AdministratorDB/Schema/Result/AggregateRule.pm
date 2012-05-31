package AdministratorDB::Schema::Result::AggregateRule;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

AdministratorDB::Schema::Result::AggregateRule

=cut

__PACKAGE__->table("aggregate_rule");

=head1 ACCESSORS

=head2 aggregate_rule_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 aggregate_rule_label

  data_type: 'char'
  is_nullable: 1
  size: 255

=head2 aggregate_rule_service_provider_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=head2 aggregate_rule_formula

  data_type: 'char'
  is_nullable: 0
  size: 32

=head2 aggregate_rule_last_eval

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 aggregate_rule_timestamp

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 aggregate_rule_state

  data_type: 'char'
  is_nullable: 0
  size: 32

=head2 aggregate_rule_action_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 aggregate_rule_description

  data_type: 'text'
  is_nullable: 1

=head2 class_type_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "aggregate_rule_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "aggregate_rule_label",
  { data_type => "char", is_nullable => 1, size => 255 },
  "aggregate_rule_service_provider_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "aggregate_rule_formula",
  { data_type => "char", is_nullable => 0, size => 32 },
  "aggregate_rule_last_eval",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "aggregate_rule_timestamp",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "aggregate_rule_state",
  { data_type => "char", is_nullable => 0, size => 32 },
  "aggregate_rule_action_id",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "aggregate_rule_description",
  { data_type => "text", is_nullable => 1 },
  "class_type_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
);
__PACKAGE__->set_primary_key("aggregate_rule_id");

=head1 RELATIONS

=head2 aggregate_rule_service_provider

Type: belongs_to

Related object: L<AdministratorDB::Schema::Result::ServiceProvider>

=cut

__PACKAGE__->belongs_to(
  "aggregate_rule_service_provider",
  "AdministratorDB::Schema::Result::ServiceProvider",
  { service_provider_id => "aggregate_rule_service_provider_id" },
  { on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 class_type

Type: belongs_to

Related object: L<AdministratorDB::Schema::Result::ClassType>

=cut

__PACKAGE__->belongs_to(
  "class_type",
  "AdministratorDB::Schema::Result::ClassType",
  { class_type_id => "class_type_id" },
  { on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 workflow_instances

Type: has_many

Related object: L<AdministratorDB::Schema::Result::WorkflowInstance>

=cut

__PACKAGE__->has_many(
  "workflow_instances",
  "AdministratorDB::Schema::Result::WorkflowInstance",
  { "foreign.aggregate_rule_id" => "self.aggregate_rule_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2012-05-30 14:27:01
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:r37ZE08UnOnPcpTXqHCDFA


# You can replace this text with custom content, and it will be preserved on regeneration
1;

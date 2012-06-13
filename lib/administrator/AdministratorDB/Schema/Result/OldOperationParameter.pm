package AdministratorDB::Schema::Result::OldOperationParameter;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

AdministratorDB::Schema::Result::OldOperationParameter

=cut

__PACKAGE__->table("old_operation_parameter");

=head1 ACCESSORS

=head2 old_operation_parameter_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 old_operation_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=head2 name

  data_type: 'char'
  is_nullable: 0
  size: 64

=head2 value

  data_type: 'char'
  is_nullable: 0
  size: 255

=head2 tag

  data_type: 'char'
  is_nullable: 1
  size: 64

=cut

__PACKAGE__->add_columns(
  "old_operation_parameter_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "old_operation_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "name",
  { data_type => "char", is_nullable => 0, size => 64 },
  "value",
  { data_type => "char", is_nullable => 0, size => 255 },
  "tag",
  { data_type => "char", is_nullable => 1, size => 64 },
);
__PACKAGE__->set_primary_key("old_operation_parameter_id");
__PACKAGE__->add_unique_constraint("old_operation_id", ["old_operation_id", "name", "tag"]);

=head1 RELATIONS

=head2 old_operation

Type: belongs_to

Related object: L<AdministratorDB::Schema::Result::OldOperation>

=cut

__PACKAGE__->belongs_to(
  "old_operation",
  "AdministratorDB::Schema::Result::OldOperation",
  { old_operation_id => "old_operation_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-06-12 15:39:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:3rJiHCjxIVbvT1PopEzHXw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;

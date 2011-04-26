package AdministratorDB::Schema::Result::Php5;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

AdministratorDB::Schema::Result::Php5

=cut

__PACKAGE__->table("php5");

=head1 ACCESSORS

=head2 php5_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 component_instance_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=head2 php5_session_handler

  data_type: 'enum'
  default_value: 'files'
  extra: {list => ["files","memcache"]}
  is_nullable: 0

=head2 php5_session_path

  data_type: 'char'
  is_nullable: 0
  size: 127

=cut

__PACKAGE__->add_columns(
  "php5_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "component_instance_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "php5_session_handler",
  {
    data_type => "enum",
    default_value => "files",
    extra => { list => ["files", "memcache"] },
    is_nullable => 0,
  },
  "php5_session_path",
  { data_type => "char", is_nullable => 0, size => 127 },
);
__PACKAGE__->set_primary_key("php5_id");

=head1 RELATIONS

=head2 component_instance

Type: belongs_to

Related object: L<AdministratorDB::Schema::Result::ComponentInstance>

=cut

__PACKAGE__->belongs_to(
  "component_instance",
  "AdministratorDB::Schema::Result::ComponentInstance",
  { component_instance_id => "component_instance_id" },
  { on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2011-04-26 14:21:37
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Bja0kSjHg6GBj0vb2dY8nw


# You can replace this text with custom content, and it will be preserved on regeneration
1;

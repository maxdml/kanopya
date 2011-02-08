package AdministratorDB::Schema::ComponentTemplateAttr;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("+AdministratorDB::EntityBase", "Core");
__PACKAGE__->table("component_template_attr");
__PACKAGE__->add_columns(
  "template_component_id",
  { data_type => "INT", default_value => undef, is_nullable => 0, size => 8 },
  "template_component_attr_file",
  { data_type => "CHAR", default_value => undef, is_nullable => 0, size => 45 },
  "component_template_attr_field",
  { data_type => "CHAR", default_value => undef, is_nullable => 0, size => 45 },
  "component_template_attr_type",
  { data_type => "CHAR", default_value => undef, is_nullable => 0, size => 45 },
);
__PACKAGE__->set_primary_key("template_component_id");
__PACKAGE__->belongs_to(
  "template_component_id",
  "AdministratorDB::Schema::ComponentTemplate",
  { "component_template_id" => "template_component_id" },
);


# Created by DBIx::Class::Schema::Loader v0.04006 @ 2011-02-08 12:50:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:q9boJdEfXnl4DBH068z67g


# You can replace this text with custom content, and it will be preserved on regeneration
1;

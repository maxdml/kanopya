package AdministratorDB::Schema::ComponentInstalled;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("+AdministratorDB::EntityBase", "Core");
__PACKAGE__->table("component_installed");
__PACKAGE__->add_columns(
  "component_id",
  { data_type => "INT", default_value => undef, is_nullable => 0, size => 8 },
  "systemimage_id",
  { data_type => "INT", default_value => undef, is_nullable => 0, size => 8 },
);
__PACKAGE__->set_primary_key("component_id", "systemimage_id");
__PACKAGE__->belongs_to(
  "component_id",
  "AdministratorDB::Schema::Component",
  { component_id => "component_id" },
);
__PACKAGE__->belongs_to(
  "systemimage_id",
  "AdministratorDB::Schema::Systemimage",
  { systemimage_id => "systemimage_id" },
);


# Created by DBIx::Class::Schema::Loader v0.04006 @ 2010-12-22 17:26:09
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:+Gs4Orq+bO1tod/3C9llbg


# You can replace this text with custom content, and it will be preserved on regeneration
1;

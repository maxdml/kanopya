package AdministratorDB::Schema::ClusterEntity;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("cluster_entity");
__PACKAGE__->add_columns(
  "entity_id",
  { data_type => "INT", default_value => undef, is_nullable => 0, size => 8 },
  "cluster_id",
  { data_type => "INT", default_value => undef, is_nullable => 0, size => 8 },
);
__PACKAGE__->set_primary_key("entity_id", "cluster_id");
__PACKAGE__->belongs_to(
  "entity_id",
  "AdministratorDB::Schema::Entity",
  { entity_id => "entity_id" },
);


# Created by DBIx::Class::Schema::Loader v0.04006 @ 2010-07-19 01:22:21
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:J2HRiSBaAncGD8dYY24jeg


# You can replace this text with custom content, and it will be preserved on regeneration
1;

package AdministratorDB::Schema::Publicip;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("+AdministratorDB::EntityBase", "Core");
__PACKAGE__->table("publicip");
__PACKAGE__->add_columns(
  "publicip_id",
  { data_type => "INT", default_value => undef, is_nullable => 0, size => 8 },
  "ip_address",
  { data_type => "CHAR", default_value => undef, is_nullable => 0, size => 39 },
  "ip_mask",
  { data_type => "CHAR", default_value => undef, is_nullable => 0, size => 39 },
  "gateway",
  { data_type => "CHAR", default_value => undef, is_nullable => 1, size => 39 },
  "cluster_id",
  { data_type => "INT", default_value => undef, is_nullable => 1, size => 8 },
);
__PACKAGE__->set_primary_key("publicip_id");
__PACKAGE__->belongs_to(
  "cluster_id",
  "AdministratorDB::Schema::Cluster",
  { cluster_id => "cluster_id" },
);
__PACKAGE__->has_many(
  "routes",
  "AdministratorDB::Schema::Route",
  { "foreign.publicip_id" => "self.publicip_id" },
);


# Created by DBIx::Class::Schema::Loader v0.04005 @ 2010-11-02 18:11:52
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:63cWHpItsho9UFqYc88yvA


# You can replace this text with custom content, and it will be preserved on regeneration
1;

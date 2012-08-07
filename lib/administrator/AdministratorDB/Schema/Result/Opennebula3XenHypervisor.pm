package AdministratorDB::Schema::Result::Opennebula3XenHypervisor;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

AdministratorDB::Schema::Result::Opennebula3XenHypervisor

=cut

__PACKAGE__->table("opennebula3_xen_hypervisor");

=head1 ACCESSORS

=head2 opennebula3_xen_hypervisor_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "opennebula3_xen_hypervisor_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
);
__PACKAGE__->set_primary_key("opennebula3_xen_hypervisor_id");

=head1 RELATIONS

=head2 opennebula3_xen_hypervisor

Type: belongs_to

Related object: L<AdministratorDB::Schema::Result::Opennebula3Hypervisor>

=cut

__PACKAGE__->belongs_to(
  "opennebula3_xen_hypervisor",
  "AdministratorDB::Schema::Result::Opennebula3Hypervisor",
  { opennebula3_hypervisor_id => "opennebula3_xen_hypervisor_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-08-06 17:35:48
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:o7GFZWjfWl0Jvu43IoU0cw

__PACKAGE__->belongs_to(
  "parent",
  "AdministratorDB::Schema::Result::Opennebula3Hypervisor",
  { opennebula3_hypervisor_id => "opennebula3_xen_hypervisor_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

1;

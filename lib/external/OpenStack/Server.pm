#    Copyright © 2014 Hedera Technology SAS
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU Affero General Public License as
#    published by the Free Software Foundation, either version 3 of the
#    License, or (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU Affero General Public License for more details.
#
#    You should have received a copy of the GNU Affero General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

=pod
=begin classdoc

Implement Openstack API Compute operations related to servers (virtual machines)
http://docs.openstack.org/api/openstack-compute/2/content/compute_servers.html

=end classdoc
=cut

package OpenStack::Server;

use strict;
use warnings;

use General;
use OpenStack::Flavor;

=pod
=begin classdoc

Lists all available servers (i.e. vms)

=end classdoc
=cut

sub list {
    my ($class, %args) = @_;
    General::checkParams(args => \%args, required => [ 'api' ], optional => {all_tenants => 0});

    if ($args{all_tenants} eq 1) {
        my $option = 'detail?all_tenants=True';
        my $output = $args{api}->compute->servers->$option->get;
        return OpenStack::API->handleOutput(output => $output)->{servers};
    }

    my $output = $args{api}->compute->servers->get;
    return OpenStack::API->handleOutput(output => $output)->{servers};
}


=pod
=begin classdoc

Details of a specified server (i.e. vms)

=end classdoc
=cut

sub detail {
    my ($class, %args) = @_;
    General::checkParams(
        args => \%args,
        required => [ 'api', 'id' ],
        optional => {flavor_detail => 0},
    );

    my $response = $args{api}->compute->servers(id => $args{id})->get;

    $response = OpenStack::API->handleOutput(output => $response);

    if (! defined $response->{server}) {
        return $response;
    }

    if ($args{flavor_detail} eq 1) {
        my $flavor_detail = OpenStack::Flavor->detail(
                                id => $response->{server}->{flavor}->{id},
                                api => $args{api},
                            );

        $response->{server}->{flavor} = $flavor_detail;
    }

    return $response;
}

sub create {
    my ($class, %args) = @_;
    General::checkParams(
        args => \%args,
        required => [ 'api', 'flavor_id', 'instance_name' ],
        optional => {
            port_ids => [],
            volume_id => undef,
            image_id => undef,
            availability_zone => undef,
        },
    );

    if (! (defined $args{volume_id} || defined $args{image_id})) {
        throw Kanopya::Exception::Internal::MissingParam(
                  "Either param volume_id or image_id must be defined"
              );
    }

    my $networks = [];

    for my $port_id (@{$args{port_ids}}) {
        push @{$networks}, {port => $port_id};
    }

    my $route = 'os-volumes_boot';

    my $params = {
        server => {
            name => $args{instance_name},
            imageRef => $args{image_id} || "",
            flavorRef => $args{flavor_id},
            networks => $networks,
            (defined $args{availability_zone}) ? ('availability_zone' , $args{availability_zone}) : (),
        }
    };

    if (defined $args{volume_id}) {
        $params->{server}->{block_device_mapping_v2} = [{
            source_type => "volume",
            delete_on_termination => "false",
            boot_index => 0,
            uuid => $args{volume_id},
            destination_type => "volume"
        }];
    }

    my $output = $args{api}->compute->$route->post(content => $params);
    return OpenStack::API->handleOutput(output => $output);
}


sub migrate {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => [ 'api', 'id', 'hypervisor_hostname' ]);

    my $output = $args{api}->compute->servers(id => $args{id})->action->post(
               content => {
                   'os-migrateLive'  => {
                       disk_over_commit => 'false',
                       block_migration  => 'false',
                       host             => $args{hypervisor_hostname},
                    }
                }
           );
    return OpenStack::API->handleOutput(output => $output);
}


sub stop {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => [ 'api', 'id' ]);

    my $output = $args{api}->compute->servers(id => $args{id})->action->post(
                     content => { 'os-stop' => undef }
                 );
    return OpenStack::API->handleOutput(output => $output);
}

sub delete {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => [ 'api' ]);

    if (defined $args{id}) {
        my $output = $args{api}->compute->servers(id => $args{id})->delete;
        return OpenStack::API->handleOutput(output => $output);
    }

    if (defined $args{name}) {
        my $output = $args{api}->compute->servers(id => $self->id(%args))->delete;
        return OpenStack::API->handleOutput(output => $output);
    }

    throw Kanopya::Exception::Internal::MissingParam(
              "Either param id or name must be defined"
          );
}

sub id {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => [ 'api' , 'name' ]);
    my $vms = OpenStack::Server->list(api => $args{api});
    for my $vm (@$vms) {
        if ($vm->{name} eq $args{name}) {
            return $vm->{id};
        }
    }
    return undef;
}

1;
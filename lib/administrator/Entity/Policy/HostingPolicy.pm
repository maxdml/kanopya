# Copyright © 2011-2012 Hedera Technology SAS
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Maintained by Dev Team of Hedera Technology <dev@hederatech.com>.

package Entity::Policy::HostingPolicy;
use base 'Entity::Policy';

use strict;
use warnings;

use Data::Dumper;
use Log::Log4perl 'get_logger';

my $log = get_logger("");

use constant ATTR_DEF => {};

sub getAttrDef { return ATTR_DEF; }


my $merge = Hash::Merge->new('RIGHT_PRECEDENT');

sub getPolicyDef {
    my $self  = shift;
    my $class = ref($self) || $self;
    my %args  = @_;

    General::checkParams(args => \%args, optional => { 'set_mandatory' => 0 });

    %args = %{ $self->mergeValues(values => \%args) };

    # Build the host provider list
    my $providers = {};
    for my $component ($class->searchManagers(component_category => 'Cloudmanager')) {
        $providers->{$component->service_provider->id} = $component->service_provider->toJSON();
    }
    my @hostproviders = values $providers;

    my $attributes = {
        displayed  => [ 'host_provider_id', 'host_manager_id' ],
        attributes =>  {
            host_provider_id => {
                label        => 'Host provider',
                type         => 'relation',
                relation     => 'single',
                pattern      => '^\d*$',
                is_mandatory => 1,
                is_editable  => 1,
                reload       => 1,
                options      => \@hostproviders,
            },
            host_manager_id => {
                label        => "Host type",
                type         => 'relation',
                relation     => 'single',
                is_mandatory => 1,
                is_editable  => 1,
                pattern      => '^\d*$',
                reload       => 1,
            }
        }
    };

    # Complete the attributes with common ones
    $attributes = $merge->merge($self->SUPER::getPolicyDef(%args), $attributes);

    # If host_provider_id not defined, select it from host manager or
    # select the first one.
    if (not defined $args{host_provider_id}) {
        if (defined $args{host_manager_id}) {
            $args{host_provider_id} = Entity->get(id => $args{host_manager_id})->service_provider->id;
        }
        elsif (scalar @hostproviders){
            $args{host_provider_id} = $hostproviders[0]->{pk};
        }
    }

    # Build the list of host manager of the host provider
    my $manager_options = {};
    for my $component ($class->searchManagers(component_category  => 'Cloudmanager',
                                              service_provider_id => $args{host_provider_id})) {
        $manager_options->{$component->id} = $component->toJSON();
        $manager_options->{$component->id}->{label} = $component->host_type;
    }
    my @options = values $manager_options;
    $attributes->{attributes}->{host_manager_id}->{options} = \@options;

    # If the manager id not defined or the defined value not in options
    # so use the first options as selected value.
    if (not defined $args{host_manager_id} or not defined $manager_options->{$args{host_manager_id}}) {
        $args{host_manager_id} = $attributes->{attributes}->{host_manager_id}->{options}[0]->{pk};
    }

    # Get the host manager params from the selected host manager
    my $hostmanager = Entity->get(id => $args{host_manager_id});
    my $managerparams = $hostmanager->getHostManagerParams();
    for my $attrname (keys $managerparams) {
        $attributes->{attributes}->{$attrname} = $managerparams->{$attrname};
        push @{ $attributes->{displayed} }, $attrname;
    }

    $self->setValues(attributes => $attributes, values => \%args);
    return $attributes;
}

1;

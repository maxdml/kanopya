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

package WorkflowInstance;
use base 'BaseDB';

use strict;
use warnings;

use Kanopya::Exceptions;

use Data::Dumper;
use Log::Log4perl 'get_logger';

my $log = get_logger('administrator');
my $errmsg;

use constant ATTR_DEF => {
    workflow_def_id => {
        pattern      => '^.*$',
        is_mandatory => 1,
        is_extended  => 0
    },
    aggregate_rule_id => {
        pattern      => '^.*$',
        is_mandatory => 0,
        is_extended  => 0
    },
    nodemetric_rule_id => {
        pattern      => '^.*$',
        is_mandatory => 0,
        is_extended  => 0
    },
};

sub getAttrDef { return ATTR_DEF; }



sub getValues {

}

sub setSpecificValues {

}

sub getScopeParameterNameList{
    my ($self,%args) = @_;
    General::checkParams(args => \%args, required => [ 'scope_id' ]);

    my @scopeParameterList = ScopeParameter->search(hash=>{scope_id => $args{scope_id}});
    my @array = map {$_->getAttr(name => 'scope_parameter_name')} @scopeParameterList;
    return \@array;
}

sub getSpecificParams {
    my ($self,%args) = @_;

    General::checkParams(args => \%args, required => [ 'scope_name' ]);
    my $scope_name = $args{scope_name};

    my $scope    = Scope->find(hash => {scope_name => $scope_name});
    my $scope_id = $scope->getAttr(name => 'scope_id');
    my $scope_parameter_list = $self->getScopeParameterNameList(
        scope_id => $scope_id
    );

    my $all_params = $self->_parse();
    # Remove automatic params
    for my $scope_parameter (@$scope_parameter_list){
        delete $all_params->{$scope_parameter};
    };

    return $all_params;
}

sub _getSpecificValues {

}

sub _getAutomaticParams {

}

sub _getAutomaticValues {

}

sub _parse{

}
1;

#    Copyright © 2012 Hedera Technology SAS
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

Condition on combination value

@see <package>Entity::Metric::Combination::ConstantCombination</package>

=end classdoc

=cut

package Entity::NodemetricCondition;
use base Entity;

use strict;
use warnings;

use Entity::Rule::NodemetricRule;
use Entity::Metric::Combination::ConstantCombination;

use TryCatch;
my $err;

use Data::Dumper;
use Log::Log4perl "get_logger";
my $log = get_logger("");

use constant ATTR_DEF => {
    nodemetric_condition_label => {
        pattern         => '^.*$',
        is_mandatory    => 0,
        is_editable     => 1,
    },
    nodemetric_condition_service_provider_id => {
        pattern         => '^.*$',
        is_mandatory    => 1,
        is_delegatee    => 1,
        is_editable     => 1,
    },
    left_combination_id => {
        pattern         => '^.*$',
        is_mandatory    => 1,
        is_editable     => 1,
    },
    nodemetric_condition_comparator => {
        pattern         => '^(>|<|>=|<=|==)$',
        is_mandatory    => 1,
        is_editable     => 1,
    },
    right_combination_id => {
        pattern         => '^.*$',
        is_mandatory    => 1,
        is_editable     => 1,
    },
    nodemetric_condition_formula_string => {
        pattern         => '^.*$',
        is_mandatory    => 0,
        is_editable     => 1,
    },
};

sub getAttrDef { return ATTR_DEF; }

sub methods {
    return {
        updateName => {
            description => 'updateName',
        },
        getDependencies => {
            description => 'return dependencies tree for this object',
        },
    };
}


=pod

=begin classdoc

@constructor

Create a new instance of the class.
Transforms thresholds into ConstantCombinations
Update formula_string with toString() methods and the label if not provided in attribute.

@return a class instance

=end classdoc

=cut

sub new {
    my $class = shift;
    my %args = @_;

    if ((! defined $args{right_combination_id}) && defined $args{nodemetric_condition_threshold}  ) {
        my $comb =  Entity::Metric::Combination::ConstantCombination->new (
                        service_provider_id => $args{nodemetric_condition_service_provider_id},
                        value => $args{nodemetric_condition_threshold}
                    );
        delete $args{nodemetric_condition_threshold};
        $args{right_combination_id} = $comb->id;
    }

    if ((! defined $args{left_combination_id}) && defined $args{nodemetric_condition_threshold}  ) {
        my $comb =  Entity::Metric::Combination::ConstantCombination->new (
                        service_provider_id => $args{nodemetric_condition_service_provider_id},
                        value => $args{nodemetric_condition_threshold}
                    );
        delete $args{nodemetric_condition_threshold};
        $args{left_combination_id} = $comb->id;
    }


    my $self = $class->SUPER::new(%args);

    my $toString = $self->toString();

    $self->setAttr (name=>'nodemetric_condition_formula_string', value => $toString);
    if(!defined $args{nodemetric_condition_label} || $args{nodemetric_condition_label} eq ''){
        $self->setAttr(name=>'nodemetric_condition_label', value => $toString);
    }
    $self->save();
    return $self;
}

sub label {
    my $self = shift;
    return $self->nodemetric_condition_label;
}


=pod

=begin classdoc

set label to human readable version of the formula

=end classdoc

=cut

sub updateName {
    my $self    = shift;

    $self->setAttr(name => 'nodemetric_condition_label', value => $self->toString);
    $self->save;
}

=pod

=begin classdoc

Transform formula to human readable String

@return human readable String of the formula

=end classdoc

=cut

sub toString {
    my $self = shift;

    # Not used yet due to bad Combination::computeUnit() behavior (see also AggregateCondition::toString())
    my $unit = '';
    if ((ref $self->right_combination) eq 'Entity::Metric::Combination::ConstantCombination') {
        my $left_unit = $self->left_combination->combination_unit;
        if ($left_unit && (($left_unit ne '?') || ($left_unit ne '-'))) {
            $unit = $left_unit;
        }
    }

    return  $self->left_combination->combination_formula_string.' '
           .$self->nodemetric_condition_comparator.' '
           .$self->right_combination->combination_formula_string;
};


=pod

=begin classdoc

Evaluate the condition. Call evaluation of both dependant combinations then evaluate the condition

@param node Node instance on which the condition will be analyzed

@return 1 if condition is true, 0 if condition is false

=end classdoc

=cut

sub evaluate {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => ['node']);

    if (exists $args{memoization}->{$self->id}->{$args{node}->id}) {
        return $args{memoization}->{$self->id}->{$args{node}->id};
    }

    my $comparator        = $self->nodemetric_condition_comparator;
    my $left_combination  = $self->left_combination;
    my $right_combination = $self->right_combination;

    my $left_value  = $left_combination->evaluate(%args);
    my $right_value = $right_combination->evaluate(%args);

    my $val;
    if ((not defined $left_value) || (not defined $right_value)) {
        $val = undef;
    }
    else {
        $val = (eval $left_value.$comparator.$right_value) ? 1 : 0;
    }

    if (defined $args{memoization}) {
        $args{memoization}->{$self->id}->{$args{node}->id} = $val;
    }

    return $val;
}


=pod

=begin classdoc

Find all the rules which depends on the NodemetricCondition

@return array of rules

=end classdoc

=cut

sub getDependentRules {
    my $self = shift;
    my @servicerules = Entity::Rule::NodemetricRule->search(hash => {
                    service_provider_id => $self->nodemetric_condition_service_provider_id
                });

    my @rules;
    my $id = $self->id;
    RULE:
    for my $rule (@servicerules) {
        my @rule_dependant_condition_ids = $rule->getDependentConditionIds;
        for my $condition_id (@rule_dependant_condition_ids) {
            if ($id == $condition_id) {
                push @rules, $rule;
                next RULE;
            }
        }
    }
    return @rules;
}


=pod

=begin classdoc

Find all the rules which depends on the NodemetricCondition

@return hashref of rule_names

=end classdoc

=cut

sub getDependencies {
    my $self = shift;

    my @rules = $self->getDependentRules;

    my %dependencies;
    for my $rule (@rules) {
        $dependencies{$rule->rule_name} = {};
    }
    return \%dependencies;
}


=pod

=begin classdoc

Delete instance and delete dependant object on cascade.

=end classdoc

=cut

sub delete {
    my $self = shift;
    my @rules = Entity::Rule::NodemetricRule->search(hash => {
                    service_provider_id => $self->nodemetric_condition_service_provider_id
                });

    my $id = $self->id;
    RULE:
    while(@rules) {
        my $rule = pop @rules;
        my @rule_dependant_condition_ids = $rule->getDependentConditionIds;
        for my $condition_id (@rule_dependant_condition_ids) {
            if ($id == $condition_id) {
                $rule->delete();
                next RULE;
            }
        }
    }
    my $comb_left  = $self->left_combination;
    my $comb_right = $self->right_combination;
    $self->SUPER::delete();
    $comb_left->deleteIfConstant();
    $comb_right->deleteIfConstant();
}


=pod

=begin classdoc

Search indicators used by the NodemetricCondition

@return array of indicator ids

=end classdoc

=cut

sub getDependentIndicatorIds {
    my $self = shift;
    return ($self->left_combination->getDependentIndicatorIds(), $self->right_combination->getDependentIndicatorIds());
}


=pod

=begin classdoc

Update instance attributes. Manage update of related objects and formula_string.

=end classdoc

=cut

sub update {
    my ($self, %args) = @_;
    my $service_provider_id = $args{nodemetric_condition_service_provider_id} ?
                                  $args{nodemetric_condition_service_provider_id} :
                                  $self->nodemetric_condition_service_provider_id ;


    my $two_attributes = 0;
    if (defined $args{nodemetric_condition_threshold}) { $two_attributes++; }
    if (defined $args{left_combination_id}) { $two_attributes++; }
    if (defined $args{right_combination_id}) { $two_attributes++; }

    if ( $two_attributes == 0) {
        my $rep = $self->SUPER::update (%args);
        $rep->updateFormulaString;
        return $rep;
    }

    if ( $two_attributes != 2) {
        my $error = 'When updating nodemetric condition, have to specify two attributes between '.
                    'nodemetric_condition_threshold, left_combination_id and right_combination';
        throw Kanopya::Exception::Internal::WrongValue(error => $error);
    }

    my $old_left_combination = $self->left_combination;
    my $old_right_combination = $self->right_combination;

    if (! defined $args{left_combination_id}) {
        my $new_left_combination = Entity::Metric::Combination::ConstantCombination->new (
                                       service_provider_id => $service_provider_id,
                                       value => $args{nodemetric_condition_threshold}
                                   );
        delete $args{nodemetric_condition_threshold};
        $args{left_combination_id} = $new_left_combination->id;
    }
    elsif (! defined $args{right_combination_id}) {
        my $new_right_combination = Entity::Metric::Combination::ConstantCombination->new (
                                        service_provider_id => $service_provider_id,
                                        value => $args{nodemetric_condition_threshold}
                                    );
        delete $args{nodemetric_condition_threshold};
        $args{right_combination_id} = $new_right_combination->id;
    }
    else {
        # do nothing, update will just replace both ids with right and left combination ids
    }

    my $rep = $self->SUPER::update (%args);
    $rep->updateFormulaString;
    $old_left_combination->deleteIfConstant();
    $old_right_combination->deleteIfConstant();
    return $rep;
}

=pod

=begin classdoc

Clones the condition and all related objects.
Links clones to the specified service provider. Only clones objects that do not exist in service provider.

@param dest_service_provider_id id of the service provider where to import the clone

@return clone object

=end classdoc

=cut

sub clone {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => ['dest_service_provider_id']);

    my $attrs_cloner = sub {
        my %args = @_;
        for my $operand ('left_combination', 'right_combination') {
            try {
                $args{attrs}->{$operand . '_id'} = $self->$operand->clone(
                    dest_service_provider_id => $args{attrs}->{nodemetric_condition_service_provider_id}
                )->id;
            }
            catch (Kanopya::Exception $err) {
                $err->rethrow();
            }
            catch ($err) {
                throw Kanopya::Exception::Internal(error => "$err");
            }
        }
        return $args{attrs};
    };

    return $self->_importToRelated(
        dest_obj_id         => $args{'dest_service_provider_id'},
        relationship        => 'nodemetric_condition_service_provider',
        label_attr_name     => 'nodemetric_condition_label',
        attrs_clone_handler => $attrs_cloner
    );
}


=pod

=begin classdoc

Compute and update the instance formula_string attribute and call the update of the formula_string
attribute of the objects which depend on the instance.

=end classdoc

=cut


sub updateFormulaString {
    my $self = shift;

    $self->setAttr (name=>'nodemetric_condition_formula_string', value => $self->toString());
    $self->save ();

    my @rules = $self->getDependentRules;

    for my $rule (@rules) {
        $rule->updateFormulaString;
    }
}

1;

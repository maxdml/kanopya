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
package AggregateCondition;

use strict;
use warnings;
use TimeData::RRDTimeData;
use AggregateCombination;

use base 'BaseDB';

use constant ATTR_DEF => {
    aggregate_condition_id               =>  {pattern       => '^.*$',
                                 is_mandatory   => 0,
                                 is_extended    => 0,
                                 is_editable    => 0},
    aggregate_combination_id     =>  {pattern       => '^.*$',
                                 is_mandatory   => 1,
                                 is_extended    => 0,
                                 is_editable    => 1},
    comparator =>  {pattern       => '^(>|<|>=|<=|==)$',
                                 is_mandatory   => 1,
                                 is_extended    => 0,
                                 is_editable    => 1},
    threshold =>  {pattern       => '^.*$',
                                 is_mandatory   => 1,
                                 is_extended    => 0,
                                 is_editable    => 1},
    state              =>  {pattern       => '(enabled|disabled)$',
                                 is_mandatory   => 1,
                                 is_extended    => 0,
                                 is_editable    => 1},
    time_limit         =>  {pattern       => '^.*$',
                                 is_mandatory   => 1,
                                 is_extended    => 0,
                                 is_editable    => 1},
    last_eval          =>  {pattern       => '^.*$',
                                 is_mandatory   => 0,
                                 is_extended    => 0,
                                 is_editable    => 1},
};

sub getAttrDef { return ATTR_DEF; }


=head2 toString

    desc: return a string representation of the entity

=cut

sub toString {
    my $self = shift;
    my $aggregate_combination_id   = $self->getAttr(name => 'aggregate_combination_id');
    my $comparator                 = $self->getAttr(name => 'comparator');
    my $threshold                  = $self->getAttr(name => 'threshold');
    
    return AggregateCombination->get('id'=>$aggregate_combination_id)->toString().$comparator.$threshold;
}

sub eval{
    my $self = shift;
    
    my $aggregate_combination_id    = $self->getAttr(name => 'aggregate_combination_id');
    my $comparator      = $self->getAttr(name => 'comparator');
    my $threshold       = $self->getAttr(name => 'threshold');

    my $agg_combination = AggregateCombination->get('id' => $aggregate_combination_id);
    my $value = $agg_combination->calculate(); 
    
    my $evalString = $value.$comparator.$threshold;
    
    if(eval $evalString){
        print $evalString."=> 1\n";        
        $self->setAttr(name => 'last_eval', value => 1);
        $self->save();
        return 1;
    }else{
        print $evalString."=> 0\n";
        $self->setAttr(name => 'last_eval', value => 0);
        $self->save();
        return 0;
    }
    
}


1;

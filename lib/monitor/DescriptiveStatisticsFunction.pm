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

Provide aggregation (statistic descriptive) functions.
Extand module Statistics::Descriptive::Full.
Implement the coeffiction of variation function (coefficientOfVariation) and the compute of data outide
mean +- 4*sigma (dataOut)

=end classdoc
=cut

package DescriptiveStatisticsFunction;

use strict;
use warnings;

use Statistics::Descriptive;
use base 'Statistics::Descriptive::Full';


# logger
#use Log::Log4perl "get_logger";
#my $log = get_logger("descriptiveStatisticsFunction");


sub new {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::new(%args);

    return $self;
}


=pod
=begin classdoc

Compute the coefficient of variation (en.wikipedia.org/wiki/Coefficient_of_variation).

@return coefficient of variation value

=end classdoc
=cut

sub coefficientOfVariation {
    my $self = shift;
    return $self->standard_deviation () / $self->mean();
}


=pod
=begin classdoc

Compute the number of data outside the interval [mean - 4 * sigma, mean + 4 * sigma]

@return number of data outside the interval [mean - 4 * sigma, mean + 4 * sigma]

=end classdoc
=cut

sub dataOut{
    my $self        = shift;
    my $data        = $self->_data();

    my $coef        = 4;

    my $std         = $self->standard_deviation();
    my $mean        = $self->mean();

    my $outOfRange  = 0;

    foreach my $element (@{$data}) {
        if (
           ($element > $mean + $coef*$std)
        || ($element < $mean - $coef*$std)
        ){
            $outOfRange++;
        }
    }
    if($self->count() == 0){
        return 0;
    }
    return $outOfRange/($self->count());
};


=pod
=begin classdoc

Rename original standard_deviation function

@return standard deviation value

=end classdoc
=cut

sub std{
    my $self = shift;
    return $self->standard_deviation();
}
1;
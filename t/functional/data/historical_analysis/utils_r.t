=head1 SCOPE

Utils::R

=head1 PRE-REQUISITE

=cut

use strict;
use warnings;
use Test::More 'no_plan';
use Test::Exception;

use Utils::R;

use Statistics::R;

# The data used for the test
my @data = (5, 12, 13, 15, 13, 12, 5, 12, 13, 15, 13, 12, 5, 12, 13, 15, 13, 12);

# Frequency of the previous dataset
my $freq = 6;

# Horizon to compute
my $hor  = 5;

# Expected values (manually computed from R)
my @expected_values = (5, 12, 13, 15, 13);

main();

sub main {
    noExecutionBugInPrintPrettyRForecast();
    testConvertRForecast();
}

sub testConvertRForecast {
    lives_ok {
        # Create a communication bridge with R and start R
        my $R = Statistics::R->new();
    
        # Initialize the dataset
        $R->set('dataset', \@data);

        # Run R commands
        $R->run(q`library(forecast);`                                            # Load the forecast package
                . qq`time_serie <- ts(dataset, start=1, frequency=$freq);`       # Create the time serie
                . qq`forecast <- forecast(auto.arima(time_serie), h=$hor);`);    # fit and forecast with arima
    
        # Return the forecast computed by R
        my $R_forecast = $R->get('forecast');

        my @forecast = @{Utils::R->convertRForecast(R_forecast_ref => $R_forecast,
                                                    freq           => $freq,
                        )};

        if (scalar(@expected_values) == scalar(@forecast)) {
            for my $index (0..scalar(@expected_values) - 1) {
                unless ($forecast[$index] == $expected_values[$index]) {
                    die ("Incorrect value returned in the forecast ($expected_values[$index] expected, 
                          got $forecast[$index])");
                }
            }
        }
        else {
            die ("Wrong horizon used by R");
        }

   } 'Testing convertRForecast method'
}

sub noExecutionBugInPrintPrettyRForecast {
    lives_ok {
        # Create a communication bridge with R and start R
        my $R = Statistics::R->new();
    
        # Initialize the dataset
        $R->set('dataset', \@data);

        # Run R commands
        $R->run(q`library(forecast);`                                            # Load the forecast package
                . qq`time_serie <- ts(dataset, start=1, frequency=$freq);`       # Create the time serie
                . qq`forecast <- forecast(auto.arima(time_serie), h=$hor);`);    # fit and forecast with arima
    
        # Return the forecast computed by R
        my $R_forecast = $R->get('forecast');

        Utils::R->printPrettyRForecast(R_forecast_ref => $R_forecast,
                                       freq           => $freq,
                                       no_print       => 1,
                  );
   } 'Testing printPrettyRForecast method (no execution bug)'
}
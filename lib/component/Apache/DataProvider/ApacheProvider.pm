#    Copyright © 2011 Hedera Technology SAS
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

DataProvider::ApacheProvider is used to retrieve apache status values from a specific host.
Apache status var names correspond to strings before ":" displayed in apache status page
(see http://$host/server-status?auto)

# Creates provider
my $provider = DataProvider::ApacheProvider->new( $host );

# Retrieve data
my $var_map = { 'var_name' => '<apache status var name>', ... };
$provider->retrieveData( var_map => $var_map );

=end classdoc
=cut

package DataProvider::ApacheProvider;

use base 'DataProvider';

use strict;
use warnings;
use Log::Log4perl "get_logger";
my $log = get_logger("");


=pod
=begin classdoc

@constructor

Instanciate ApacheProvider instance to provide apache stat from a specific host

@param host ip of host

@return ApacheProvider instance

=end classdoc
=cut

sub new {
    my $class = shift;
    my %args = @_;

    my $self = {};
    bless $self, $class;

    my $host = $args{host};
    my $ip = $host->adminIp();
    my $component = $args{component};

    # Retrieve the apache port which doesn't use ssl
    my $net_conf = $component->getNetConf();
    my ($port, $protocols);
    while(($port, $protocols) = each %$net_conf) {
        last if (0 == grep {$_ eq 'ssl'} @$protocols );
    }

    my $cmd =     'curl -A "mozilla/4.0 (compatible; cURL 7.10.5-pre2; Linux 2.4.20)"';
    $cmd .=        ' -m 12 -s -L -k -b /tmp/bbapache_cookiejar.curl';
    $cmd .=        ' -c /tmp/bbapache_cookiejar.curl';
    $cmd .=        ' -H "Pragma: no-cache" -H "Cache-control: no-cache"';
    $cmd .=        ' -H "Connection: close"';
    $cmd .=        " $ip:$port/server-status?auto";

    $self->{_cmd} = $cmd;
    $self->{_host} = $host;
    $self->{_ip} = $ip;

    return $self;
}


=pod
=begin classdoc

Retrieve a set of apache status var value

@param var_map hash ref : required  var { var_name => oid }

@return [0] : time when data was retrived or [1] : resulting hash ref { var_name => value }

=end classdoc
=cut

sub retrieveData {
    my $self = shift;
    my %args = @_;

    my $var_map = $args{var_map};

    my @OID_list = values( %$var_map );
    my $time =time();

    my $server_status = qx( $self->{_cmd} );
    
    if ( $server_status eq "" ) {
        die "No response from remote host : '$self->{_ip}' ";
    }
    if ( $server_status =~ "403 Forbidden" ) {
        die "You don't have permission to access $self->{_ip}/server_status";
    }
    

    my %values = ();
    while ( my ($name, $oid) = each %$var_map ) {
        my $value;
        if ($server_status =~ /$oid: ([\d|\.]+)/i ) {
            $value = $1 || 0;
        }
        else
        {
            $value = undef;
            $log->warn("oid '$oid' not found in Apache status (maybe you forgot to activate ExtendedStatus in mod_status conf).");
        }
        $values{$name} = $value;
    }
    
    return ($time, \%values);
}

# destructor
sub DESTROY {
}

1;

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

VirtualProvider is used to retrieve Virtual status values from a specific host.
Virtual status var names correspond to strings in virtual_nodes.adm

# Creates provider
my $provider = VirtualProvider->new( $host );

# Retrieve data
my $var_map = { 'var_name' => '<Virtual status var name>', ... };
$provider->retrieveData( var_map => $var_map );


=end classdoc
=cut

package DataProvider::VirtualProvider;

use strict;
use warnings;
use base 'DataProvider';
use Log::Log4perl "get_logger";
my $log = get_logger("");

=pod
=begin classdoc

@constructor

Instanciate VirtualProvider instance to provide Virtual stat from a specific host

@param host Entity::Host: host object

@return VirtualProvider instance

=end classdoc
=cut

sub new {
    my $class = shift;
    my %args = @_;

    my $self = {};
    bless $self, $class;

    $self->{_host} = $args{host};
    $self->{_ip} = $args{host}->adminIp;

    return $self;
}


=pod
=begin classdoc

Retrieve a set of snmp var value

@param var_map hash ref required  var { var_name => oid }

@return [0] time when data was retrived [1] resulting hash ref { var_name => value }

=end classdoc
=cut

sub retrieveData {
    my $self = shift;
    my %args = @_;

    my $var_map = $args{var_map};

    my @OID_list = values( %$var_map );
    my $time = time();

    my %values = ();
    
    open NODES, "</tmp/virtual_nodes.adm";
    while (<NODES>) {
        my $line = $_;
        chomp($line);
        my ($ip, $data) = split " ", $line;
        if ($ip eq $self->{_ip}) {
            
            my $load;
            if ($data =~ /LOAD:([\d\.]+)/) {
                $load = $1 || 0;
            }
            else
            {
                $load = undef;
                $log->warn("LOAD not found in virtual nodes file for '$ip'.");
            }
            
            while ( my ($name, $oid) = each %$var_map ) {
                my $value = $self->compute( var => $oid, load => $load );
                $values{$name} = $value;
            }
            
            last;
        }
    }
    close NODES;
    
    return ($time, \%values);
}

sub compute {
    my $self = shift;
    my %args = @_;
    
    my $var = $args{var};
    my $load =$args{load};
    
    if ($var =~ "CPU") {    
        my $idle;
        if ($load >= 410) {
            $idle = 0;
        } else {
            $idle = 100 - int ($load / 4.1);
            $idle += ( rand() * 10 ) - 5;
            $idle = $idle < 0 ? 0 : $idle > 90 ? 90 + ( rand() * 10 ) - 5 : $idle;
        }
        my $rest = 95 - $idle;
        my $syst = $rest / ( 4 + rand() );
        my $user = $rest - $syst;
        
        my %res = ( 'idleCPU' => $idle, 'systCPU' => $syst, 'userCPU' => $user);
        return $res{$var};
    } elsif ($var eq "reqPerSec") {
        return $load;
    }
    
    die "Error: no definition to compute virtual var '$args{var}'";
}

# destructor
sub DESTROY {
}

1;

package Entity::Component::Storage;

use strict;
use Data::Dumper;
use base "Entity::Component";


# contructor

sub new {
    my $class = shift;
    my %args = @_;

print Dumper $class;
    my $self = $class->SUPER::new( %args );
    return $self;
}


1;

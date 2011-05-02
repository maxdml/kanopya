package EEntity::EComponent::ETool::EPhp5;

use strict;
use Template;
use String::Random;
use base "EEntity::EComponent::ETool";
use Log::Log4perl "get_logger";

my $log = get_logger("executor");
my $errmsg;

# contructor

sub new {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::new( %args );
    return $self;
}

# generate configuration files on node
sub configureNode {
	my $self = shift;
	my %args = @_;

	my $conf = $self->_getEntity()->getConf();

	# Generation of php.ini
	my $data = { 
				session_handler => $conf->{php5_session_handler},
				session_path => $conf->{php5_session_path},
				};
	if ( $data->{session_handler} eq "memcache" ) { # This handler needs specific configuration (depending on master node)
		my $masternodeip = 	$args{cluster}->getMasterNodeIp() ||
							$args{motherboard}->getInternalIP()->{ipv4_internal_address}; # current node is the master node
		my $port = '11211'; # default port of memcached TODO: retrieve memcached port using component
		$data->{session_path} = "tcp://$masternodeip:$port";
	}
	$self->generateFile( econtext => $args{econtext}, mount_point => $args{mount_point},
						 template_dir => "/templates/components/php5",
						 input_file => "php.ini.tt", output => "/php5/apache2/php.ini", data => $data);
}

sub addNode {
	my $self = shift;
	my %args = @_;
		
	$self->configureNode(%args);
}


1;

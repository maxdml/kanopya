# Keepalived1.pm -Keepalive (load balancer) component (Adminstrator side)
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

# Maintained by Dev Team of Hedera Technology <dev@hederatech.com>.
# Created 22 august 2010

package Entity::Component::Keepalived1;
use base "Entity::Component";

use strict;
use warnings;

use Kanopya::Exceptions;
use Log::Log4perl "get_logger";
use Data::Dumper;

use EFactory;

my $log = get_logger("");
my $errmsg;

use constant ATTR_DEF => {
    notification_email_from => {
        label           => 'Email from',
        type            => 'string',
        pattern         => '^.*$',
        is_mandatory    => 1,
        is_editable     => 1
    },
    notification_email      => {
        label           => 'Notification email',
        type            => 'string',
        pattern         => '^.*$',
        is_mandatory    => 1,
        is_editable     => 1
    },
    daemon_method           => {
        label           => 'Daemon method',
        type            => 'enum',
        options         => ['master','backup','both'],
        pattern         => '^.*$',
        is_mandatory    => 1,
        is_editable     => 1
    },
    smtp_connect_timeout    => {
        label           => 'Connect timeout',
        type            => 'string',
        pattern         => '^[0-9]+$',
        is_mandatory    => 1,
        is_editable     => 1
    },
    smtp_server             => {
        label           => 'SMTP server',
        type            => 'string',
        pattern         => '^.*$',
        is_mandatory    => 1,
        is_editable     => 1
    },
    lvs_id                  => {
        label           => 'Lvs identificator',
        type            => 'string',
        pattern         => '^.*$',
        is_mandatory    => 1,
        is_editable     => 0
    },
    iface                   => {
        label           => 'Interface',
        type            => 'string',
        pattern         => '^.*$',
        is_mandatory    => 1,
        is_editable     => 0
    }
};
sub getAttrDef { return ATTR_DEF; }

=head2 getVirtualservers
    
    Desc : return virtualservers list .
        
    return : array ref containing hasf ref virtualservers 

=cut

sub getVirtualservers {
    my $self = shift;
        
    my $virtualserver_rs = $self->{_dbix}->keepalived1_virtualservers->search();
    my $result = [];
    while(my $vs = $virtualserver_rs->next) {
        my $hashvs = {};
        $hashvs->{virtualserver_id} = $vs->get_column('virtualserver_id');
        $hashvs->{virtualserver_ip} = $vs->get_column('virtualserver_ip');
        $hashvs->{virtualserver_port} = $vs->get_column('virtualserver_port');
        $hashvs->{virtualserver_lbalgo} = $vs->get_column('virtualserver_lbalgo');
        $hashvs->{virtualserver_lbkind} = $vs->get_column('virtualserver_lbkind');
        push @$result, $hashvs;
    }
    $log->debug("returning ".scalar @$result." virtualservers");
    return $result;
}

=head2 getRealserverId  

    Desc : This method return realserver id given a virtualserver_id and a realserver_ip
    args: virtualserver_id, realserver_ip
        
    return : realserver_id

=cut

sub getRealserverId {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => ['realserver_ip',
                                                      'virtualserver_id']);
    
    my $virtualserver = $self->{_dbix}->keepalived1_virtualservers->find($args{virtualserver_id});
    $log->debug("Virtualserver found with id <$args{virtualserver_id}>");
    my $realserver = $virtualserver->keepalived1_realservers->search({ realserver_ip => $args{realserver_ip} })->single;
    $log->debug("Realserver found with ip <$args{realserver_ip}>");
    $log->debug("Returning realserver_id <".$realserver->get_column('realserver_id').">");
    return $realserver->get_column('realserver_id');
}

=head2 addVirtualserver
    
    Desc : This method add a new virtual server entry into keepalived configuration.
    args: virtualserver_ip, virtualserver_port, virtualserver_lbkind, virtualserver_lbalgo
        
    return : virtualserver_id added

=cut

sub addVirtualserver {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => ['virtualserver_ip',
                                                      'virtualserver_port',
                                                      'virtualserver_lbkind',
                                                      'virtualserver_lbalgo']);
    
    my $virtualserver_rs = $self->{_dbix}->keepalived1_virtualservers;
    my $row = $virtualserver_rs->create(\%args);
    $log->info("New virtualserver added with ip $args{virtualserver_ip} and port $args{virtualserver_port}");
    return $row->get_column("virtualserver_id");
}

=head2 addRealserver
    
    Desc : This function add a new real server associated a virtualserver.
    args: virtualserver_id, realserver_ip, realserver_port,realserver_checkport , 
        realserver_checktimeout, realserver_weight 
    
    return :  realserver_id

=cut

sub addRealserver {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => ['virtualserver_id',
                                                      'realserver_ip',
                                                      'realserver_port',
                                                      'realserver_checkport',
                                                      'realserver_checktimeout',
                                                      'realserver_weight']);
    
    $log->debug("New real server try to be added on virtualserver_id <$args{virtualserver_id}>");
    my $realserver_rs = $self->{_dbix}->keepalived1_virtualservers->find($args{virtualserver_id})->keepalived1_realservers;

    my $row = $realserver_rs->create(\%args);
    $log->info("New real server <$args{realserver_ip}> <$args{realserver_port}> added");
    return $row->get_column('realserver_id');
}

=head2 removeVirtualserver
    
    Desc : This function a delete virtual server and all real servers associated.
    args: virtualserver_id
        
    return : ?

=cut

sub removeVirtualserver {
    my $self = shift;
    my %args  = @_;
    
    General::checkParams(args => \%args, required => ['virtualserver_id']);
    
    $log->debug("Trying to delete virtualserver with id <$args{virtualserver_id}>");
    return $self->{_dbix}->keepalived1_virtualservers->find($args{virtualserver_id})->delete;
}

=head2 removeRealserver
    
    Desc : This function remove a real server from a virtualserver.
    args: virtualserver_id, realserver_id
        
    return : 

=cut

sub removeRealserver {
    my $self = shift;
    my %args  = @_;
    
    General::checkParams(args => \%args, required => ['virtualserver_id',
                                                      'realserver_id']);
    
    $log->debug("Trying to delete realserver with id <$args{realserver_id}>");
    return $self->{_dbix}->keepalived1_virtualservers->find($args{virtualserver_id})->keepalived1_realservers->find($args{realserver_id})->delete;
}

sub setRealServerWeightToZero {
    my $self = shift;
    my %args = @_;
    
    General::checkParams(args => \%args, require => ['realserver_id',
                                                    'virtualserver_id']);
    
    $log->debug("Setting realserver <$args{realserver_id}> weight to 0");
    my $virtualServer   = $self->{_dbix}->keepalived1_virtualservers->find($args{virtualserver_id});
    my $realServer      = $virtualServer->keepalived1_realservers->find($args{realserver_id});
    $realServer->set_column(realserver_weight => 0);
    $realServer->update();
}

# return a data structure to pass to the template processor for ipvsadm file
sub getTemplateDataIpvsadm {
    my $self = shift;
    my $data = {};
    my $keepalived = $self->{_dbix};
    $data->{daemon_method} = $keepalived->get_column('daemon_method');
    $data->{iface} = $keepalived->get_column('iface');
    return $data;      
}

# return a data structure to pass to the template processor for keepalived.conf file 
sub getTemplateDataKeepalived {
    my $self = shift;
    my $data = {};
    my $keepalived = $self->{_dbix};
    $data->{notification_email} = $keepalived->get_column('notification_email');
    $data->{notification_email_from} = $keepalived->get_column('notification_email_from');
    $data->{smtp_server} = $keepalived->get_column('smtp_server');
    $data->{smtp_connect_timeout} = $keepalived->get_column('smtp_connect_timeout');
    $data->{lvs_id} = $keepalived->get_column('lvs_id');
    $data->{virtualservers} = [];
    my $virtualservers = $keepalived->keepalived1_virtualservers;
    
    while (my $vs = $virtualservers->next) {
        my $record = {};
        $record->{ip} = $vs->get_column('virtualserver_ip');
        $record->{port} = $vs->get_column('virtualserver_port');
        $record->{lb_algo} = $vs->get_column('virtualserver_lbalgo');
        $record->{lb_kind} = $vs->get_column('virtualserver_lbkind');
            
        $record->{realservers} = [];
        
        my $realservers = $vs->keepalived1_realservers->search();
        while(my $rs = $realservers->next) {
            push @{$record->{realservers}}, { 
                ip => $rs->get_column('realserver_ip'),
                port => $rs->get_column('realserver_port'),
                weight => $rs->get_column('realserver_weight'),
                check_port => $rs->get_column('realserver_checkport'),
                check_timeout => $rs->get_column('realserver_checktimeout'),
            }; 
        }
        push @{$data->{virtualservers}}, $record;
    }
    return $data;      
}

sub getBaseConfiguration {
    return {
        daemon_method           => 'both',
        iface                   => 'eth0',
        notification_email      => 'admin@mycluster.com',
        notification_email_from => 'keepalived@mycluster.com',
        smtp_server             => '127.0.0.1',
        smtp_connect_timeout    => 30,
        lvs_id                  => 'MAIN_LVS' 
    };
}

sub getPuppetDefinition {
    my ($self, %args) = @_;

    return "class { 'kanopya::keepalived': }\n";
}

sub readyNodeRemoving {
    my $self = shift;
    my %args = @_;
 
    General::checkParams(args => \%args, required => ['host_id']);
    
    my $host = Entity::Host->find(hash => {host_id => $args{host_id}});
    
    my $EKeepalived = EFactory::newEEntity(data => $self);

    my $context = $EKeepalived->getEContext();
    my $result = $context->execute(command => "ipvsadm -L -n | grep " . $host->adminIp);
    my @result = split(/\n/, $result->{stdout});
    foreach my $line (@result) {
        my @cols = split(/[\t| ]+/, $line);
        if ($cols[5] > 0 || $cols[6] > 0) {
            return 0;
        }
    }
    return 1;
}

1;

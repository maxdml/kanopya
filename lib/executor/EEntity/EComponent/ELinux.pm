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
package EEntity::EComponent::ELinux;
use base 'EEntity::EComponent';

use strict;
use warnings;
use Log::Log4perl 'get_logger';
use Data::Dumper;
use Message;
use EEntity;

my $log = get_logger("");
my $errmsg;

sub getPriority {
    return 20;
}

# generate configuration files on node
sub addNode {
    my ($self, %args) = @_;

    General::checkParams(args     => \%args,
                         required => ['cluster','host','mount_point']);

    $log->debug("Configuration files generation");
    my $files = $self->generateConfiguration(%args);

    $log->debug("System image preconfiguration");
    $self->preconfigureSystemimage(%args, files => $files);
}

sub postStartNode {
    my ($self, %args) = @_;

    General::checkParams(args     => \%args,
                         required => [ 'cluster', 'host' ]);

    my $hosts = $args{cluster}->getHosts();
    my @ehosts = map { EEntity->new(entity => $_) } values %$hosts;
    for my $ehost (@ehosts) {
        $self->generateConfiguration(
            cluster => $args{cluster},
            host    => $ehost
        );
    }
}

sub postStopNode {
    my ($self, %args) = @_;

    General::checkParams(args     => \%args,
                         required => [ 'cluster', 'host' ]);

    my $hosts = $args{cluster}->getHosts();
    my @ehosts = map { EEntity->new(entity => $_) } values %$hosts;
    for my $ehost (@ehosts) {
        $self->generateConfiguration(
            cluster => $args{cluster},
            host    => $ehost
        );
    }    
}

# generate all component files for a host

sub generateConfiguration {
    my ($self, %args) = @_;

    General::checkParams(args     => \%args,
                         required => ['cluster','host']);
     
    my $generated_files = [];                     
                         
    push @$generated_files, $self->_generateHostname(%args);
    push @$generated_files, $self->_generateFstab(%args);
    push @$generated_files, $self->_generateResolvconf(%args);
    push @$generated_files, $self->_generateUdevPersistentNetRules(%args);
    push @$generated_files, $self->_generateHosts(
                                kanopya_domainname => $self->{_executor}->cluster_domainname,
                                %args
                            );

    return $generated_files;
}

# provision/tweak Systemimage with config files 

sub preconfigureSystemimage {
    my ($self, %args) = @_;
    General::checkParams(args     => \%args,
                         required => ['files','cluster','host','mount_point']);

    my $econtext = $self->getExecutorEContext;
    
    # send generated files to the image mount directory                    
    for my $file (@{$args{files}}) {
        $econtext->send(
            src  => $file->{src},
            dest => $args{mount_point}.$file->{dest}
        );
    }

    $self->_generateUserAccount(econtext => $econtext, %args);
    $self->_generateNtpdateConf(econtext => $econtext, %args);
    $self->_generateNetConf(econtext => $econtext, %args);

    # Set up fastboot
    $econtext->execute(
        command => "touch $args{mount_point}/fastboot"
    );
}

# individual file generation

sub _generateHostname {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host','cluster' ]);

    my $hostname = $args{host}->getAttr(name => 'host_hostname');
    my $file = $self->generateNodeFile(
        cluster       => $args{cluster},
        host          => $args{host},
        file          => '/etc/hostname',
        template_dir  => '/templates/components/linux',
        template_file => 'hostname.tt',
        data          => { hostname => $hostname }
    );
    
    return { src  => $file, dest => '/etc/hostname' };
}

sub _generateFstab {
    my ($self, %args) = @_;
    General::checkParams(args     => \%args,
                         required => ['cluster','host']);
    
    my $data = $self->_getEntity()->getConf();

    foreach my $row (@{$data->{linuxes_mount}}) {
        delete $row->{linux_id};
    }

    my $file = $self->generateNodeFile(
        cluster       => $args{cluster},
        host          => $args{host},
        file          => '/etc/fstab',
        template_dir  => '/templates/components/linux',
        template_file => 'fstab.tt',
        data          => $data 
    );
    
    return { src  => $file, dest => '/etc/fstab' };
                     
}

sub _generateHosts {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'cluster','host', 'kanopya_domainname' ]);

    $log->debug('Generate /etc/hosts file');

    my $nodes = $args{cluster}->getHosts();
    my @hosts_entries = ();

    # we add each nodes 
    foreach my $node (values %$nodes) {
        my $tmp = { 
            hostname   => $node->getAttr(name => 'host_hostname'),
            domainname => $args{kanopya_domainname},
            ip         => $node->getAdminIp 
        };

        push @hosts_entries, $tmp;
    }

    # we ask components for additional hosts entries
    my @components = $args{cluster}->getComponents(category => 'all');
    foreach my $component (@components) {
        my $entries = $component->getHostsEntries();
        if(defined $entries) {
            foreach my $entry (@$entries) {
                push @hosts_entries, $entry;
            }
        }
    }

    my $file = $self->generateNodeFile(
        cluster       => $args{cluster},
        host          => $args{host},
        file          => '/etc/hosts',
        template_dir  => '/templates/components/linux',
        template_file => 'hosts.tt',
        data          => { hosts => \@hosts_entries }
    );
    
    return { src  => $file, dest => '/etc/hosts' };
}

sub _generateResolvconf {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => ['cluster','host' ]);

    my @nameservers = ();

    for my $attr ('cluster_nameserver1','cluster_nameserver2') {
        push @nameservers, {
            ipaddress => $args{cluster}->getAttr(name => $attr)
        };
    }

    my $data = {
        domainname => $args{cluster}->getAttr(name => 'cluster_domainname'),
        nameservers => \@nameservers,
    };

    my $file = $self->generateNodeFile(
        cluster       => $args{cluster},
        host          => $args{host},
        file          => '/etc/resolv.conf',
        template_dir  => '/templates/components/linux',
        template_file => 'resolv.conf.tt',
        data          => $data
    );
    
    return { src  => $file, dest => '/etc/resolv.conf' };
}

sub _generateUdevPersistentNetRules {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'host','cluster' ]);

    my @interfaces = ();
    
    for my $iface ($args{host}->_getEntity()->getIfaces()) {
        my $tmp = {
            mac_address   => lc($iface->getAttr(name => 'iface_mac_addr')),
            net_interface => $iface->getAttr(name => 'iface_name')
        };
        push @interfaces, $tmp;
    }

    my $file = $self->generateNodeFile(
        cluster       => $args{cluster},
        host          => $args{host},
        file          => '/etc/udev/rules.d/70-persistent-net.rules',
        template_dir  => '/templates/components/linux',
        template_file => 'udev_70-persistent-net.rules.tt',
        data          => { interfaces => \@interfaces }
    );

    return { src  => $file, dest => '/etc/udev/rules.d/70-persistent-net.rules' };
}

sub _generateUserAccount {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => [ 'cluster', 'host', 'mount_point', 'econtext' ]);

    my $econtext = $args{econtext};
    my $user = $args{cluster}->user;
    my $login = $user->user_login;
    my $password = $user->user_password;

    # create user account and add sudoers entry if necessary
    my $cmd = "cat " . $args{mount_point} . "/etc/passwd | cut -d: -f1 | grep ^$login\$";
    my $result = $econtext->execute(command => $cmd);
    if ($result->{stdout}) {
        $log->info("User account $login already exists");
        Message->send(from => 'Executor', level => 'info',
                      content => "User account $login already exists");
    } else {
        # create the user account
        my $cmd = "chroot " . $args{mount_point} . " useradd -m -p '$password' $login";
        my $result = $econtext->execute(command => $cmd);

        # add a sudoers file
        $cmd = "umask 227 && echo '$login ALL=(ALL) ALL' > " . $args{mount_point} . "/etc/sudoers.d/$login";
        $result = $econtext->execute(command => $cmd);

        # add ssh pub key
        my $sshkey = $user->getAttr(name => 'user_sshkey');
        if(defined $sshkey) {
            # create ssh directory and authorized_keys file
            my $dir = $args{mount_point} . "/home/$login/.ssh";

            $cmd = "mkdir $dir";
            $result = $econtext->execute(command => $cmd);

            $cmd = "umask 177 && echo '$sshkey' > $dir/authorized_keys";
            $result = $econtext->execute(command => $cmd);

            $cmd = "chroot $args{mount_point} chown -R $login.$login /home/$login/.ssh ";
            $result = $econtext->execute(command => $cmd);
        }
    }
}

sub _generateNtpdateConf {
    my $self = shift;
    my %args = @_;

    General::checkParams(args     => \%args,
                         required => [ 'cluster', 'host', 'mount_point', 'econtext' ]);

    my $econtext = $args{econtext};
    my $file = $self->generateNodeFile(
        cluster       => $args{cluster},
        host          => $args{host},
        file          => '/etc/default/ntpdate',
        template_dir  => '/templates/components/linux',
        template_file => 'ntpdate.tt',
        data          => { ntpservers => $self->{_executor}->getMasterNodeIp() }
    );

    $econtext->send(
        src  => $file,
        dest => "$args{mount_point}/etc/default/ntpdate"
    );

    # send ntpdate init script
    $file = $self->generateNodeFile(
        cluster       => $args{cluster},
        host          => $args{host},
        file          => '/etc/init.d/ntpdate',
        template_dir  => '/templates/components/linux',
        template_file => 'ntpdate',
        data          => { }
    );

    $econtext->send(
        src  => $file,
        dest => "$args{mount_point}/etc/init.d/ntpdate"
    );

    $econtext->execute(command => "chmod +x $args{mount_point}/etc/init.d/ntpdate");

    $self->service(services    => [ "ntpdate" ],
                   state       => "on",
                   mount_point => $args{mount_point});
}

sub _generateNetConf {
    my $self = shift;
    my %args = @_;

    General::checkParams(args => \%args, required => [ 'cluster', 'mount_point', 'econtext' ]);

    # search for an potential 'loadbalanced' component
    my $cluster_components = $args{cluster}->getComponents(category => "all");
    my $is_masternode = $args{cluster}->getCurrentNodesCount == 0;
    my $is_loadbalanced = 0;
    foreach my $component (@{ $cluster_components }) {
        my $clusterization_type = $component->getClusterizationType();
        if ($clusterization_type && ($clusterization_type eq 'loadbalanced')) {
            $is_loadbalanced = 1;
            last;
        }
    }

    # Pop an IP adress for all host iface,
    my @net_ifaces;
    INTERFACES:
    foreach my $interface (@{$args{cluster}->getNetworkInterfaces}) {
        my $iface;
        eval {
            $iface = $interface->getAssociatedIface(host => $args{host});
        };
        if ($@) {
            $log->debug("Skipping configuration for interface " . $interface->getRole->interface_role_name);
            next INTERFACES;
        }

        # Only add non pxe iface to /etc/network/interfaces
        if (not $iface->getAttr(name => 'iface_pxe')) {
            my ($gateway, $netmask, $ip, $method);

            if ($iface->hasIp) {
                my $pool = $iface->getPoolip;
                $netmask = $pool->poolip_netmask;
                $ip = $iface->getIPAddr;
                $gateway = $interface->hasDefaultGateway() ? $pool->poolip_gateway : undef;
                $method = "static";
                if ($is_loadbalanced and not $is_masternode) {
                    $gateway = $args{cluster}->getMasterNodeIp
                }
            }
            else {
                $method = "manual";
            }

            push @net_ifaces, { method  => $method,
                                name    => $iface->iface_name,
                                address => $ip,
                                netmask => $netmask,
                                gateway => $gateway,
                                role    => $interface->getRole->interface_role_name };

            $log->info("Iface " .$iface->iface_name . " configured via static file");
        }
    }

    $self->_writeNetConf(interfaces => \@net_ifaces, %args);
}

sub service {
    my ($self, %args) = @_;

    General::checkParams(args     => \%args,
                         required => [ 'services', 'mount_point' ]);

    my @services = @{$args{services}};
    $log->info("Skipping configuration of @services");
}

sub _writeNetConf {
    my ($self, %args) = @_;

    General::checkParams(args     => \%args,
                         required => [ 'cluster' ]);

    $log->info("Skipping configuration of network for cluster " . $args{cluster}->cluster_name);
}

1;
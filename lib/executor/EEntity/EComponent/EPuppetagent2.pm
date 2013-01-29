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
package EEntity::EComponent::EPuppetagent2;
use base "EEntity::EComponent";

use strict;
use Template;
use General;
use EEntity;
use Log::Log4perl "get_logger";

my $log = get_logger("");
my $errmsg;

# generate configuration files on node
sub configureNode {
    my ($self, %args) = @_;
    General::checkParams(args     => \%args,
                         required => ['cluster','host','mount_point']);
    
    my $conf = $self->_getEntity()->getConf();

    # Generation of /etc/default/puppet
    my $data = { 
        puppetagent2_bootstart => 'yes',
        puppetagent2_options   => $conf->{puppetagent2_options},
    };
    
    my $file = $self->generateNodeFile(
        cluster       => $args{cluster},
        host          => $args{host},
        file          => '/etc/default/puppet',
        template_dir  => '/templates/components/puppetagent',
        template_file => 'default_puppet.tt',
        data          => $data
    );
    
    $self->getExecutorEContext->send(
        src  => $file,
        dest => $args{mount_point}.'/etc/default'
    );
    
    # Generation of puppet.conf
    $data = { 
        puppetagent2_masterserver => $conf->{puppetagent2_masterfqdn},
    };
     
    $file = $self->generateNodeFile( 
        cluster       => $args{cluster},
        host          => $args{host},
        file          => '/etc/puppet/puppet.conf',
        template_dir  => '/templates/components/puppetagent',
        template_file => 'puppet.conf.tt', 
        data         => $data
    );

     $self->getExecutorEContext->send(
        src  => $file,
        dest => $args{mount_point}.'/etc/puppet'
    );
}

sub addNode {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'cluster','mount_point', 'host' ]);

    if ($self->puppetagent2_mode eq 'kanopya') {
        # create, sign and push a puppet certificate on the image
        $log->info('Puppent agent component configured with kanopya puppet master');
        my $puppetmaster = EEntity->new(entity => $self->getPuppetMaster);
        my $fqdn = $args{host}->host_hostname . "." . $self->{_executor}->cluster_domainname;

        $puppetmaster->createHostCertificate(
            mount_point => $args{mount_point},
            host_fqdn   => $fqdn
        );
    }

    $self->configureNode(
        cluster     => $args{cluster},
        mount_point => $args{mount_point},
        host        => $args{host}
    );
    
    $self->addInitScripts(    
        mountpoint => $args{mount_point}, 
        scriptname => 'puppet', 
    );    

    $self->generatePuppetDefinitions(%args);
}

sub generatePuppetDefinitions {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'cluster', 'host' ]);

    my $puppetmaster = EEntity->new(entity => $self->getPuppetMaster);
    my $fqdn = $args{host}->host_hostname . "." . $self->{_executor}->cluster_domainname;
    my $puppet_definitions = "";
    my $cluster_components = $args{cluster}->getComponents(category => "all", order_by => "priority");
    foreach my $component (@{ $cluster_components }) {
        # retrieve puppet definition to create manifest
        $puppet_definitions .= $component->getPuppetDefinition(
            host    => $args{host},
            cluster => $args{cluster},
        );
    }

    if ($self->puppetagent2_mode eq 'kanopya') {
        # create, sign and push a puppet certificate on the image
        $log->info('Puppent agent component configured with kanopya puppet master');
        my $puppetmaster = EEntity->new(entity => $self->getPuppetMaster);
        my $fqdn = $args{host}->host_hostname . "." . $self->{_executor}->cluster_domainname;

        $puppetmaster->createHostManifest(
            host_fqdn          => $fqdn,
            puppet_definitions => $puppet_definitions
        );
    }
}

sub postStartNode {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'cluster', 'host' ]);

    $self->applyConfiguration(%args);
}

sub postStopNode {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'cluster', 'host' ]);

    $self->applyConfiguration(%args);
}

sub applyConfiguration {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'cluster' ]);

    EEntity->new(entity => $self->getPuppetMaster)->updateSite();

    my $hosts = $args{cluster}->getHosts();
    my @ehosts = map { EEntity->new(entity => $_) } values %$hosts;
    for my $ehost (@ehosts) {
        $self->generatePuppetDefinitions(%args,
                                         host => $ehost);
        $self->applyManifest(%args,
                             host => $ehost);
    }
}

sub applyAllManifests {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'cluster' ]);

    my $hosts = $args{cluster}->getHosts();
    my @ehosts = map { EEntity->new(entity => $_) } values %$hosts;
    for my $ehost (@ehosts) {
        $self->applyManifest(host => $ehost);
    }
}

sub applyManifest {
    my ($self, %args) = @_;
    General::checkParams(args => \%args, required => ['host']);
    my $econtext = $args{host}->getEContext;
    $econtext->execute(command => 'puppet agent --test');
}

1;

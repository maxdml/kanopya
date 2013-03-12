class kanopya::openstack::repository {
    if $operatingsystem =~ /(?i)(ubuntu)/ {
        package { 'ubuntu-cloud-keyring':
            name => 'ubuntu-cloud-keyring',
            ensure => present,
        }

        class { 'apt':
            always_apt_update => true,
        }

        apt::source { 'ubuntu-cloud-repository':
            location => 'http://ubuntu-cloud.archive.canonical.com/ubuntu',
            release  => 'precise-updates/folsom',
            repos    => 'main',
        }
    }
}

class kanopya::keystone($dbserver, $password) {
    @@mysql::db { 'keystone':
        user     => 'keystone',
        password => "${password}",
        host     => "${ipaddress}",
        grant    => ['all'],
        tag      => "${dbserver}",
    }

    class { 'keystone::endpoint':
        public_address   => "${fqdn}",
        admin_address    => "${fqdn}",
        internal_address => "${fqdn}",
    }

    Keystone_user <<| tag == "${fqdn}" |>>
    Keystone_user_role <<| tag == "${fqdn}" |>>
    Keystone_service <<| tag == "${fqdn}" |>>
    Keystone_endpoint <<| tag == "${fqdn}" |>>

    Class['kanopya::openstack::repository'] -> Class['kanopya::keystone']
}

class kanopya::glance($dbserver, $password, $keystone, $email) {
    @@mysql::db { 'glance':
        user     => 'glance',
        password => "${password}",
        host     => "${ipaddress}",
        grant    => ['all'],
        tag      => "${dbserver}",
    }

    @@keystone_user { 'glance':
        ensure   => present,
        password => "${password}",
        email    => "${email}",
        tenant   => 'services',
        tag      => "${keystone}"
    }

    @@keystone_user_role { "glance@services":
        ensure  => present,
        roles   => 'admin',
        tag     => "${keystone}"
    }

    @@keystone_service { 'glance':
        ensure      => present,
        type        => 'image',
        description => "Openstack Image Service",
        tag         => "${keystone}"
    }

    @@keystone_endpoint { "RegionOne/glance":
        ensure       => present,
        public_url   => "http://${fqdn}:9292/v2",
        admin_url    => "http://${fqdn}:9292/v2",
        internal_url => "http://${fqdn}:9292/v2",
        tag          => "${keystone}"
    }

    class { 'glance::api':
        verbose           => 'True',
        debug             => 'True',
        auth_type         => '',
        auth_port         => '35357',
        keystone_tenant   => 'services',
        keystone_user     => 'glance',
        keystone_password => 'glance',
        sql_connection    => "mysql://glance:${password}@${dbserver}/glance",
        require           => Class['kanopya::openstack::repository']
    }

    class { 'glance::registry':
        verbose           => 'True',
        debug             => 'True',
        auth_type         => '',
        keystone_tenant   => 'services',
        keystone_user     => 'glance',
        keystone_password => 'glance',
        sql_connection    => "mysql://glance:${password}@${dbserver}/glance",
        require           => Class['kanopya::openstack::repository']
    }

    class { 'glance::backend::file': }

    Class['kanopya::openstack::repository'] -> Class['kanopya::glance']
}

class kanopya::novacontroller($password, $dbserver, $amqpserver, $keystone, $email, $glance, $quantum) {
    exec { "/usr/bin/nova-manage db sync":
        path => "/usr/bin:/usr/sbin:/bin:/sbin",
    }

    class { 'nova::api':
        enabled        => true,
        admin_password => "${password}",
        auth_host      => "${keystone}",
        require        => [ Exec["/usr/bin/nova-manage db sync"],
                            Class['kanopya::openstack::repository'] ]
    }

    if ! defined(Class['kanopya::nova::common']) {
        class { 'kanopya::nova::common':
            amqpserver => "${amqpserver}",
            dbserver   => "${dbserver}",
            glance     => "${glance}",
            keystone   => "${keystone}",
            email      => "${email}",
            password   => "${password}"
        }
    }

    class { 'nova::network::quantum':
        quantum_admin_password    => "quantum",
        quantum_auth_strategy     => 'keystone',
        quantum_url               => "http://${quantum}:9696",
        quantum_admin_tenant_name => 'services',
        quantum_admin_auth_url    => "http://${keystone}:35357/v2.0",
        require                   => Class['kanopya::openstack::repository']
    }

    class { 'nova::scheduler':
        enabled => true,
        require => Class['kanopya::openstack::repository']
    }

    class { 'nova::objectstore':
        enabled => true,
        require => Class['kanopya::openstack::repository']
    }

    class { 'nova::cert':
        enabled => true,
        require => Class['kanopya::openstack::repository']
    }

    class { 'nova::vncproxy':
        enabled => true,
        require => Class['kanopya::openstack::repository']
    }

    class { 'nova::consoleauth':
        enabled => true,
        require => Class['kanopya::openstack::repository']
    }

    Class['kanopya::openstack::repository'] -> Class['kanopya::novacontroller']
}

class kanopya::novacompute($amqpserver, $dbserver, $glance, $keystone, $email, $password, $libvirt_type) {
    file { "/run/iscsid.pid":
        content => "1",
    }

    if ! defined(Class['kanopya::nova::common']) {
        class { 'kanopya::nova::common':
            amqpserver => "${amqpserver}",
            dbserver   => "${dbserver}",
            glance     => "${glance}",
            keystone   => "${keystone}",
            email      => "${email}",
            password   => "${password}"
        }
    }

    class { 'nova::compute':
        enabled => true,
        require => Class['kanopya::openstack::repository']
    }

    class { 'nova::compute::quantum':
        libvirt_vif_driver => 'nova.virt.libvirt.vif.LibvirtHybridOVSBridgeDriver',
        require            => Class['kanopya::openstack::repository']
    }

    class { 'nova::compute::libvirt':
        libvirt_type      => "${libvirt_type}",
        migration_support => true,
        vncserver_listen  => '0.0.0.0'
    }

    @@keystone_service { 'compute':
        ensure      => present,
        type        => "compute",
        description => "Nova Compute Service",
        tag         => "${keystone}"
    }

    @@keystone_endpoint { "RegionOne/compute":
        ensure       => present,
        public_url   => "http://${fqdn}:8774/v2/\$(tenant_id)s",
        admin_url    => "http://${fqdn}:8774/v2/\$(tenant_id)s",
        internal_url => "http://${fqdn}:8774/v2/\$(tenant_id)s",
        tag          => "${keystone}"
    }

    class { 'quantum::agents::ovs':
        integration_bridge  => 'br-int',
        bridge_mappings     => [ 'physflat:br-flat', 'physvlan:br-vlan' ],
        bridge_uplinks      => [ 'br-flat:eth1' ]
    }

    Class['kanopya::openstack::repository'] -> Class['kanopya::novacompute']
}

class kanopya::quantum_($amqpserver, $dbserver, $keystone, $password, $email, $bridge_flat, $bridge_vlan) {
    class { 'quantum':
        rabbit_password => "${password}",
        rabbit_host     => "${amqpserver}",
        rabbit_user     => 'quantum',
    }

    class { 'quantum::server':
        auth_password => $password,
        auth_host     => "${keystone}",
        require       => Class['kanopya::openstack::repository']
    }

    @@mysql::db { 'quantum':
        user     => 'quantum',
        password => "${password}",
        host     => "${ipaddress}",
        tag      => "${dbserver}"
    }

    @@rabbitmq_user { 'quantum':
        admin    => true,
        password => "${password}",
        provider => 'rabbitmqctl',
        tag      => "${amqpserver}"
    }

    @@rabbitmq_user_permissions { "quantum@/":
        configure_permission => '.*',
        write_permission     => '.*',
        read_permission      => '.*',
        provider             => 'rabbitmqctl',
        tag                  => "${amqpserver}"
    }

    @@keystone_user { 'quantum':
        ensure   => present,
        password => "${password}",
        email    => "${email}",
        tenant   => "services",
        tag      => "${keystone}"
    }

    @@keystone_user_role { "quantum@services":
        ensure  => present,
        roles   => 'admin',
        tag     => "${keystone}"
    }

    @@keystone_service { 'quantum':
        ensure      => present,
        type        => "network",
        description => "Quantum Networking Service",
        tag         => "${keystone}"
    }

    @@keystone_endpoint { "RegionOne/quantum":
        ensure       => present,
        public_url   => "http://${fqdn}:9696",
        admin_url    => "http://${fqdn}:9696",
        internal_url => "http://${fqdn}:9696",
        tag          => "${keystone}"
    }

    class { 'quantum::plugins::ovs':
        sql_connection      => "mysql://quantum:${password}@${dbserver}/quantum",
        tenant_network_type => 'vlan',
        network_vlan_ranges => 'physnetflat,physnetvlan:1:4094',
        bridge_mappings     => [ "physnetflat:${bridge_flat}", "physnetvlan:${bridge_vlan}" ],
        require             => Class['kanopya::openstack::repository']
    }

    Class['kanopya::openstack::repository'] -> Class['kanopya::quantum_']
}

class kanopya::nova::common($amqpserver, $dbserver, $glance, $keystone, $email, $password) {
    @@rabbitmq_user { 'nova':
        admin    => true,
        password => "${password}",
        provider => 'rabbitmqctl',
        tag      => "${amqpserver}",
    }

    @@rabbitmq_user_permissions { "nova@/":
        configure_permission => '.*',
        write_permission     => '.*',
        read_permission      => '.*',
        provider             => 'rabbitmqctl',
        tag                  => "${amqpserver}",
    }

    @@keystone_user { 'nova':
        ensure   => present,
        password => "${password}",
        email    => "${email}",
        tenant   => 'services',
        tag      => "${keystone}",
    }

    @@keystone_user_role { 'nova@services':
        ensure  => present,
        roles   => 'admin',
        tag     => "${keystone}",
    }

    @@mysql::db { 'nova':
            user     => 'nova',
            password => "${password}",
            host     => "${ipaddress}",
            grant    => ['all'],
            charset  => 'latin1',
            tag      => "${dbserver}",
    }

    @@database_user { "nova@${fqdn}":
        password_hash => mysql_password("${password}"),
        tag           => "${dbserver}",
    }

    @@database_grant { "nova@${fqdn}/nova":
        privileges => ['all'] ,
        tag        => "${dbserver}"
    }

    class { 'nova':
        # set sql and rabbit to false so that the resources will be collected
        sql_connection     => "mysql://nova:${password}@${dbserver}/nova",
        rabbit_host        => "${amqpserver}",
        image_service      => 'nova.image.glance.GlanceImageService',
        glance_api_servers => "${glance}",
        rabbit_userid      => "nova",
        rabbit_password    => "nova"
    }
}

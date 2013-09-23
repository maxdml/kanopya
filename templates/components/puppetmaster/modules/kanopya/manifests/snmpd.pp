class kanopya::snmpd::service {
	file { '/etc/snmp/snmpd.conf':
		path    => '/etc/snmp/snmpd.conf',
		ensure  => present,
		mode    => 0644,
		source  => "puppet:///kanopyafiles/${sourcepath}/etc/snmp/snmpd.conf",
		notify  => Service['snmpd'],
		require => Package['snmpd']
	}

	if $operatingsystem =~ /(?i)(debian|ubuntu)/ {
		file { '/etc/default/snmpd':
			path    => '/etc/default/snmpd',
			ensure  => present,
			mode    => 0644,
			source  => "puppet:///kanopyafiles/${sourcepath}/etc/default/snmpd",
			notify  => Service['snmpd']
		}
	}

	service {
		'snmpd':
			name => $operatingsystem ? {
				default => 'snmpd'
			},
			ensure => running,
			hasrestart => true,
			enable => true,
			require => [ Package['snmpd'],
			             File['/etc/snmp/snmpd.conf'] ]
	}
}

class kanopya::snmpd::install {
	package {
		'snmpd':
			name => $operatingsystem ? {
				/(RedHat|CentOS|Fedora)/ => 'net-snmp',
				default => 'snmpd'
			},
			ensure => present,
	}
}

class kanopya::snmpd {
    include kanopya::snmpd::install, kanopya::snmpd::service
}


class keepalived::service {
	service {
		'keepalived':
			name => $operatingsystem ? {
				default => 'keepalived'
			},
			ensure => running,
			hasstatus => true,
			hasrestart => true,
			enable => true,
	}
}

class keepalived::install {
	package {
		'keepalived':
			name => $operatingsystem ? {
				default => 'keepalived'
			},
			ensure => present,
	}
}

class keepalived {
	include keepalived::install, keepalived::service
}

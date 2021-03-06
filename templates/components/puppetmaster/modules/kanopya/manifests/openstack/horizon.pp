#
# == Class: kanopya::openstack::horizon
# Based on class openstack::horizon
#
# FIXME This class is a WORKAROUND for story #2373
# FIXME MUST BE REWRITED AND ADDED AS COMPONENT
# 
# Class to install / configure horizon.
# Will eventually include apache and ssl.
#
# FIXME Memcached is installed and configured by this class
# FIXME A better way is using Kanopya Memcache component
# FIXME (Urgent bugfix for Kanopya)
#
# Specific changes between 
# - python-lesscpy is installed (story #2371)
# - _member_ is the default role instead of Member (story #2372)
# - Allowed fqdn is '*' (story #2373) 
# 
# === Parameters
#
# [*secret_key*]
#   (required) A secret key for a particular Django installation. This is used to provide cryptographic signing,
#   and should be set to a unique, unpredictable value.
#
# [*configure_memcached*]
#   (optional) Enable/disable the use of memcached with Horizon.
#   Defaults to true.
#
# [*memcached_listen_ip*]
#   (optional) The IP address for binding memcached.
#   Defaults to undef.
#
# [*cache_server_ip*]
#   (optional) Ip address where the memcache server is listening.
#   Defaults to '127.0.0.1'.
#
# [*cache_server_port*]
#    (optional) Port that memcache server listens on.
#    Defaults to '11211'.
#
# [*horizon_app_links*]
#   (optional) External Monitoring links.
#   Defaults to undef.
#
# [*keystone_host*]
#   (optional) Address of keystone host.
#   Defaults to '127.0.0.1'.
#
# [*keystone_scheme*]
#    (optional) Protocol for keystone. Accepts http or https.
#    Defaults to http.
#
# [*keystone_default_role*]
#   (Optional) Default role for keystone authentication.
#   Defaults to 'Member'.
#
# [*django_debug*]
#    (Optional) Sets Django debug level.
#    Defaults to false.
#
# [*api_result_limit*]
#    (Optional) Maximum results to show on a page before pagination kicks in.
#    Defaults to 1000.
#
# === Examples
#
# class { 'openstack::horizon':
#   secret_key => 'dummy_secret_key',
# }
#

class kanopya::openstack::horizon (
  $secret_key,
  $fqdn                  = '*',
  $configure_memcached   = true,
  $memcached_listen_ip   = undef,
  $cache_server_ip       = '127.0.0.1',
  $cache_server_port     = '11211',
  $horizon_app_links     = undef,
  $keystone_host         = '127.0.0.1',
  $keystone_scheme       = 'http',
  $keystone_default_role = '_member_',
  $django_debug          = 'False',
  $api_result_limit      = 1000
) {

  if $configure_memcached {
    if $memcached_listen_ip {
      $cache_server_ip_real = $memcached_listen_ip
    } else {
      warning('The cache_server_ip parameter is deprecated. Use memcached_listen_ip instead.')
      $cache_server_ip_real = $cache_server_ip
    }
    class { 'memcached':
      listen_ip => $cache_server_ip_real,
      tcp_port  => $cache_server_port,
      udp_port  => $cache_server_port,
    }
  }

  class { '::horizon':
    fqdn                  => $fqdn,
    cache_server_ip       => $cache_server_ip,
    cache_server_port     => $cache_server_port,
    secret_key            => $secret_key,
    horizon_app_links     => $horizon_app_links,
    keystone_host         => $keystone_host,
    keystone_scheme       => $keystone_scheme,
    keystone_default_role => $keystone_default_role,
    django_debug          => $django_debug,
    api_result_limit      => $api_result_limit,
  }

  #For CSS
  package { 'python-lesscpy':
    ensure => present,
  }

  if str2bool($::selinux) {
    selboolean{'httpd_can_network_connect':
      value      => on,
      persistent => true,
    }
  }
}

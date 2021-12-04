include nginx


node 'domain.com' {
  nginx::resource::server { 'domain.com':
    ensure            => present,
    listen_port       => 443,
    ssl_port          => 443,
    ssl_verify_client => 'off',
    ssl               => true,
    ssl_cert          => '/etc/ssl/certs/puppet-agent-nginx-selfsigned.crt',
    ssl_key           => '/etc/ssl/private/puppet-agent-nginx-selfsigned.key',
    access_log        => '/var/log/nginx/access.log',
    error_log         => '/var/log/nginx/access.log',
    proxy             => 'http://10.10.10.10:80',
  }

  nginx::resource::location { '/resource2':
    ensure   => present,
    server   => 'domain.com',
    ssl_only => true,
    proxy    => 'http://20.20.20.20:80',
  }
}


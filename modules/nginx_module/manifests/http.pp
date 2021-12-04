include nginx


node 'domain.com' {
  nginx::resource::server { 'domain.com':
    listen_port => 80,
    proxy       => 'http://10.10.10.10:80',
  }

  nginx::resource::location { '/resource2':
    server => 'domain.com',
    proxy  => 'http://20.20.20.20:80',
  }
}

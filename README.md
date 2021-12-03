# puppet-nginx-module-test

Create/extend an existing puppet module for Nginx including the following functionalities:

- Create a proxy to redirect requests for https://domain.com to 10.10.10.10 and redirect requests for https://domain.com/resource2 to 20.20.20.20.
- Create a forward proxy to log HTTP requests going from the internal network to the Internet including: request protocol, remote IP and time take to serve the request.
- (Optional) Implement a proxy health check.

## Considerations

As long as we are using Docker and Docker networking using Docker Compose, we can't reach from external sources any container unless ports are exposed. Using internal for the 10.10.10.10 and 20.20.20.20 machines will work. Connectivity through containers is managed by Docker networking.

Please note that .env file is uploaded and contains some random passwords for Graylog instances only valid for testing purposes. This SHOULD NEVER BE DONE in any other circumstance. (u: admin p: 12345).

This README file provides some light on the implementation of this automation.

## Infrastructure bootstrap

There is a [GUIDE](docs/RUN.md) where you can follow simple steps to bootstrap the infrastructure using Docker Compose.

As the agent service needs the Puppet server to be active in order to request certificates we will add in Docker Compose a condition waiting for service to be healthy.

```bash
    depends_on:
      puppet-server:
        condition: service_healthy
```

> I've been playing with PDK but for simplicity I've used a simple approach by loading init.pp module file through volumes into the Puppet server to provide our module.

Create a file init.pp inside manifests folder

```ruby
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
```

Modules should be installed on Puppet server instance, to test it, let's execute an installation on the server for puppet-nginx module.

```bash
docker exec -it puppet-server puppet module install puppet-nginx
```

```bash
ivan@DESKTOP-26PPR46:/mnt/c/Users/ivann/Development/ntcntrc$ docker run --rm -it -v ${PWD}/modules/nginx_module/:/root/nginx_module puppet/pdk new module^C
ivan@DESKTOP-26PPR46:/mnt/c/Users/ivann/Development/ntcntrc$ docker exec -it puppet-server puppet
See 'puppet help' for help on available puppet subcommands
ivan@DESKTOP-26PPR46:/mnt/c/Users/ivann/Development/ntcntrc$ docker exec -it puppet-server puppet module install puppet-nginx
Notice: Preparing to install into /etc/puppetlabs/code/environments/production/modules ...
Notice: Downloading from https://forgeapi.puppet.com ...
Notice: Installing -- do not interrupt ...
/etc/puppetlabs/code/environments/production/modules
└─┬ puppet-nginx (v3.3.0)
  └─┬ puppetlabs-concat (v7.1.1)
    └── puppetlabs-stdlib (v8.1.0)
```

Add to docker-compose.yaml and run

```bash
docker compose up -d --force-recreate --build
```

When running this command if we run into the issue:

> Error: The certificate for 'CN=domain.com' does not match its private key
> Error: Could not run: The certificate for 'CN=domain.com' does not match its private key

Then we need to refresh CA certs from Puppet server, to do it in a greedy way:

Get into Puppet server container

```bash
docker exec -it puppet-server bash
root@puppet:~# puppet resource service puppet ensure=stopped
root@puppet:~# cd /
root@puppet:/# ./docker_entrypoint.sh
root@puppet:/# service puppetserver status # If it's not running, just do it run
root@puppet:/# service puppetserver start
```

Then remove the agent and recreate it

```bash
docker compose up -d
```

If you run into the error while starting agent (which will do):

> Error: Could not retrieve catalog from remote server: Error 500 on SERVER: Server Error: Evaluation Error: Error while evaluating a Function Call, Could not find class ::nginx for domain.com (file: /etc/puppetlabs/code/environments/production/manifests/nginx_module.pp, line: 1, column: 1) on node domain.com

This is due to the lack of the nginx module in Puppet server, then install it

Install nginx and apt modules in Puppet server

```bash
docker exec -it puppet-server puppet module install puppet-nginx
docker exec -it puppet-server puppet module install puppetlabs-apt
# Restart stopped container to retrieve new facts from master (Not a new container as this is the one that contains the certificate)
docker compose up -d
```

We move into agent NGINX container in order to test connectivity with our configuration

```bash
docker-exec -it puppet-agent-nginx bash
```

Always, after applying a new change in Puppet server, restart the container:

```bash
docker compose stop puppet-agent-nginx
docker compose up -d
```

Provide a first approach for init.pp using HTTP only

```bash
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
```

### First connectivity test

If we now curl to domain.com to check connectivity we won't get response

```bash
root@domain:/# curl -I domain.com
```

We now get 502 Bad Gateway error. Why?

```bash
root@domain:/# curl -I domain.com
HTTP/1.1 502 Bad Gateway
Server: nginx/1.20.2
Date: Wed, 01 Dec 2021 20:56:18 GMT
Content-Type: text/html
Content-Length: 157
Connection: keep-alive
```

If we curl from inside to internal ips:

```bash
root@domain:/# curl -I 10.10.10.10
curl: (7) Failed to connect to 10.10.10.10 port 80: No route to host

root@domain:/# curl -I 20.20.20.20
curl: (7) Failed to connect to 20.20.20.20 port 80: No route to host
```

I was stating in my docker-compose the subnet ips for the networks as 10.10.10.10/24 instead of 10.10.10.0/24 :dissapointed:

### Second connectivity test

If we curl from inside to internal ips:

```bash
root@domain:/# cat /etc/hosts
127.0.0.1       localhost
::1     localhost ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
172.21.0.3      domain.com domain
20.20.20.2      domain.com domain
10.10.10.2      domain.com domain
```

```bash
ivan@DESKTOP-26PPR46:/ntcntrc$ docker exec -it puppet-agent-nginx curl domain.com
<h1>This is 10.10.10.10</h1>

ivan@DESKTOP-26PPR46:/ntcntrc$ docker exec -it puppet-agent-nginx curl 10.10.10.10
<h1>This is 10.10.10.10</h1>

ivan@DESKTOP-26PPR46:/ntcntrc$ docker exec -it puppet-agent-nginx curl 20.20.20.20
<h1>This is 20.20.20.20</h1>
```

We can check NGINX conf generated from inside agent container:

```bash
root@domain:/# cat /etc/nginx/sites-available/domain.com.conf
# MANAGED BY PUPPET
server {
  listen *:80;


  server_name           domain.com;


  index  index.html index.htm index.php;
  access_log            /var/log/nginx/domain.com.access.log;
  error_log             /var/log/nginx/domain.com.error.log;

  location / {
    proxy_pass            http://10.10.10.10:80;
    proxy_read_timeout    90s;
    proxy_connect_timeout 90s;
    proxy_send_timeout    90s;
    proxy_set_header      Host $host;
    proxy_set_header      X-Real-IP $remote_addr;
    proxy_set_header      X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header      X-Forwarded-Proto $scheme;
    proxy_set_header      Proxy "";
  }

  location /resource2 {
    proxy_pass            http://20.20.20.20:80;
    proxy_read_timeout    90s;
    proxy_connect_timeout 90s;
    proxy_send_timeout    90s;
    proxy_set_header      Host $host;
    proxy_set_header      X-Real-IP $remote_addr;
    proxy_set_header      X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header      X-Forwarded-Proto $scheme;
    proxy_set_header      Proxy "";
  }
}
```

### Setting SSL

Update the init.pp module manifest to implement a first approach.

```bash
include nginx

node 'domain.com' {
  nginx::resource::server { 'domain.com':
    listen_port => 443,
    ssl         => true,
    ssl_port    => 443,
    ssl_cert    => false,
    ssl_key     => false,
    proxy       => 'http://10.10.10.10:80'
  }

  nginx::resource::location { '/resource2':
    server => 'domain.com',
    proxy  => 'http://20.20.20.20:80',
  }
}
```

Gather the new facts

```bash
root@domain:/# puppet agent --verbose --onetime --no-daemonize --summarize
Info: Using environment 'production'
Info: Retrieving pluginfacts
Info: Retrieving plugin
Info: Loading facts
Info: Caching catalog for domain.com
Info: Applying configuration version '1638470079'

Error: Could not start Service[nginx]: Execution of '/etc/init.d/nginx start' returned 1: nginx: [emerg] "location" directive is not allowed here in /etc/nginx/sites-enabled/domain.com.conf:2
```

Let's check conf file:

```bash
root@domain:/# cat /etc/nginx/sites-available/domain.com.conf

  location /resource2 {
    proxy_pass            http://20.20.20.20:80;
    proxy_read_timeout    90s;
    proxy_connect_timeout 90s;
    proxy_send_timeout    90s;
    proxy_set_header      Host $host;
    proxy_set_header      X-Real-IP $remote_addr;
    proxy_set_header      X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header      X-Forwarded-Proto $scheme;
    proxy_set_header      Proxy "";
  }
# MANAGED BY PUPPET
server {
  listen       *:443 ssl;


  server_name  domain.com;


  index  index.html index.htm index.php;
  access_log            /var/log/nginx/ssl-domain.com.access.log;
  error_log             /var/log/nginx/ssl-domain.com.error.log;


  location / {
    proxy_pass            http://10.10.10.10:80;
    proxy_read_timeout    90s;
    proxy_connect_timeout 90s;
    proxy_send_timeout    90s;
    proxy_set_header      Host $host;
    proxy_set_header      X-Real-IP $remote_addr;
    proxy_set_header      X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header      X-Forwarded-Proto $scheme;
    proxy_set_header      Proxy "";
  }
}
```

WTH? For any reason the resulting NGINX config file is unstructured.

Searching for this error, results raise:

[https://github.com/voxpupuli/puppet-nginx/issues/1142](https://github.com/voxpupuli/puppet-nginx/issues/1142) this could be the solution, let's try.

It works, we need to set ssl_only => true on resource2 location and it will generate the proper config after gathering new facts.

```ruby
include nginx


node 'domain.com' {
  nginx::resource::server { 'domain.com':
    ensure            => present,

    # HTTPS only server
    ssl               => true,
    listen_port       => 443,
    ssl_port          => 443,
    ssl_verify_client => 'off',
    ssl_cert          => '/etc/ssl/certs/puppet-agent-nginx-selfsigned.crt',
    ssl_key           => '/etc/ssl/private/puppet-agent-nginx-selfsigned.key',
    access_log        => 'syslog:server=graylog:5140 custom_format',
    error_log         => 'syslog:server=graylog:5140',
    proxy             => 'http://10.10.10.10',
  }

  nginx::resource::location { '/resource2':
    ensure         => present,

    server         => 'domain.com',
    ssl_only       => true,
    ssl            => true,
    proxy          => 'http://20.20.20.20',
  }
}
```

```bash
root@domain:/# curl https://domain.com -k
<h1>This is 10.10.10.10</h1>
```

Our final config will look like this

```bash
root@domain:/etc/nginx/sites-available# cat domain.com.conf

log_format custom_format  '$remote_addr - $remote_user $time_local $request $status $body_bytes_sent $http_referer';
# MANAGED BY PUPPET
server {
  listen       *:443 ssl;


  server_name  domain.com;

  ssl_certificate           /etc/ssl/certs/puppet-agent-nginx-selfsigned.crt;
  ssl_certificate_key       /etc/ssl/private/puppet-agent-nginx-selfsigned.key;

  index  index.html index.htm index.php;
  access_log            syslog:server=graylog:5140 custom_format;
  error_log             syslog:server=graylog:5140;


  location /resource2 {
    proxy_pass            http://20.20.20.20:80;
    proxy_read_timeout    90s;
    proxy_connect_timeout 90s;
    proxy_send_timeout    90s;
    proxy_set_header      Host $host;
    proxy_set_header      X-Real-IP $remote_addr;
    proxy_set_header      X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header      X-Forwarded-Proto $scheme;
    proxy_set_header      Proxy "";
  }

  location / {
    proxy_pass            http://10.10.10.10:80;
    proxy_read_timeout    90s;
    proxy_connect_timeout 90s;
    proxy_send_timeout    90s;
    proxy_set_header      Host $host;
    proxy_set_header      X-Real-IP $remote_addr;
    proxy_set_header      X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header      X-Forwarded-Proto $scheme;
    proxy_set_header      Proxy "";
  }
}
```

My big gotcha here, I don't know why https://domain.com/resource2 can't be reached from URL.

I've got two possible workarounds but no time to implement them:

- It seems that configuring ssl_only on /resource2 location may be the culprit.
- Checking regex url for location.

## Logging (UNFINISHED :disappointed:)

### Graylog

I tried fluentd but having some issues with their containers and went into Graylog.

When starting UI for first time, use admin and the password generated previously and stated in graylog/.env file.

Commands to generate passwords:
GRAYLOG_PASSWORD_SECRET: `pwgen -N 1 -s 96`
GRAYLOG_ROOT_PASSWORD_SHA2: `echo -n "Enter password: " && head -1 </dev/stdin | tr -d '\n' | sha256sum | cut -d" " -f1`

### Graylog troubleshooting

For troubleshooting inside graylog container

```bash
# clear password root
graylog@43b03fbf23c2:~$ sed -i 's/password_secret =.*/password_secret = /' data/config/graylog.conf

# clear password sha2
graylog@43b03fbf23c2:~$ sed -i 's/root_password_sha2 =.*/root_password_sha2 = /' data/config/graylog.conf

# Add pwd to config lines (need a container restart)
graylog@43b03fbf23c2:~$ sed -i '/^root_password_sha2 =/ s/$/ e8c039209e898ce1fd9377e6e66b11bc13ec16493865e94e559f1ecc9552dbc0/' data/config/graylog.conf
graylog@43b03fbf23c2:~$ sed -i '/^password_secret =/ s/$/ 2mt9umI90mhlamuuwH75prnoRkyCyIVUFI3XkMCVxt4AUNrJDobc7Z0MckvCStu2pMdMtlO3NsEuwpMbCHRn96ElhJYZ3gyQ/' data/config/graylog.conf

List all configuration options without comments
graylog@43b03fbf23c2:~$ sed -e '/^#/d' data/config/graylog.conf
or
graylog@43b03fbf23c2:~$ grep -v '^#' data/config/graylog.conf
```

I'm having some issues while creating format_log in puppet module.

As far as docs state in [https://nginx.org/en/docs/http/ngx_http_log_module.html#log_format](https://nginx.org/en/docs/http/ngx_http_log_module.html#log_format) log_format key should be used and [http://www.puppetmodule.info/github/voxpupuli/puppet-nginx/puppet_defined_types/nginx_3A_3Aresource_3A_3Aserver](http://www.puppetmodule.info/github/voxpupuli/puppet-nginx/puppet_defined_types/nginx_3A_3Aresource_3A_3Aserver) states that format_log should be used and there exists some kind of mismatch in naming rules, that way I can't rewrite the f_format. I will relay on defaults.

Docs in puppet-nginx module configuration are pretty inexistent.

```ruby
    format_log        => 'f_format \'$request $remote_addr $request_time\'',
    access_log        => '/var/log/nginx/access.log f_format',
```

As soon as Graylog is up I see inside puppet-agent-nginx that configuration does not work due to inability to find a proper log_format.

Set log_format from inside nginx agent due to the problem with preppending the proper syntax a log_format in puppet-nginx configuration.

```bash
sed -i "1i log_format custom_format  '\$remote_addr - \$remote_user \$time_local \$request \$status \$body_bytes_sent \$http_referer';" /etc/nginx/sit
es-available/domain.com.conf
service nginx reload
service nginx restart
```

Configuring the input to display logs from source:

```bash
allow_override_date: true
bind_address: 0.0.0.0
expand_structured_data: false
force_rdns: false
max_message_size: 2097152
number_worker_threads: 16
override_source: <empty>
port: 5140
recv_buffer_size: 1048576
store_full_message: false
tcp_keepalive: false
tls_cert_file: <empty>
tls_client_auth: disabled
tls_client_auth_cert_file: <empty>
tls_enable: false
tls_key_file: <empty>
tls_key_password:********
use_null_delimiter: false
```

I'm switching access.log and error.log to be exposed on 5140 port for graylog service but it seems to not reach the target for any reason.

### Fallback

Remove from init.pp and update module.

```ruby
    access_log        => 'syslog:server=graylog:5140 custom_format',
    error_log         => 'syslog:server=graylog:5140',
```

You can watch logs by using basic terminal commands:

`tail -f /var/log/nginx/access.log`

### Summary

I think it lacks the proxy to expose puppet-agent-nginx to internet overriding the current domain.com.

Due to the amount of time invested in learning new concepts like Puppet (I'm used to Ansible), refreshing NGINX concepts (lot of time since my last config), fixing issues on-the-go and searching for documentation (scarce) in the internet about Puppet, and mostly the lack of time due to my current workload I have to provide this solution instead something more clear and working one. Will fix in later weeks.

Much of the issues I've found were almost everyone related to syntax and missing [documentation for puppet-nginx module](http://www.puppetmodule.info/github/voxpupuli/puppet-nginx/puppet_defined_types), which I find pretty poor.

Didn't have the time to test and add a healthcheck for puppet-agent-nginx service.

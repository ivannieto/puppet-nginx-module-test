#!/bin/bash

set -e

AGENT_NAME=puppet-agent-nginx

apt update

# Generate self-signed certificate
mkdir -p /etc/ssl/private
chmod 700 /etc/ssl/private
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/${AGENT_NAME}-selfsigned.key -out /etc/ssl/certs/${AGENT_NAME}-selfsigned.crt -batch
puppet agent --verbose --onetime --no-daemonize --summarize

# Add log_format to missing property from puppet-nginx generated file
sed -i "2i log_format custom_format  '\$remote_addr - \$remote_user \$time_local \$request \$status \$body_bytes_sent \$http_referer';" /etc/nginx/sites-available/domain.com.conf

cat /etc/nginx/sites-available/domain.com.conf

nginx -t

service nginx reload
service nginx restart

# This avoids container from exit with 0 value
tail -f /dev/null

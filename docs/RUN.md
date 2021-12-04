# Run instructions

## Requirements

- Docker ins talled in your system.

## Running

- Start the infrastructure.

  - `docker compose up -d`

- After agent has exited (or while container is in CREATED state) install required packages in Puppet server (latest versions gave me a headache, those are the ones that worked for me).

  - `docker exec puppet-server puppet module install puppetlabs-apt --8.1.0`
  - `docker exec puppet-server puppet module install puppet-nginx --version 3.2.0`

- Restart exited container to gather facts from Puppet server.

  `docker compose up -d`

- Module development (do this to apply changes in your NGINX configuration as the volume on your dev folder with the module manifest is routed to Puppet server).

  - `docker exec puppet-agent-nginx puppet agent --verbose --onetime --no-daemonize --summarize`

- Check connectivity

  - `docker exec puppet-agent-nginx curl https://domain.com -k`
  - `docker exec puppet-agent-nginx curl https://domain.com/resource2 -k`
  - `docker exec puppet-agent-nginx curl http://10.10.10.10` only puppet-agent-nginx has connectivity through HTTP internally
  - `docker exec puppet-agent-nginx curl http://20.20.20.20` only puppet-agent-nginx has connectivity through HTTP internally

- Turn down all services and networks in infrastructure.

  - `docker compose down`

- If you need to rebuild all services.

  - `docker compose up -d --force-recreate --build`

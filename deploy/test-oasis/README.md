# NOMAD Oasis test deployment

This directory contains a small Docker Compose deployment for a test NOMAD Oasis on a Linux VM.

It follows the official Oasis configuration layout:

- `docker-compose.yaml`
- `configs/nomad.yaml`
- `configs/nginx.conf`

## Configure

Copy the example environment and edit the values for your VM:

```sh
cp .env.example .env
```

Set `OASIS_HOST` to the DNS name or IP address that users can open in a browser. This value is used by NOMAD's login redirects, so it must match the externally reachable host.

For a plain local test keep `OASIS_SCHEME=http`. If you put HTTPS in front of this service later, set `OASIS_SCHEME=https` and keep the frontend proxy headers aligned.

After changing `configs/nginx.conf`, recreate the proxy container so Docker remounts the updated file:

```sh
docker compose up -d --force-recreate proxy
```

## Start

From this directory:

```sh
./start-test-oasis.sh
```

The script renders `configs/nomad.yaml`, pulls images, and starts the Compose stack.

Check the deployment with:

```sh
curl http://$OASIS_HOST/nomad-oasis/alive
curl http://$OASIS_HOST/nomad-oasis/api/info
```

The GUI is available at:

```text
http://<your-host>/nomad-oasis/gui/
```

## Stop

```sh
docker compose down
```

Managed data is stored in Docker volumes and under `.volumes/` in this directory.

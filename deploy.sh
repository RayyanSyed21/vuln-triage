#!/usr/bin/env bash
# CS3 Group 14: build the image and (re)start all five containers on the shared VM.
# Uses plain `docker` because the VM has no `docker compose` plugin.
# Host ports, all in our claimed block 1400-1409:
#   1400 api UI     1401 api app metrics     1402 api node exporter
#   1403 local UI   1404 local app metrics   1405 local node exporter
#   1406 prometheus 1407 grafana    1408 nginx path router (what ngrok points at)
set -euo pipefail
cd "$(dirname "$0")"

# .env holds HF_TOKEN and GRAFANA_PASSWORD. `set -a` exports everything it defines,
# so `-e HF_TOKEN` below passes the value without it ever appearing on a command line.
set -a; source .env; set +a
: "${HF_TOKEN:?missing in .env}" "${GRAFANA_PASSWORD:?missing in .env}"

NET=group14-net
IMG=group14/vuln-triage:latest

# One private network so Prometheus can reach the apps by name (api-product:8000 ...).
docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET"

docker build -t "$IMG" .

# Remove old copies so the script can be re-run after every code change.
for c in group14-api group14-local group14-prometheus group14-grafana group14-nginx; do
  docker rm -f "$c" >/dev/null 2>&1 || true
done

docker run -d --name group14-api --network "$NET" --network-alias api-product \
  --restart unless-stopped -e PRODUCT_MODE=remote -e GRADIO_ROOT_PATH=/api -e HF_TOKEN \
  -p 1400:7860 -p 1401:8000 -p 1402:9100 "$IMG"

docker run -d --name group14-local --network "$NET" --network-alias local-product \
  --restart unless-stopped -e PRODUCT_MODE=local -e GRADIO_ROOT_PATH=/local \
  -p 1403:7860 -p 1404:8000 -p 1405:9100 "$IMG"

docker run -d --name group14-prometheus --network "$NET" --network-alias prometheus --restart unless-stopped \
  -v "$PWD/Prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
  -p 1406:9090 prom/prometheus:v2.55.1

# Grafana's SQLite DB lives in RAM (tmpfs): on the shared VM's overloaded disk it hit
# "database is locked" and crash-looped. Nothing in it needs to persist, because the
# datasource and dashboard are re-created from Grafana/provisioning on every start.
docker run -d --name group14-grafana --network "$NET" --network-alias grafana --restart unless-stopped \
  -e GF_SERVER_ROOT_URL='%(protocol)s://%(domain)s/grafana/' -e GF_SERVER_SERVE_FROM_SUB_PATH=true \
  -e GF_SECURITY_ADMIN_PASSWORD="$GRAFANA_PASSWORD" \
  -v "$PWD/Grafana/provisioning:/etc/grafana/provisioning:ro" \
  --tmpfs /var/lib/grafana:mode=1777,size=512m \
  -p 1407:3000 grafana/grafana:11.3.0

# Started last, because nginx looks up the other containers' names when it boots.
docker run -d --name group14-nginx --network "$NET" --restart unless-stopped \
  -v "$PWD/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" \
  -p 1408:80 nginx:1.27-alpine

docker ps --filter name=group14- --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# CS3 runbook (Group 14, ports 1400-1409)

| Host port | What | Inside container |
|---|---|---|
| 1400 / 1401 / 1402 | API product: UI / app metrics / node exporter | 7860 / 8000 / 9100 |
| 1403 / 1404 / 1405 | Local product: UI / app metrics / node exporter | 7860 / 8000 / 9100 |
| 1406 | Prometheus | 9090 |
| 1407 | Grafana | 3000 |

## 1. Get onto the VM (on your Mac)

```bash
ssh -i ~/.ssh/cs3_key -p 2222 group14@melnibone.wpi.edu
```

melnibone resolves to a private campus address (10.128.x.x), so the WPI VPN must be on when off campus.

## 2. Clone and start everything (on the VM)

```bash
git clone https://github.com/<you>/vuln-triage.git && cd vuln-triage
git switch cs3/docker-monitoring
```

Put the secrets in a `.env` file in the repo folder. `deploy.sh` reads it, and it is gitignored:

```bash
printf 'HF_TOKEN=hf_...\nGRAFANA_PASSWORD=pick-something\n' > .env && chmod 600 .env
./deploy.sh    # builds the image (slow the first time) and starts all 4 containers
```

## 3. Check each piece (on the VM)

```bash
curl -s localhost:1401/metrics | grep ^triage_          # api app metrics
curl -s localhost:1402/metrics | grep ^node_cpu | head -3 # api node exporter
curl -s localhost:1406/api/v1/targets | grep -o '"health":"[a-z]*"'   # expect 4x up
```

## 4. Container IPs for the sheet

```bash
docker inspect -f '{{.Name}} {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -q --filter name=group14-)
```

## 5. Public URL (ngrok, one tunnel)

Free ngrok gives one domain, so the tunnel points at nginx (1408), which routes
`/api/`, `/local/` and `/grafana/` to the right container.

```bash
mkdir -p ~/bin && curl -sSL https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz | tar -xz -C ~/bin
read -rsp "ngrok token: " T && ~/bin/ngrok config add-authtoken "$T" && unset T
tmux new -d -s ngrok "~/bin/ngrok http 1408 --log stdout --log-format logfmt > ~/ngrok.log 2>&1"
grep -o "url=https://[^ ]*" ~/ngrok.log | tail -1
```

Current URL: https://unguided-chump-bottom.ngrok-free.dev (`/api/`, `/local/`, `/grafana/`)

## 6. Generate traffic for the report

Open each public URL and run 10 to 20 alerts from `samples.md`, plus a few empty submits and a few with a bad `HF_TOKEN`. That way every metric has data. Screenshot the "Group 14 - Vuln Triage" dashboard in Grafana.

## 7. Tear down

```bash
tmux kill-session -t ngrok
docker rm -f group14-api group14-local group14-prometheus group14-grafana group14-nginx
```

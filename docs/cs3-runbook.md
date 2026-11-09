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

## 5. Public URLs (ngrok)

Sign up at ngrok.com and copy your authtoken. Keep it out of the repo. Create `~/ngrok.yml` on the VM:

```yaml
version: 3
agent:
  authtoken: <YOUR_NGROK_TOKEN>
endpoints:
  - name: api-product
    upstream: {url: 1400}
  - name: local-product
    upstream: {url: 1403}
  - name: grafana
    upstream: {url: 1407}
```

```bash
tmux new -s ngrok 'ngrok start --all --config ~/ngrok.yml'
```

If the free plan rejects three endpoints at once, use Cloudflare quick tunnels instead. They need no account and count as "ngrok or similar":
`cloudflared tunnel --url http://localhost:1400`, run once per port.

## 6. Generate traffic for the report

Open each public URL and run 10 to 20 alerts from `samples.md`, plus a few empty submits and a few with a bad `HF_TOKEN`. That way every metric has data. Screenshot the "Group 14 - Vuln Triage" dashboard in Grafana.

## 7. Tear down

```bash
docker rm -f group14-api group14-local group14-prometheus group14-grafana
```

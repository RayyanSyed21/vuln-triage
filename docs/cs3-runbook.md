# CS3 runbook (Group 14, ports 1400-1409)

| Host port | What | Inside container |
|---|---|---|
| 1400 / 1401 | API product UI / metrics | 7860 / 8000 |
| 1402 / 1403 | Local product UI / metrics | 7860 / 8000 |
| 1404 | node-exporter | 9100 |
| 1405 | Prometheus | 9090 |
| 1406 | Grafana | 3000 |

## 1. Get onto the VM (on your Mac)

```bash
ssh -i ~/.ssh/cs3_key -p <PORT> student-admin@<HOST>
```

## 2. Clone and start everything (on the VM)

```bash
docker compose version          # confirm the compose plugin exists
git clone https://github.com/<you>/vuln-triage.git && cd vuln-triage
git switch cs3/docker-monitoring
```

Put the secrets in a `.env` file next to `docker-compose.yml`. Compose reads it automatically and it is gitignored:

```bash
printf 'HF_TOKEN=hf_...\nGRAFANA_PASSWORD=pick-something\n' > .env && chmod 600 .env
docker compose up -d --build    # the first build takes a while (torch + model)
docker compose ps
```

## 3. Check each piece (on the VM)

```bash
curl -s localhost:1401/metrics | grep ^triage_
curl -s localhost:1404/metrics | head
curl -s localhost:1405/api/v1/targets | grep -o '"health":"[a-z]*"'   # expect 3x up
```

## 4. Container IPs for the sheet

```bash
docker inspect -f '{{.Name}} {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker compose ps -q)
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
    upstream: {url: 1402}
  - name: grafana
    upstream: {url: 1406}
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
docker compose down
```

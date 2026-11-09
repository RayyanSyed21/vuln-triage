"""CS3: send realistic traffic to both public products so Grafana has data.

Mix per product: real alerts on its own backend, a few empty submits
(triage_empty_inputs_total), and a few requests on the *other* backend.
On the local product that means "Remote API" with no HF_TOKEN in that
container, which is a genuine error path (triage_errors_total).

Usage:  python traffic.py [rounds]     (default 3 rounds, about 15 min)
"""
import random
import sys
import threading
import time

from gradio_client import Client

BASE = "https://unguided-chump-bottom.ngrok-free.dev"
HEADERS = {"ngrok-skip-browser-warning": "1"}  # skip ngrok's free-plan interstitial

ALERTS = [
    "CVE-2024-3094: backdoor in xz-utils 5.6.0/5.6.1, sshd links liblzma, internet-facing build image.",
    "CVE-2021-44228 (Log4Shell): JNDI RCE in log4j-core 2.14.1, public API logs untrusted input.",
    "CVE-2023-4863: heap overflow in libwebp, used by our image upload service.",
    "CVE-2022-22965 (Spring4Shell): RCE in Spring Framework 5.3.17 on Tomcat, internal admin app.",
    "CVE-2023-44487: HTTP/2 Rapid Reset DoS in nginx 1.25.2 fronting the public website.",
    "npm audit: lodash 4.17.15 prototype pollution (CVE-2020-8203) in a dev-only build script.",
    "CVE-2024-6387 (regreSSHion): race condition RCE in OpenSSH 9.7p1 on bastion host.",
    "Dependabot: requests 2.25.0 leaks Proxy-Authorization header on redirect (CVE-2023-32681).",
    "Trivy: base image debian:11 has 14 LOW findings in unused locale packages.",
    "CVE-2023-34362: SQL injection in MOVEit Transfer, internet-facing file share.",
    "GitHub secret scanning: AWS access key committed to public repo 3 hours ago.",
    "CVE-2022-0778: infinite loop in OpenSSL BN_mod_sqrt via crafted certificate, internal service.",
]

PRODUCTS = {  # path -> (own backend, other backend)
    "/api/": ("Remote API", "Local model"),
    "/local/": ("Local model", "Remote API"),
}


def one_request(client, path, alert, backend):
    t = time.time()
    try:
        out = client.predict(alert, backend, round(random.uniform(0, 0.8), 2), api_name="/triage")
        first = out.splitlines()[0][:70] if out else ""
    except Exception as e:
        first = f"client error: {type(e).__name__}"
    print(f"{path:8} {backend:12} {time.time() - t:6.1f}s  {first}", flush=True)


def run_product(path, rounds):
    own, other = PRODUCTS[path]
    client = Client(BASE + path, verbose=False, headers=HEADERS)
    for _ in range(rounds):
        plan = [(a, own) for a in random.sample(ALERTS, 5)]
        plan += [("", own), (random.choice(ALERTS), other)]
        random.shuffle(plan)
        for alert, backend in plan:
            one_request(client, path, alert, backend)
            time.sleep(random.uniform(5, 25))  # spread out so the graphs show a shape


if __name__ == "__main__":
    rounds = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    threads = [threading.Thread(target=run_product, args=(p, rounds)) for p in PRODUCTS]
    # A short burst of 3 parallel local requests, so triage_in_progress goes above 1.
    burst = Client(BASE + "/local/", verbose=False, headers=HEADERS)
    threads += [threading.Thread(target=one_request, args=(burst, "/local/", a, "Local model"))
                for a in random.sample(ALERTS, 3)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    print("done", flush=True)

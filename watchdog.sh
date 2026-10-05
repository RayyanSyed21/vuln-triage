#!/usr/bin/env bash
#
# watchdog.sh — CS553 Case Study 2, Group 14
# Runs on linux.wpi.edu (inside the WPI network, so it can reach the VM
# that GitHub Actions cannot). Each run: check the product; if it is down,
# SSH into the VM and re-run bootstrap.sh to rebuild it.
#
set -uo pipefail

VM_HOST="paffenroth-23.dyn.wpi.edu"
SSH_PORT=22014
APP_URL="http://paffenroth-23.dyn.wpi.edu:8014"
MY_KEY="$HOME/cs553/cs553_vm"
DEFAULT_KEY="$HOME/cs553/student-admin_key"
BOOTSTRAP_URL="https://raw.githubusercontent.com/RayyanSyed21/vuln-triage/main/bootstrap.sh"
LOG="$HOME/cs553/watchdog.log"

stamp() { date '+%Y-%m-%d %H:%M:%S'; }
say() { echo "[$(stamp)] $*" >> "$LOG"; }

# 1. Is the product answering from outside?
if curl -fsS --max-time 15 "$APP_URL" >/dev/null 2>&1; then
    say "OK - app is up"
    exit 0
fi

say "DOWN - app not responding, starting recovery"

# 2. Pick a working key: ours first, default (post-wipe) as fallback.
KEY=""
for k in "$MY_KEY" "$DEFAULT_KEY"; do
    if ssh -i "$k" -p "$SSH_PORT" \
        -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout=10 -o BatchMode=yes \
        student-admin@"$VM_HOST" 'true' 2>/dev/null; then
        KEY="$k"
        say "reached VM with key: $(basename "$k")"
        break
    fi
done

if [ -z "$KEY" ]; then
    say "FAILED - VM unreachable on any key (host likely still rebuilding)"
    exit 1
fi

# 3. Re-provision: pull latest bootstrap and run it on the VM.
say "running bootstrap on VM"
ssh -i "$KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=accept-new \
    student-admin@"$VM_HOST" \
    "curl -fsSL '$BOOTSTRAP_URL' -o bootstrap.sh && HF_TOKEN='$(cat ~/cs553/hf_token 2>/dev/null)' bash bootstrap.sh" \
    >> "$LOG" 2>&1

if curl -fsS --max-time 20 "$APP_URL" >/dev/null 2>&1; then
    say "RECOVERED - app is back up"
else
    say "bootstrap ran but app still not answering externally"
fi

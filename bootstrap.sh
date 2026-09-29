#!/usr/bin/env bash
#
# bootstrap.sh — CS553 Case Study 2, Group 14
#
# Idempotent provisioning script. Brings a freshly-wiped VM back to a
# fully running state: our SSH key installed, dependencies present, both
# products deployed, and the Gradio service running under systemd on 8014.
#
# Safe to run on a blank machine, a fully-provisioned machine, or one
# stuck halfway. Every step checks before it acts. This is what the
# recovery watchdog runs; it is also step 3a of the assignment.
#
# Run ON the VM:   bash bootstrap.sh
#
set -euo pipefail

# --- config ---------------------------------------------------------------
REPO_URL="https://github.com/RayyanSyed21/vuln-triage.git"
APP_DIR="$HOME/vuln-triage"
VENV="$APP_DIR/.venv"
GRADIO_PORT=7860
PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOuZhtA0YWScGxZvgt39PIc23N0PLBmHjxygfvJtEvfW rayyan-cs553"

log() { echo ">>> [$(date +%H:%M:%S)] $*"; }

# --- 1. lock down SSH -----------------------------------------------------
# Ensure ONLY our key is trusted. On a fresh machine the default
# student-admin key is present; this removes it.
log "Securing authorized_keys"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
echo "$PUBKEY" > "$HOME/.ssh/authorized_keys"
chmod 600 "$HOME/.ssh/authorized_keys"

# --- 2. system packages ---------------------------------------------------
# Non-interactive or this hangs forever with nobody at the keyboard.
log "Installing system packages"
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
sudo -E apt-get update -y
sudo -E apt-get install -y python3-venv python3-pip git tmux

# --- 3. code --------------------------------------------------------------
log "Fetching latest code"
if [ -d "$APP_DIR/.git" ]; then
    git -C "$APP_DIR" pull --ff-only
else
    git clone "$REPO_URL" "$APP_DIR"
fi

# --- 4. python env --------------------------------------------------------
log "Building virtualenv"
if [ ! -d "$VENV" ]; then
    python3 -m venv "$VENV"
fi
# shellcheck disable=SC1091
source "$VENV/bin/activate"
pip install --upgrade pip
# CPU-only torch: no GPU on this box, and the CUDA build is ~2.5 GB.
pip install --index-url https://download.pytorch.org/whl/cpu torch
pip install gradio huggingface_hub python-dotenv transformers pytest

# --- 5. systemd service ---------------------------------------------------
# Runs the app independent of any SSH session and restarts it on crash
# or reboot. This is what makes recovery "start the machine" instead of
# "log in and babysit".
log "Installing systemd unit"
sudo tee /etc/systemd/system/vuln-triage.service >/dev/null <<UNIT
[Unit]
Description=Vuln Triage Gradio app (CS553 group 14)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$APP_DIR
Environment=GRADIO_SERVER_NAME=0.0.0.0
Environment=GRADIO_SERVER_PORT=$GRADIO_PORT
EnvironmentFile=-/etc/vuln-triage.env
ExecStart=$VENV/bin/python $APP_DIR/app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

# Optional: write HF token for the remote backend, if one was passed in.
if [ -n "${HF_TOKEN:-}" ]; then
    echo "HF_TOKEN=$HF_TOKEN" | sudo tee /etc/vuln-triage.env >/dev/null
    sudo chmod 600 /etc/vuln-triage.env
    log "wrote HF token env file"
fi

sudo systemctl daemon-reload
sudo systemctl enable vuln-triage.service
sudo systemctl restart vuln-triage.service

# --- 6. verify ------------------------------------------------------------
log "Waiting for the app to answer on :$GRADIO_PORT"
for i in $(seq 1 30); do
    if curl -fsS "http://localhost:$GRADIO_PORT" >/dev/null 2>&1; then
        log "UP — app is serving on port $GRADIO_PORT"
        exit 0
    fi
    sleep 2
done

log "FAILED — app did not come up in time; recent logs:"
sudo journalctl -u vuln-triage.service --no-pager -n 30
exit 1
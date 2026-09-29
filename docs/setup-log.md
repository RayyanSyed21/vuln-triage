# Case Study 2 — Setup Log

Group 14. VM: paffenroth-23.dyn.wpi.edu, SSH port 22014, Gradio port 8014.
User: student-admin. WPI VPN required from off campus.

## Mon Sep 28, 2:50pm ET — SSH access established (deliverable 1a)

- Downloaded student-admin_key from Canvas, chmod 600 (SSH rejects world-readable keys)
- Connected: ssh -i student-admin_key -p 22014 student-admin@paffenroth-23.dyn.wpi.edu
- Confirmed correct machine via hostname: group14

Initial authorized_keys contained exactly one entry, a single shared key
distributed to every group in the class:
  ssh-ed25519 AAAA...S8a rcpaffenroth@paffenroth-23

## Mon Sep 28, 2:55pm ET — Replaced the shared key

- Generated a dedicated passwordless ed25519 keypair on the dev machine:
  ssh-keygen -t ed25519 -f ~/.ssh/cs553_vm -C "rayyan-cs553"
  Passwordless because the automated recovery process must authenticate
  without a human present.
- Appended the public key over the existing default-key connection.
- Verified the new key in a SEPARATE session BEFORE removing anything.
  Removing the only working credential first would have locked us out
  with no way back in.
- Removed the shared key, leaving only rayyan-cs553 in authorized_keys.
- Confirmed lockdown: the default key now returns
  "Permission denied (publickey)".
- Added an ~/.ssh/config alias "cs553" so scripts and the recovery
  watchdog can reference the host without repeating flags.

Screenshots: docs/screenshots/

## Mon Sep 28, 3:10pm ET — Environment survey (deliverable 1b)

- Ubuntu 22.04.5 LTS (jammy), kernel 6.8.0-136, LXD container
- Python 3.10.12
- 2 vCPU, 4.0 GiB RAM, 2.0 GiB swap
- 1.8 TB disk, 1.2 TB free

Note: RAM is 4 GiB here versus 16 GiB on Hugging Face Spaces in Case
Study 1. Memory, not disk, is the binding constraint for the locally
executed model.

## Mon Sep 28, 3:15pm ET — Challenge: interactive apt prompts

apt paused on a needrestart dialog ("Daemons using outdated libraries")
requiring keyboard input. This would hang the automated recovery script
indefinitely, since recovery runs unattended over SSH.

Resolution: the bootstrap script sets
  DEBIAN_FRONTEND=noninteractive
  NEEDRESTART_MODE=a
and invokes apt-get with sudo -E so those variables propagate.

## Mon Sep 28, 3:20pm ET — Challenge: requirements.txt is platform-specific

requirements.txt was produced by pip freeze on the dev machine
(macOS, Python 3.13). It is not installable on the VM:

- audioop-lts==0.2.2 is a backport for Python 3.13, which removed the
  built-in audioop module. It does not apply to Python 3.10.
- torch==2.14.0 installed from the default index pulls roughly 2.5 GB of
  CUDA libraries onto a machine with no GPU.
- Several other pins (numpy 2.5.2, pandas 3.0.5) may lack 3.10 wheels.

Resolution: install CPU-only torch from https://download.pytorch.org/whl/cpu,
install remaining packages unpinned, then freeze on the target platform to
produce requirements-vm.txt. The bootstrap script installs from that file.

Lesson: a frozen dependency file is only valid for the platform it was
frozen on.

## Mon Sep 28, 3:22pm ET — VM dropped the SSH connection mid-session

"Connection to paffenroth-23.dyn.wpi.edu closed by remote host."

No action on our side caused this; the course hardware is deliberately
unstable. A long-running install would have died with the connection.

Resolution: run long operations inside tmux so they survive disconnects.
This is the same problem the deployment itself has, and the reason the
application runs under systemd rather than from an interactive shell.

## Tue Sep 29, ~1:20pm ET — Port forwarding gotcha

App bound to 8014 inside the VM returned HTTP 200 on localhost but
ERR_EMPTY_RESPONSE from outside. The host forwards external port 8014 to
the container's internal 7860. Fix: the app listens on 7860 inside the VM;
the outside world reaches it at 8014. Corrected GRADIO_PORT in bootstrap.sh.

## Tue Sep 29, ~1:40pm ET — Resilience test 1: process crash (Layer 1)

Killed the app's main process with kill -9. systemd (Restart=always)
restarted it within 8 seconds; curl returned HTTP 200 afterward. Confirms
Layer 1 recovery handles a crashed process with no external intervention.
Note: systemctl stop does NOT trigger restart (deliberate stop is not a
failure) — only crashes and non-zero exits do.

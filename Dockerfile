# CS3: one image, run twice (PRODUCT_MODE=remote and PRODUCT_MODE=local).
# 3.13 matches the venv requirements.txt was frozen from (audioop-lts, pandas 3 need >=3.11).
FROM python:3.13-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/opt/hf-cache

WORKDIR /app

# Deliverable 2a: node exporter as the apt package, inside each product
# container, serving machine metrics on 9100 (same as the professor's template).
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        prometheus-node-exporter && \
    rm -rf /var/lib/apt/lists/*

# CPU-only torch first, so the pip line below sees torch==2.14.0 already
# satisfied and does not pull the multi-GB CUDA build (the VM has no GPU).
RUN pip install torch==2.14.0 --index-url https://download.pytorch.org/whl/cpu

# Copy requirements alone before the code, so editing app.py does not
# invalidate this (slow) layer.
COPY requirements.txt .
RUN pip install -r requirements.txt

# Bake the local model into the image so the first local request does not
# have to download about 1 GB at runtime.
RUN python -c "from huggingface_hub import snapshot_download; snapshot_download('Qwen/Qwen2.5-0.5B-Instruct')"

COPY app.py .

# 7860 = Gradio UI, 8000 = app /metrics, 9100 = node exporter /metrics
EXPOSE 7860 8000 9100

# Two processes: node exporter in the background, the app in the foreground.
# exec makes python PID 1, so `docker stop` signals it directly.
# --no-collector.systemd: containers have no systemd, so that collector only logs errors.
CMD ["bash", "-c", "prometheus-node-exporter --web.listen-address=:9100 --no-collector.systemd & exec python app.py"]

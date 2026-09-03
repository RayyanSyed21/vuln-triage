import os
import time
import gradio as gr
from dotenv import load_dotenv
from huggingface_hub import InferenceClient

load_dotenv()

BACKENDS = ["Remote API", "Local model"]
REMOTE_MODEL = "google/gemma-3-4b-it"

client = InferenceClient(
    provider="auto",
    api_key=os.environ.get("HF_TOKEN"),
    timeout=30,
)

SYSTEM_PROMPT = (
    "You are a security triage assistant. Given a vulnerability alert, reply with "
    "exactly three lines:\n"
    "SEVERITY: one of LOW/MEDIUM/HIGH/CRITICAL\n"
    "WHY: one sentence\n"
    "FIX: one concrete action\n"
    "No preamble, no markdown."
)


def call_remote(alert, temp):
    resp = client.chat.completions.create(
        model=REMOTE_MODEL,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": alert},
        ],
        max_tokens=200,
        temperature=temp,
    )
    return resp.choices[0].message.content


def triage(alert, backend, temp):
    if not alert.strip():
        return "Paste an alert first."

    start = time.time()
    try:
        if backend == "Remote API":
            body = call_remote(alert, temp)
        else:
            body = "Local model not wired up yet (Step 5)."
    except Exception as e:
        body = f"{type(e).__name__}: {e}"

    elapsed = time.time() - start
    return f"{body}\n\n---\nBackend: {backend}\nLatency: {elapsed:.2f}s"


with gr.Blocks(title="Vuln Triage") as demo:
    gr.Markdown("# Vuln Triage\nPaste a dependency alert or scanner finding.")

    with gr.Row():
        with gr.Column(scale=1):
            backend = gr.Radio(
                choices=BACKENDS,
                value=BACKENDS[0],
                label="Model backend",
            )
            temp = gr.Slider(0, 1, value=0.7, step=0.05, label="Temperature")
            alert = gr.Textbox(
                label="Security alert",
                lines=8,
                placeholder="CVE-2024-1234: RCE in libfoo < 2.1.0 ...",
            )
            go = gr.Button("Triage", variant="primary")
        with gr.Column(scale=1):
            out = gr.Textbox(label="Result", lines=12)

    go.click(fn=triage, inputs=[alert, backend, temp], outputs=out)

if __name__ == "__main__":
    demo.launch()
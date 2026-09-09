import os
import time
import gradio as gr
from dotenv import load_dotenv
from huggingface_hub import InferenceClient

load_dotenv()

BACKENDS = ["Remote API", "Local model"]
REMOTE_MODEL = "google/gemma-3-4b-it"
LOCAL_MODEL = "Qwen/Qwen2.5-0.5B-Instruct"

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


_local_pipe = None


def get_local_pipeline():
    global _local_pipe
    if _local_pipe is None:
        from transformers import pipeline
        _local_pipe = pipeline("text-generation", model=LOCAL_MODEL)
    return _local_pipe


def call_local(alert, temp):
    pipe = get_local_pipeline()
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": alert},
    ]
    gen_kwargs = {"max_new_tokens": 200, "do_sample": temp > 0}
    if temp > 0:
        gen_kwargs["temperature"] = temp
    result = pipe(messages, **gen_kwargs)
    return result[0]["generated_text"][-1]["content"]


def triage(alert, backend, temp):
    if not alert.strip():
        return "Paste an alert first."

    start = time.time()
    try:
        if backend == "Remote API":
            body = call_remote(alert, temp)
        else:
            body = call_local(alert, temp)
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
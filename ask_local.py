from app import get_local_pipeline

QUESTION = (
    "Analyze my vuln-triage Gradio app (a security-alert triage tool with "
    "two backends: a remote HF Inference API call, and a local transformers "
    "pipeline running Qwen2.5-0.5B-Instruct on HF Spaces CPU Basic). "
    "Identify one meaningful improvement related to performance, "
    "reliability, scalability, cost, security, or maintainability."
)

if __name__ == "__main__":
    pipe = get_local_pipeline()
    result = pipe(
        [{"role": "user", "content": QUESTION}],
        max_new_tokens=200,
        do_sample=False,
    )
    print("\n----- LOCAL MODEL RESPONSE -----")
    print(result[0]["generated_text"][-1]["content"])
    print("---------------------------------\n")

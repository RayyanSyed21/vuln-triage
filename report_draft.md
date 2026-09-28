# Vuln Triage — Case Study 1 Report (Draft: sections a-f)

## a. Members
Rayyan Syed (solo)

## b. Product description, purpose, and target audience
Vuln Triage is a small web app that helps a security or DevOps team quickly
make sense of a raw vulnerability alert (e.g., a CVE description or a
dependency-scanner finding). The user pastes the alert text into a text box;
the app returns a three-line structured response: a severity rating
(LOW/MEDIUM/HIGH/CRITICAL), a one-sentence explanation of why, and one
concrete remediation step.

The target audience is practitioners who are triaging a high volume of
scanner output and need a fast, consistent first pass — e.g., an
on-call engineer or a junior security analyst deciding what to escalate
versus what can wait, rather than a replacement for expert judgment on
genuinely ambiguous or high-stakes findings.

The app offers two interchangeable backends, selectable via a radio toggle:
a remotely hosted LLM accessed through Hugging Face's Inference API, and a
small LLM executed locally on the same host serving the app. Both share
identical prompting logic so their outputs are directly comparable.

## c. Models used
**Remote backend — `google/gemma-3-4b-it`**
A 4-billion-parameter instruction-tuned decoder-only transformer from
Google's Gemma 3 family, accessed via Hugging Face's Inference Providers
(`InferenceClient` with `provider="auto"`, which routes the request to
whichever backing provider is available). It was chosen because it's small
enough to be cheap to serve remotely while still following structured
instructions reliably. Training data/procedure are Google's own (not
disclosed in full) — general web-scale pretraining followed by instruction
tuning; no custom fine-tuning or additional dataset was used for this
project.

**Local backend — `Qwen/Qwen2.5-0.5B-Instruct`**
A 500-million-parameter instruction-tuned decoder-only transformer from
Alibaba's Qwen2.5 family, run in-process via a Hugging Face `transformers`
`pipeline("text-generation", ...)`, loaded lazily on first use and cached
for the life of the process. Chosen specifically for its small size, since
the local backend has to run on the Space's CPU Basic hardware (2 vCPU,
16GB RAM, no GPU) with no dedicated inference infrastructure. Like the
remote model, it's used as-is with no fine-tuning — only prompted with the
same system prompt used for the remote backend.

Both backends receive an identical system prompt instructing them to
respond in the fixed SEVERITY/WHY/FIX format, so any difference in output
quality reflects the models themselves, not the prompting.

## d. Performance analysis
Measured live on the deployed Space (CPU Basic), using the same alert
(the xz-utils/CVE-2024-3094 backdoor) against both backends:

| | Remote API (gemma-3-4b-it) | Local model (Qwen2.5-0.5B-Instruct) |
|---|---|---|
| Latency | ~2.3-2.5s | ~18.4s |
| Format adherence | Followed the exact `SEVERITY:`/`WHY:`/`FIX:` format | Same content, looser formatting (e.g. `Severity:` instead of `SEVERITY:`) |
| Compute used | None on the Space — offloaded to HF's hosted infrastructure | Full CPU inference on the Space's own 2 vCPU |
| Cold-start cost | None (model always warm on HF's side) | First request after a restart also pays a one-time model download (~1GB) |

The roughly 8x latency gap is expected: the remote path offloads generation
to infrastructure built for serving 4B-parameter models quickly, while the
local path runs a smaller model but on general-purpose CPU with no GPU
acceleration — CPU matrix multiplication is simply much slower than what
dedicated inference serving provides, even for a model 8x smaller.

## e. Cost analysis (at ~1,000 users)
Two cost shapes worth calling out, since they scale completely differently:

**Hosting (fixed, either backend):** Hugging Face now requires a PRO
subscription ($9/month) to host any Gradio Space on CPU Basic hardware —
this changed mid-project (previously CPU Basic Spaces were free). This cost
is flat regardless of user count — 1 user or 1,000 users pay the same $9/mo
for hosting, until CPU Basic's 2 vCPU can no longer keep up with concurrent
local-model requests, at which point a paid hardware upgrade would be
needed.

**Inference (variable, remote backend only):** Assuming 1,000 users each
submit ~5 triage requests/day, at roughly 300-400 tokens per request
(prompt + response combined), that's on the order of 1.5-2M tokens/day,
or ~50-60M tokens/month. Hugging Face Inference Providers pricing varies
by which backing provider actually serves the request (routed
automatically via `provider="auto"`), but per-token rates for a model this
size are typically well under $1 per million tokens, putting a rough
monthly estimate in the tens of dollars — small at this scale, but unlike
hosting cost, it scales linearly with usage and could grow significantly
beyond 1,000 users or with heavier per-user usage. [Verify current
per-token rate at huggingface.co/pricing before finalizing this number.]

The local backend has no per-request inference cost at all beyond the
fixed hosting fee — its cost story is flat, the remote backend's is
usage-linear. At high enough scale, this crossover point is exactly the
kind of tradeoff a real deployment decision would hinge on.

## f. Comments and concerns
- **Dependency on an external API**: the remote backend's availability,
  latency, and cost are entirely outside this app's control. If Hugging
  Face's Inference Providers have an outage or change pricing/rate limits
  (as happened mid-project with Space hosting itself), the remote path
  breaks with no fallback (see extra-credit failover discussion if
  attempted).
- **Data privacy**: alert text pasted into the app — which may describe
  sensitive internal infrastructure (internet-facing status, specific
  packages/versions in a build image, etc.) — is sent to a third-party API
  for the remote backend. An organization with strict data-handling
  requirements might be limited to the local backend for this reason
  alone, despite its slower/less consistent output.
- **No authentication or rate limiting**: the Space is public with no
  login and no per-user rate limits, so anyone with the link can consume
  the remote API quota (and therefore cost) or tie up the local model's
  CPU.
- **No persistent logging**: the app is fully stateless — no triage
  history is saved, which limits its usefulness as an audit trail even
  though that's often valuable in a real security workflow.
- **Reliability of the local model's output format**: the local model
  answers correctly but doesn't always follow the exact requested format
  as reliably as the larger remote model — a real deployment would need
  either output validation/retry logic or a more forgiving downstream
  parser.

## g. [LLM only] Established LLM code/product analysis
**Model used:** Claude (Sonnet 5), via Claude Code

**Prompt:**
> Analyze my vuln-triage Gradio app (a security-alert triage tool with two
> backends: a remote HF Inference API call, and a local `transformers`
> pipeline running Qwen2.5-0.5B-Instruct on HF Spaces CPU Basic). Identify
> one meaningful improvement related to performance, reliability,
> scalability, cost, security, or maintainability.

**Response:**
> The most meaningful gap is around concurrency and scalability of the
> local backend. `call_local` lazily loads the model into a module-level
> global (`_local_pipe`) the first time it's called, with no lock — if two
> users hit "Local model" for the first time at nearly the same moment,
> both requests can race into loading the model simultaneously, wasting
> memory and CPU on the Space's already-limited 2 vCPU. More importantly,
> each local inference call is a synchronous, CPU-bound operation that
> took ~18 seconds in testing — for that entire duration it occupies a
> full CPU thread. On 2-vCPU CPU Basic hardware, that means only about two
> local-model requests can be served at once; at meaningful traffic (e.g.
> the 1,000-user case discussed in the cost analysis), requests would
> queue up badly, and users would see growing wait times with no
> indication why. I'd recommend two things: guard the lazy load with a
> `threading.Lock` so it only loads once even under concurrent
> first-requests, and set Gradio's queue concurrency limit for the
> local-model path explicitly (rather than relying on defaults), so the
> app degrades gracefully — e.g. showing a queue position — instead of
> silently stacking up slow requests.

## h. [LLM only] Same question, asked of the local/weaker model
**Model used:** Qwen2.5-0.5B-Instruct (this project's own local backend),
asked directly via a one-off script (`ask_local.py`) run on GitHub Actions

**Prompt:** identical to section g's prompt, word for word.

**Response:**
> To analyze the performance, reliability, scalability, cost, security,
> and maintainability of your Gradio app, let's break down each aspect:
>
> 1. **Performance**:
>    - The remote HF Inference API call is likely causing significant
>      delays due to network latency and potential high costs for data
>      transfer.
>    - The local transformers pipeline running Qwen2.5-0.5B-Instruct on HF
>      Spaces CPU Basic can be resource-intensive, potentially leading to
>      performance bottlenecks.
>
> 2. **Reliability**:
>    - Both backend systems (HF Inference API and Qwen2.5-0.5B-Instruct)
>      have their own inherent limitations in terms of reliability.
>    - The remote HF Inference API call might introduce errors or timeouts
>      that could affect the overall system's reliability.
>
> 3. **Scalability**:
>    - The remote HF Inference API call may not scale well as the number
>      of requests increases, which could lead to increased costs and
>      reduced efficiency.

## i. [Human only]
*(Rayyan to write — compare the two responses above: which was more
useful, accurate, and actionable; call out anything incorrect, vague, or
questionable; say which suggestions you'd actually implement and why.)*

## j. [Human only]
*(Rayyan to write — which model you'd choose for real users and why, and
whether that changes if cost, privacy, or reliability were the top
priority.)*

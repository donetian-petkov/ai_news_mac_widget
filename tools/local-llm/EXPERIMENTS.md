# Local model experiment log

One line per experiment: what changed, on what sample, what happened, and the decision. Read this before
trying anything, so nothing that already failed is tried again.

## How to test

- A change gets a 5–10 story check first.
- A full 40-story run happens only when that check shows a gain.
- Judge: `judge-tools.mjs` (blind, 6 criteria, worst error) and `judge-briefing.py`.
- One 40-story pool is noisy. The same summary setup scored 15 wins / 20 losses on one pool and
  6 wins / 32 losses on another.

## Infrastructure (bugs found, fixed, keep)

| Date | Change | Result | Decision |
|---|---|---|---|
| 10-20 | Qwen 3.6 27B / 9B / Gemma 12B | froze the Mac / fans blaring | Only Qwen 3.5 4B q4_K_M |
| 10-21 | llama-server prompt cache default | server grew to 8.3 GB, Mac swapped | `--cache-ram 512` |
| 10-21 | Ollama with Qwen 3.5 | forced to one request at a time | llama-server directly, 2 slots |
| 10-21 | Responses API path | model "thought out loud" into the summary | `--jinja --reasoning off` |
| 10-21 | App queue expiry 3 min, call limits 22–60 s | nearly every local job expired | Local defaults: 2 h expiry, 10 min calls |
| 10-21 | JSON schema on the Responses API | ignored by llama-server | Fixed-format local calls go as chat |
| 10-21 | Gate rewrote requests | kept the old length, requests rejected | Length recomputed |
| 10-21 | Port 8082 | already used by another service | Gate on 18082 |
| 10-21 | Click on a story already queued | dropped as a duplicate, waited behind the backlog | Promote the queued job |
| 10-22 | First `<article>` on a page | other stories' text used (video and live pages) | Use the best-matching article; skip pages under 34% headline overlap |
| 10-22 | Briefing, all candidates rated | first local briefing took 11 min | Top 20 rated on local |

## Quality experiments

| Date | Tool | Change | Sample | Result, local vs cloud | Decision |
|---|---|---|---|---|---|
| 10-21 | summary | cloud prompt as-is | 40 | 10/0/30 wins/ties/losses, major errors 31 vs 11 | replaced |
| 10-21 | summary | facts → checks → pick (kit) | 40 | 20/5/15, accuracy 29 vs 30 | ported to the app |
| 10-22 | summary | app pipeline with the merge step | 40 | 16/4/20, major errors 19 vs 10 | merge off (no gain, misattributions) |
| 10-22 | summary | + self-check + article fit | 40 | 15/5/20, major errors 14 vs 10 | keep |
| 10-22 | summary | same, today's pool | 40 | 6/2/32, major errors 17 vs 5; 7 missing; informative 2.1 vs 3.3 | the first step picks side facts; reframe |
| 10-22 | summary | first step asks the reader's question, 5 answers | 10 | (running) | |
| 10-21 | research | cloud prompt as-is | 40 | 0/0/40, major errors 37 vs 10 (invented sources) | replaced |
| 10-21 | research | + no-invention rules | 24 | 1/0/23, major errors 17 vs 5 | not enough |
| 10-22 | research | facts → checks → write note | 14 | 1/0/13, major errors 8 vs 2 | the writing step mixes facts up |
| 10-22 | research | the note is the checked facts | 14 | 3/0/11, major errors 5 vs 5 | keep; thin (informative 2.4 vs 4.1) |
| 10-21 | mood/type | cloud prompt | 40 | almost all empty or invalid | fixed labels |
| 10-22 | mood | labels held to the list | 40 | 9/18/13, major errors 11 vs 6 | keep |
| 10-22 | mood | same, today | 40 | 6/15/19, major errors 15 vs 4 | add label meanings (running) |
| 10-22 | type | labels held to the list | 40 | 1/31/8, major errors 7 vs 1 | keep |
| 10-22 | neutral title | JSON held to keys | 40 | 7 rewritten, 8 failed | rewrite step held too |
| 10-22 | neutral title | rewrite step held, no full stop | 40 | 14 rewritten, 0 failed | keep |
| 10-22 | neutral title | judge counts "kept the calm headline" | 40 | 7/18/15, major errors 8 vs 10 | at cloud level |
| 10-22 | Ask | cloud prompt + rules | 15 | 2/0/13, major errors 10 vs 3 | replaced |
| 10-22 | Ask | facts that answer → answer from them | 15 | 5/0/10 and 4/0/11, major errors 5 vs 6 and 4 vs 3 | keep; thin |
| 10-22 | briefing | cloud calls as-is | 1 | timed out, keyword fallback | replaced |
| 10-22 | briefing | AI-written digest | 1 | mixed unrelated stories, "injured" became "killed" | digest = top stories' own summaries |
| 10-22 | briefing | digest from summaries | 1 | digest accuracy 5 vs 5, 0 major errors; ranking 1 vs 4 (server stopped mid-run) | rerun ranking |

## Lessons

- A small model fails worst when it writes freely across many facts or stories. Facts it copies from
  the text and that code checks hold up.
- Every number above is one pool and one judge, so differences of ±3 wins are noise.
- Story-specific wording never goes into prompts: fix the error class with a rule or check.

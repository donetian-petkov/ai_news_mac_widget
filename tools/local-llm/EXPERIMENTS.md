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
| 10-22 | battery.sh sign-in failed in the local copy | every job request refused, the run carried on with nothing | Stop when a sign-in fails |
| 10-22 | Self-check, one call per candidate | each call re-read the article, ~10 calls a story | One call checks all candidates |
| 10-22 | Research and Ask skip the busy limit | a bulk research run carries the same task name as a click: model 97% busy, fans 5,400+ | Clicks one at a time above 40%; every request waits above 75% |

## Quality experiments

| Date | Tool | Change | Sample | Result, local vs cloud | Decision |
|---|---|---|---|---|---|
| 10-21 | summary | cloud prompt as-is | 40 | 10/0/30 wins/ties/losses, major errors 31 vs 11 | replaced |
| 10-21 | summary | facts → checks → pick (kit) | 40 | 20/5/15, accuracy 29 vs 30 | ported to the app |
| 10-22 | summary | app pipeline with the merge step | 40 | 16/4/20, major errors 19 vs 10 | merge off (no gain, misattributions) |
| 10-22 | summary | + self-check + article fit | 40 | 15/5/20, major errors 14 vs 10 | keep |
| 10-22 | summary | same, today's pool | 40 | 6/2/32, major errors 17 vs 5; 7 missing; informative 2.1 vs 3.3 | the first step picks side facts; reframe |
| 10-22 | summary | first step asks the reader's question, 5 answers, one-call self-check | 25 (live) | 3/0/23, major errors 6 vs 1; English stories 12 of 18 losses and 4 of 5 errors; informative 2.9 | fix translation and vagueness |
| 10-22 | summary | + translation with article context, model yes/no check, round-trip word check (50%), right script, most specific confirmed sentence, "unknown"-only sentences dropped | 3 of 10 | 1/0/2; 2 major errors: English half missing (checks rejected good translations) | drop the model's yes/no check |
| 10-22 | summary | code checks only (round trip 40%, script) | 4 of 10 | English back on 3 of 4; one cut short ("compared to..."); one empty sentence picked because headline names counted as specific | next row |
| 10-22 | summary | + cut-short or off-length translations rejected, retry without the article, only names not in the headline count as specific | 10 | 1/1/8 (same 10 before: 1/0/9), major errors 1 vs 2 before; English half on all 10 | keep; within noise on wins |
| 10-22 | summary | + ask again for a concrete new detail when the pick has none | 6 | all 6 word for word as before; the one retry found no fact that passed the checks; the cloud's sentences often carry the same facts and still win | removed; the gap is phrasing, not facts |
| 10-22 | type | + label meanings | 10 | dropped from the fix run (same code as the 40-story run) | |
| 10-22 | mood/type | name the subject first, then the label (local) | 4 of the 10 with major errors | moods unchanged (court stories still "uncertainty"); type 1 fixed, 1 worse | mood: stricter meanings instead |
| 10-22 | mood/type | + plain reports of trials, plans, announcements are neutral; uncertainty only when the story stresses doubt | 10 with major errors + 8 non-neutral that matched | mood matches cloud 15/18 (before 11/18): errors 9/10 (before 3/10), but 2 of 8 reviews/features flattened to neutral; type 15/18 (before 13/18), 4 fixed, 2 broken | keep; add a rule for reviews |
| 10-22 | mood | + a review or feature takes the mood of its verdict | 5 entertainment stories | the 2 flattened ones back to the cloud's label; Klara review now "curios" (cloud pesimistic) | keep; mood now matches the cloud on 17 of the 18 |
| 10-21 | research | cloud prompt as-is | 40 | 0/0/40, major errors 37 vs 10 (invented sources) | replaced |
| 10-21 | research | + no-invention rules | 24 | 1/0/23, major errors 17 vs 5 | not enough |
| 10-22 | research | facts → checks → write note | 14 | 1/0/13, major errors 8 vs 2 | the writing step mixes facts up |
| 10-22 | research | the note is the checked facts | 14 | 3/0/11, major errors 5 vs 5 | keep; thin (informative 2.4 vs 4.1) |
| 10-22 | research | same, today | 14 (live) | 5/0/9, major errors 9 vs 5; one note repeated a half-sentence 8 times, one pasted a cut-off excerpt | drop repeats and cut-off facts |
| 10-22 | research | + repeated, cut-off ("...") and broken-quote facts dropped | 5 of those with major errors | 2/0/3 (before 3/0/2), major errors 2 (before 5) | keep |
| 10-22 | research (judge) | judge also given other outlets' reports of the same event (research is meant to use them) | 14 (live run), 5 (fix) | 40-story run: 3/0/11, major errors 7 vs 2; the fix on 5: 2/0/3, major errors 4 (before 3) under this judge, 2 (before 5) under the old one | on 5 stories the two judges disagree: noise; the fix only removes text, so keep; a wider research run is needed |
| 10-21 | mood/type | cloud prompt | 40 | almost all empty or invalid | fixed labels |
| 10-22 | mood | labels held to the list | 40 | 9/18/13, major errors 11 vs 6 | keep |
| 10-22 | mood | same, today | 40 | 6/15/19, major errors 15 vs 4 | add label meanings |
| 10-22 | mood | + label meanings | 34 (live) | 5/19/10, major errors 7 vs 2 | keep; recheck in the fix run |
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
- Every number above is one pool and one judge, so differences of ±3 wins are noise. On 5 stories, two
  versions of the judge disagreed on 3 of 5 research errors: small research checks cannot show a gain.
- Story-specific wording never goes into prompts: fix the error class with a rule or check.

## 40-story run, 10-22 12:25 (today's news, code before the 13:15 commit)

| Tool | Local / tie / cloud | Major errors local vs cloud | Note |
|---|---|---|---|
| Summary | 3 / 2 / 29 (34 judged) | 7 vs 1 | English halves missing; facts often the same as the cloud's, wording worse |
| Title BG | 2 / 19 / 19 | 10 vs 0 | clarity 3.7 vs 4.9 |
| Title EN | 1 / 26 / 13 | 6 vs 0 | |
| Neutral title | 8 / 20 / 12 | 2 vs 11 | local ahead on errors |
| Research | 5 / 0 / 9 (old judge); 3 / 0 / 11 (judge with other outlets' reports) | 9 vs 5; 7 vs 2 | repeated and cut-off facts (fixed since) |
| Mood | 5 / 23 / 12 | 8 vs 2 | stricter meanings since: 17 of 18 checked match the cloud |
| News type | 0 / 31 / 9 | 8 vs 0 | subject first since: 15 of 18 match |
| Ask | 3 / 0 / 12 | 7 vs 6 | informative 2.7 vs 4.4 |
| Briefing | digest accuracy 5 vs 5, usefulness 2 vs 5, ranking 1 vs 4 | 0 vs 0 | ratings reused from 12:43; ranking is the weak part |


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
| 10-22 | Live judging used an old article cache | for today's stories the judge had ~100 characters of feed text and called supported details invented (and "cut off") | battery.sh fetches the articles before live judging; regraded: summary 5/5/30, major errors 11 vs 9 (the cloud makes them too), faithful 4.1 vs 4.2 |
| 10-22 | The summary step never read the article | it fetched the article only when the feed snippet was under 140 characters, so most summaries (local and cloud) were written from the snippet; on news-agency pages the best-matching <article> was a 76-character headline card | local: always fetch; longest matching <article>, else the page's paragraphs; 4,000 characters for local |
| 10-22 | Research and Ask skip the busy limit | a bulk research run carries the same task name as a click: model 97% busy, fans 5,400+ | Clicks one at a time above 40%; every request waits above 75% |
| 10-22 | Model server stalled mid-run (14:40) | no answer to health checks, memory pushed to swap (3 GB to 278 MB) while other apps held 5 of 6 GB of swap; the gate showed 1 running and 100% busy | restarted; model-watch.sh now restarts it after 90 s without an answer while work waits |

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
| 10-22 | summary | + keep the article's own wording where a sentence says it | 10 the local had lost | 5/0/5 (before 0/0/10), major errors 1 (before 1), clarity 4.5 (before 3.7), informative 3.1 (before 2.6) | gain; 40-story run |
| 10-22 | summary | same, 40 stories | 37 judged | 12/1/24 (old on the same: 3/2/27), clarity 4.4 (3.8), informative 2.9 (2.6), major errors 12 (6): 7 of the 12 a missing language half | the back-translation check threw out good translations: see next row |
| 10-22 | all local tools | the app's rules were written above every task; with them there, the model copied a Bulgarian sentence it was asked to translate back into English, so every back-translation check scored 0 | 1 sentence by hand | rules as a system message: translated correctly | rules go as a system message on shaped calls; the gate joins its rules to that message (the chat template allows one) |
| 10-22 | summary | own wording + rules as a system message + HTML codes decoded + Bulgarian letters only | 37 of 40 | 13/0/24 (old local on the same: 3/2/28), major errors 7 (6), clarity 4.2 (3.8), informative 2.7 (2.6); one-language halves 1 (before 7); the 7 majors are mostly Bulgarian wording slips (names, "ill swindler") | keep, committed |
| 10-22 | summary | same build, today's newer 40 (a harder pool) | 39 | 7/1/31, major errors 5 vs 3; one-language halves 0 | the gain on the first pool did not repeat; no old-code run on this pool to compare |
| 10-22 | summary | + keep who said it; a negation only when the text's matching sentence has one; mixed-alphabet words rejected | 10 losses from that run | 0/0/10 before and after, major errors 3 (before 2) | the "keep who said it" line removed; the negation and alphabet checks kept, since they stop an observed false claim ("the match will not take place") |
| 10-22 | summary | + "not only": a negated fact must keep the matching sentence's "only" | 1 sentence | the false claim is now rejected | keep |
| 10-22 | summary | local reads the article (always fetched; longest fitting <article>, else paragraphs; 4,000 chars) + the self-check names the main news | 10 losses, judge also given the right article | 3/0/7 (before 0/0/10), major errors 1 (before 3), informative 3.5 (2.2), faithful 5.0 (4.4); ~4 usable facts a story instead of 1-2 | keep, committed; 40-story run next |
| 10-22 | judge | fetch-articles.mjs picks the article the same way (it graded BTA stories against an unrelated card) | — | — | keep |
| 10-22 | summary | same build, today's 40 | 39 | 17/0/22 (before, same stories and judge: 5/5/29), major errors 10 (11), informative 3.3 (2.4), faithful 4.4 (4.1); the majors: Bulgarian wording slips, 2 missing Bulgarian halves, 1 claimed number stated as fact, 1 wrong institution | gain confirmed |
| 10-22 | summary | a fact with a number keeps the source its sentence names | 10 with serious errors | all summaries word for word the same; in the casualty story the source is named in an earlier sentence, which a same-sentence check cannot see | removed |
| 10-22 | summary | a name with its first letter slipped into Cyrillic ("Бouches-du-Rhône") gets the original spelling back before the checks | the 1 story that lost its Bulgarian half this way | both halves now (the Bulgarian still says "suffocated" for "drowned") | keep |
| 10-22 | type | + label meanings | 10 | dropped from the fix run (same code as the 40-story run) | |
| 10-22 | mood/type | name the subject first, then the label (local) | 4 of the 10 with major errors | moods unchanged (court stories still "uncertainty"); type 1 fixed, 1 worse | mood: stricter meanings instead |
| 10-22 | mood/type | + plain reports of trials, plans, announcements are neutral; uncertainty only when the story stresses doubt | 10 with major errors + 8 non-neutral that matched | mood matches cloud 15/18 (before 11/18): errors 9/10 (before 3/10), but 2 of 8 reviews/features flattened to neutral; type 15/18 (before 13/18), 4 fixed, 2 broken | keep; add a rule for reviews |
| 10-22 | mood | + a review or feature takes the mood of its verdict | 5 entertainment stories | the 2 flattened ones back to the cloud's label; Klara review now "curios" (cloud pesimistic) | keep; mood now matches the cloud on 17 of the 18 |
| 10-22 | type | when the local answer is "other", ask once more without it | 9 type errors of the 14:31 run | 5 "other" answers changed: 2 now match the cloud (world, culture), 1 close (world for politics), 2 still wrong (health, business) | keep: each "other" was already a major error |
| 10-22 | mood | rage meaning widened to strong condemnation and quoted outrage | 11 mood errors | the rage stories still came out uncertainty or neutral; 0 of 11 fixed | reverted |
| 10-21 | research | cloud prompt as-is | 40 | 0/0/40, major errors 37 vs 10 (invented sources) | replaced |
| 10-21 | research | + no-invention rules | 24 | 1/0/23, major errors 17 vs 5 | not enough |
| 10-22 | research | facts → checks → write note | 14 | 1/0/13, major errors 8 vs 2 | the writing step mixes facts up |
| 10-22 | research | the note is the checked facts | 14 | 3/0/11, major errors 5 vs 5 | keep; thin (informative 2.4 vs 4.1) |
| 10-22 | research | same, today | 14 (live) | 5/0/9, major errors 9 vs 5; one note repeated a half-sentence 8 times, one pasted a cut-off excerpt | drop repeats and cut-off facts |
| 10-22 | research | + repeated, cut-off ("...") and broken-quote facts dropped | 5 of those with major errors | 2/0/3 (before 3/0/2), major errors 2 (before 5) | keep |
| 10-22 | research (judge) | judge also given other outlets' reports of the same event (research is meant to use them) | 14 (live run), 5 (fix) | 40-story run: 3/0/11, major errors 7 vs 2; the fix on 5: 2/0/3, major errors 4 (before 3) under this judge, 2 (before 5) under the old one | on 5 stories the two judges disagree: noise; the fix only removes text, so keep; a wider research run is needed |
| 10-23 | research | committed build (article read in full, paragraphs when the <article> is a card) | 10 of the 14:31 run | 1/0/9 before and after; informative 2.9 (2.5), faithful 3.8 (3.4), major errors 4 (3); one note copied "&ldquo;" | no gain in wins; HTML codes now decoded for research too |
| 10-21 | mood/type | cloud prompt | 40 | almost all empty or invalid | fixed labels |
| 10-22 | mood | labels held to the list | 40 | 9/18/13, major errors 11 vs 6 | keep |
| 10-22 | mood | same, today | 40 | 6/15/19, major errors 15 vs 4 | add label meanings |
| 10-22 | mood | + label meanings | 34 (live) | 5/19/10, major errors 7 vs 2 | keep; recheck in the fix run |
| 10-22 | type | labels held to the list | 40 | 1/31/8, major errors 7 vs 1 | keep |
| 10-22 | neutral title | JSON held to keys | 40 | 7 rewritten, 8 failed | rewrite step held too |
| 10-22 | neutral title | rewrite step held, no full stop | 40 | 14 rewritten, 0 failed | keep |
| 10-22 | title BG/EN | story text in view, meaning not word by word, alphabet/length/back-translation checks | 7 of the 10 with major errors | 2 better, 2 worse, 3 the same | no gain |
| 10-22 | title BG/EN | + two translations (with and without the story), keep the one whose meaning comes back best; leave out below half | 10 with major errors | 0/5/15, major errors 13 (4 left out, which the judge counts as major) vs 10 before; the kept translations had the same mistakes ("exercise" → "female student") | reverted; a limit of the 4B model, the patch is in the scratchpad |
| 10-22 | neutral title | judge counts "kept the calm headline" | 40 | 7/18/15, major errors 8 vs 10 | at cloud level |
| 10-22 | Ask | cloud prompt + rules | 15 | 2/0/13, major errors 10 vs 3 | replaced |
| 10-22 | Ask | facts that answer → answer from them | 15 | 5/0/10 and 4/0/11, major errors 5 vs 6 and 4 vs 3 | keep; thin |
| 10-22 | Ask | facts cover why it matters too; main point first, then why; the checked summary is used when no fact is found; no lists of what the text leaves out | 10 (same as the 40-story run) | 3/0/7 (before 2/0/8), major errors 3 (before 5), informative 3.2 (before 3.0); all 10 answered with briefings running, none timed out | keep; still thin on why it matters |
| 10-22 | briefing | cloud calls as-is | 1 | timed out, keyword fallback | replaced |
| 10-22 | briefing | AI-written digest | 1 | mixed unrelated stories, "injured" became "killed" | digest = top stories' own summaries |
| 10-22 | briefing | digest from summaries | 1 | digest accuracy 5 vs 5, 0 major errors; ranking 1 vs 4 (server stopped mid-run) | rerun ranking |
| 10-22 | briefing | built at the same moment as the cloud (earlier runs compared different 24-hour windows) | 1 | digest accuracy 5 vs 5, usefulness 2 vs 5, ranking 2 vs 4; 529 s vs 38 s | the cloud's top 3 (PHP alert, Zelensky, diesel tanker) were never rated: the keyword score kept them out of the local 20 |
| 10-22 | briefing | each reason before its score | 1 | accuracy 4, usefulness 2, ranking 2; 531 s | no gain, reverted |
| 10-22 | briefing | scores only (reasons ~320 tokens a story), 8 stories a call, as many stories as the cloud | 1 | 70 rated (PHP alert, Zelensky now scored), 480 s; accuracy 5, usefulness 2, ranking 2, storylines 2 (before 4), 1 major error; scores coarse (0-3, many ties), a house fire with one death got severity 3 | no gain, reverted; the scores themselves are the limit |

## Lessons

- A small model fails worst when it writes freely across many facts or stories. Facts it copies from
  the text and that code checks hold up.
- Live results before 10-22 15:00 may have been judged without the article (old cache): read them with care.
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

## 40-story run, 10-22 14:31 (code with the rules fix, judged with the articles except where noted)

| Tool | Local / tie / cloud | Major errors local vs cloud | Morning run (12:25) |
|---|---|---|---|
| Summary | 5 / 5 / 30 (regraded with articles) | 11 vs 9 | 3 / 2 / 29, 7 vs 1 (no articles) |
| Title BG | 0 / 25 / 15 | 3 vs 1 | 2 / 19 / 19, 10 vs 0 |
| Title EN | 2 / 20 / 18 | 5 vs 1 | 1 / 26 / 13, 6 vs 0 |
| Neutral title | 9 / 17 / 14 | 7 vs 12 | 8 / 20 / 12, 2 vs 11 |
| Research | 5 / 0 / 10 | 7 vs 4 | 5 / 0 / 9, 9 vs 5 |
| Mood | 9 / 13 / 18 | 11 vs 10 | 5 / 23 / 12, 8 vs 2 |
| News type | 3 / 31 / 6 | 9 vs 3 | 0 / 31 / 9, 8 vs 0 |
| Ask | 6 / 0 / 9 | 3 vs 8 | 3 / 0 / 12, 7 vs 6 |
| Briefing | digest accuracy 5 vs 5, usefulness 3 vs 5, ranking 3 vs 4 | 0 vs 0 | usefulness 2, ranking 1 |

Per-story tools took 2,921 s local vs 1,073 s cloud; briefing 553 s vs 114 s. The final grading was run by hand:
battery.sh was edited while it ran, and bash read the shifted file ("line 70: n: command not found").
Never edit a script that is running.


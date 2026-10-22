# Local model test kit

Tests whether a small model running on the Mac can do the app's AI work as well as the cloud model,
without loading the Mac. Nothing here is wired into the app yet.

## Model and server

- **Model:** Qwen 3.5 4B, `q4_K_M` GGUF, about 3.3 GB on disk, pulled with Ollama: `ollama pull qwen3.5:4b-q4_K_M`.
- **Server:** `start-server.sh` runs the llama-server that ships inside Ollama, with 3 slots and a 512 MB prompt cache.
  - Ollama itself forces Qwen 3.5 to one request at a time.
  - The default llama-server prompt cache grew the server to 8.3 GB in testing.
- **Ruled out:**
  - Qwen 3.6 27B froze the Mac.
  - Qwen 3.5 9B and Gemma 4 12B made the fans blare.
  - Gemini Nano has no Bulgarian.
  - Apple Foundation Models has no Bulgarian.
  - The Apple Neural Engine is about 5 times slower and has no JSON output.

## Summary pipeline (`lean.mjs`)

1. **Read the whole article.** The model reads the fetched article, up to 6,000 characters, not just the feed snippet. The snippet is a median of 245 characters.
2. **List facts.** The model lists up to 3 facts in the headline's language.
   - Straight quotes in the article are swapped for „ “, because a straight quote ends the JSON string mid-fact.
   - Caution words such as "може да", "alleged" and "trying to" must stay (`guides/facts.md`).
3. **Check the facts in code.** A fact is dropped if:
   - it has 5 words or fewer, or more than 22;
   - it is cut off;
   - it is a remark about the text itself;
   - it has unbalanced quotes;
   - it names people or numbers that are not in the article. For English articles only the numbers are checked, because names come back transliterated.
   - A fact must also be at least half new beyond the headline, or 60% for question headlines, which also may not come back as a claim.
4. **Second try.** If no fact survives, the model is asked once more, for facts the headline leaves out.
5. **Write the summary.** One call writes one sentence from the best facts.
   - It is kept only if it passes the same checks and keeps every caution word.
   - Otherwise the best single fact is the summary.
   - Bulgarian stories get a Bulgarian summary and English stories an English one, as the app does in bilingual mode.

## Limits that hold however much news arrives (`pool()` in `lean.mjs`)

- At most `PAR` stories in work at once (default 3; tested at 2).
- The model may be busy at most `BUSY_SHARE` of any minute (default 0.6; tested at 0.4). Above that, new stories wait.
- At most `QUEUE_MAX` stories wait (60). Beyond that the oldest are skipped and keep the cloud summary or none.
- A story that waited longer than `STORY_DEADLINE_MS` (20 minutes) is skipped.
- Every call has a 45-second limit, and the server's health is checked before each story.
- New work pauses while:
  - macOS reports serious heat;
  - free memory is under 6 GB;
  - or swap has grown by 1 GB since the start.

`guard.sh` is a second safety net. It stops the run and the server if free memory falls under 6 GB, swap grows by 1.5 GB, or free disk falls under 15 GB. Fans are not a trigger.

## Running it

```
bash build-tools.sh                       # bin/thermal, bin/fans (read-only helpers)
./start-server.sh &                       # model server on 127.0.0.1:8081
./build-pool.py 40 12                     # data/pool.json + data/cloud.json from the app's database
POOL=pool.json ARTS=articles.json node fetch-articles.mjs
bash guard.sh >> data/guard.log &
LLAMA_URL=http://127.0.0.1:8081 PAR=2 BUSY_SHARE=0.4 ARTICLE=1 ONLY_IDS=data/pool-ids.txt node lean.mjs data/run.json
OPENAI_API_KEY=... EXPECT=40 node judge.mjs data/run.json.live.jsonl data/judge.json   # judges each story as it lands
```

`judge.mjs` shows the cloud model the article, the headline and the two summaries in random order, without saying which is which.

## Running the app's own AI tools on the local model

`gate.mjs` sits between any client and the model server and enforces the same limits for the app's own calls:
2 requests at once, busy at most 40% of a minute, at most 60 waiting (more are refused with 503), and a time
limit per request; requests whose client gave up are dropped. A copy of the backend (`dist-local`, its own
database copy and port) with `AI_PROVIDER=local` and `LOCAL_LLM_BASE_URL=http://127.0.0.1:8082/v1` runs every
AI tool through the gate; a second copy on the cloud model gives the reference. `ws-tools.mjs` triggers the
on-demand tools (mood, news type, topic labels, Ask) over the app's socket; `judge-tools.mjs` grades every
tool's two outputs blind on six criteria (faithful, hedging, informative, specific, clarity, format, 1-5 each)
plus the worst error (none/minor/major).

Found so far:
- The app drops an AI job that waits more than 3 minutes in its queue (`AI_JOB_TTL_MS`, default 180 s) and
  times calls out after 22-45 s. At local speed nearly every job expired; a local provider needs far longer.
- Through the Responses API the model "thinks out loud" and the app saved that text as the summary. The server
  must run with its own chat template and thinking off (`--jinja --reasoning off`, in `start-server.sh`).
- The app's keyword matching needs an embeddings model, which the local server does not provide.

## Results so far

The pool is the 40 newest stories from 11 sources, 15 of them in English. The reference is the cloud
model (gpt-6-luna) running the same tool in a copy of the app. Outputs were graded blind by `judge-tools.mjs`.
"Before" is the app's cloud prompt on the local model; "after" is the local pipeline now in the app.

| Tool (stories) | Before: local / tie / cloud, major errors L/C | After: local / tie / cloud, major errors L/C |
|---|---|---|
| Summary (40) | 10 / 0 / 30, 31 / 11 | 15 / 4 / 21, 20 / 10 |
| Research (14) | 0 / 0 / 24, 23 / 3 | 3 / 0 / 11, 5 / 5 |
| Neutral title (~22) | 0 / 0 / 21, 21 / 12 (none produced) | 8 / 0 / 15, 12 / 12 |
| Mood (40) | 0 / 0 / 40, 40 / 5 (none saved) | 9 / 18 / 13, 11 / 6 |
| News type (40) | 0 / 0 / 40, 40 / 3 (none saved) | 2 / 33 / 5, 6 / 4 |
| Ask (15) | 2 / 0 / 13, 10 / 3 | 5 / 0 / 10, 5 / 6 |
| Title translation BG (40) | 0 / 28 / 12, 9 / 2 | not changed |
| Title translation EN (40) | 3 / 17 / 20, 11 / 6 | not changed |

The local model now makes about as many major errors as the cloud. In research, Ask and neutral titles
the cloud still writes richer text. Speed: a research click returns in 7-10 s; background work runs inside
the gate's limits (2 at once, model busy at most 40% of a minute).

Not done yet: the briefing (ratings, grouping, digest) on the local model, alert rules, the Android app,
and a switch and status for the local model in the app's settings.

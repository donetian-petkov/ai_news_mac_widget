# Are two reports about the same event?

You get two news headlines with a line of text each. Decide how they relate:
- "same": both report the very same happening (one event, possibly told by different outlets or with different details).
- "related": different happenings in one ongoing situation (the start and the end of one search, two statements in one dispute, two attacks in one war).
- "unrelated": anything else. Sharing a person, a country or a topic is not enough.

Sports and entertainment stories are never related to war, politics or the economy.
Answer with JSON: {"relation":"same|related|unrelated"}

Examples (invented)
A: Пожар изпепели склад край Примерово / B: Огнеборци гасиха цяла нощ склад в Примерово
Answer: {"relation":"same"}
A: Министърът обяви нов закон за пътищата / B: Опозицията критикува промените в пътния закон
Answer: {"relation":"related"}
A: Министърът посети болница в Примерово / B: Министърът обяви нов закон за пътищата
Answer: {"relation":"unrelated"}

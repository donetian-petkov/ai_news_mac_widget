# Are two reports about the same event?

You get two news headlines with a line of text each. Decide how they relate:
- "same": both report the very same happening (one event, possibly told by different outlets or with different details).
- "related": different happenings in one ongoing situation (the start and the end of one search, two statements in one dispute, two attacks in one war).
- "unrelated": anything else. Sharing a person, a country or a topic is not enough.

Sports and entertainment stories are never related to war, politics or the economy.
Answer with JSON: {"relation":"same|related|unrelated"}

Examples
A: Съдът остави в ареста момчето, задържано за убийството на майка си / B: Пращал снимки на мъртвата си майка: шокиращи подробности за убийството в Пловдив
Answer: {"relation":"same"}
A: В Барселона отхвърлили оферта от 250 милиона евро за Ламин Ямал / B: Босът на Барселона каза истината за Ямал
Answer: {"relation":"related"}
A: Тръмп с тежко предупреждение към Париж / B: Тръмп унижи публично Мелания
Answer: {"relation":"unrelated"}

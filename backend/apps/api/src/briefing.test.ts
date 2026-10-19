import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  buildBriefing,
  clusterStories,
  createBriefingStore,
  levelOf,
  applyGrouping,
  parseAiRatings,
  parseDigest,
  parseStorylines,
  pickVaried,
  ruleRating,
  scoreOf,
  type BriefingStory,
  type RatedStory
} from './briefing.js';

const at = (h: number, m = 0) => new Date(2026, 9, 15, h, m).getTime();
const hour = { startMs: at(13), endMs: at(14) };

function story(overrides: Partial<BriefingStory>): BriefingStory {
  return { id: 'x', title: 'Story', feedUrl: 'feed-a', publishedMs: at(13, 30), ...overrides };
}

describe('ruleRating', () => {
  it('rates a deadly disaster above a sports story and quotes the words behind each score', () => {
    const disaster = ruleRating(story({ title: 'School roof collapses in northwestern Pakistan, killing at least 29 people', source: 'Al Jazeera' }), [], hour);
    const sports = ruleRating(story({ title: '"Това е война": Каналът на Реал Мадрид с жестока атака преди Ел Класико' }), [], hour);
    expect(disaster.dimension).toBe('environment');
    expect(sports.dimension).toBe('sports');
    expect(scoreOf(disaster.scores)).toBeGreaterThan(scoreOf(sports.scores));
    expect(disaster.notes.severity).toContain('killing at least 29');
    expect(disaster.notes.coverage).toBe('Only Al Jazeera reports it');
  });

  it('names the sources, the tracked topic and the region that matched', () => {
    const lead = story({ title: 'България и Украйна обсъждат ударите по руски рафинерии', source: 'A' });
    const rating = ruleRating(lead, [story({ source: 'B' }), story({ source: 'C' })], hour, {
      localTerms: ['българ'],
      trackedTerms: ['украйна', 'AI'],
      region: 'Bulgaria'
    });
    expect(rating.scores.coverage).toBe(2);
    expect(rating.scores.relevance).toBe(2);
    expect(rating.notes.coverage).toBe('Reported by A, B, C');
    expect(rating.notes.relevance).toBe('Mentions your topic “украйна” and Bulgaria “България и Украйна…”');
  });

  it('sees reach in stories that involve several countries', () => {
    const rating = ruleRating(story({ title: 'Зеленски: Почваме пак да удряме руските рафинерии', summary: 'Украйна ще продължи да удря руските рафинерии.' }), [], hour);
    expect(rating.scores.scale).toBe(2);
    expect(rating.notes.scale).toMatch(/several countries/);
  });

  it('picks up what makes a story interesting', () => {
    const rating = ruleRating(story({ title: 'Scientists discover a record-breaking deep sea fish' }), [], hour);
    expect(rating.scores.interest).toBeGreaterThan(0);
    expect(rating.notes.interest).toContain('discover');
  });
});

describe('scores and levels', () => {
  const scores = { severity: 3, scale: 0, urgency: 0, interest: 3, coverage: 0, relevance: 0 };

  it('maps scores to levels', () => {
    expect(levelOf(75)).toBe('critical');
    expect(levelOf(55)).toBe('high');
    expect(levelOf(30)).toBe('notable');
    expect(levelOf(10)).toBe('routine');
  });

  it('lets one strong criterion carry a story, and more lift it further', () => {
    const none = { severity: 0, scale: 0, urgency: 0, interest: 0, coverage: 0, relevance: 0 };
    expect(scoreOf({ ...none, severity: 3 })).toBe(65);
    expect(levelOf(scoreOf({ ...none, severity: 3 }))).toBe('high');
    expect(scoreOf({ ...none, severity: 3, scale: 3, urgency: 3 })).toBeGreaterThan(80);
    // Without anything happening now it stays just below Critical.
    expect(scoreOf({ ...none, severity: 3, scale: 3 })).toBe(69);
    expect(scoreOf(none)).toBe(0);
  });

  it('follows the weights relative to each other', () => {
    const onlyInterest = { severity: 0, scale: 0, urgency: 0, interest: 5, coverage: 0, relevance: 0 };
    expect(scoreOf(scores, onlyInterest)).toBe(65);
    expect(scoreOf({ ...scores, interest: 0 }, onlyInterest)).toBe(0);
    expect(scoreOf(scores, { ...onlyInterest, interest: 0 })).toBe(0);
  });
});

describe('clusterStories', () => {
  it('merges the same event from several sources and leads with the most informative one', () => {
    const clusters = clusterStories([
      story({ id: 'nyt', title: 'Zelensky Says Ukraine Will Resume Strikes on Russian Oil Refineries', source: 'NYT', publishedMs: at(13, 5) }),
      story({ id: 'aj', title: 'Ukraine to resume strikes on Russian oil refineries, Zelensky says', source: 'AJ', summary: 'Detail', publishedMs: at(13, 20) }),
      story({ id: 'other', title: 'Messi’s Inter Miami reach playoff', publishedMs: at(13, 10) })
    ]);
    expect(clusters).toHaveLength(2);
    const ukraine = clusters.find(cluster => cluster.story.id === 'aj');
    expect(ukraine?.related.map(s => s.id)).toEqual(['nyt']);
  });

  it('merges reports that spell names in another script or quote other lines of one statement', () => {
    const clusters = clusterStories([
      story({ id: 'tesla-a', title: 'Първата летяща кола е тук: Tesla представи Roadster (ВИДЕО)', link: 'a' }),
      story({ id: 'tesla-b', title: '"Тесла" демонстрира летяща версия на модела си "Роудстър"', link: 'b' }),
      story({ id: 'pm-a', title: 'Костов, Борисов, Петков и Денков призоваха Радев да защити националната сигурност', link: 'c' }),
      story({ id: 'pm-b', title: 'Костов, Борисов и Петков: Мирът не се гарантира с надеждата, че Путин ще ни пощади', link: 'd' }),
      story({ id: 'other', title: 'Радев: Борисов носи отговорност за бюджета', link: 'e' }),
      story({ id: 'sport', title: 'Стоичков избухна след драмата на ЦСКА. Посочи виновника', link: 'f' })
    ]);
    const groups = clusters.map(cluster => [cluster.story.id, ...cluster.related.map(s => s.id)].sort());
    expect(groups).toHaveLength(4);
    expect(groups).toContainEqual(['tesla-a', 'tesla-b']);
    expect(groups).toContainEqual(['pm-a', 'pm-b']);
  });
});

const entry = (id: string, score: number, dimension: RatedStory['rating']['dimension']): RatedStory => ({
  story: story({ id, title: id, source: id }),
  related: [],
  rating: {
    scores: { severity: 0, scale: 0, urgency: 0, interest: 0, coverage: 0, relevance: 0 },
    notes: {},
    dimension,
    impacts: {},
    ratedBy: 'ai'
  },
  score,
  level: levelOf(score)
});

describe('pickVaried', () => {
  it('stops one area from taking over', () => {
    const picked = pickVaried([
      entry('s1', 90, 'security'),
      entry('s3', 80, 'security'),
      entry('s4', 75, 'security'),
      entry('e1', 40, 'economy'),
      entry('h1', 30, 'health')
    ], 4);
    expect(picked.map(p => p.story.id)).toEqual(['s1', 's3', 'e1', 'h1']);
  });

  it('fills up from the capped area when nothing else is left', () => {
    const picked = pickVaried([entry('s1', 90, 'security'), entry('s2', 80, 'security'), entry('s3', 70, 'security')], 3);
    expect(picked).toHaveLength(3);
  });
});

describe('applyGrouping', () => {
  it('folds duplicate reports into the strongest one and groups storylines of different events', () => {
    const groups = parseStorylines(JSON.stringify({
      duplicates: [['nyt', 'bg'], ['ghost', 'oman']],
      storylines: [{ label: 'Black Sea security', ids: ['drone', 'command'] }, { label: 'Gulf ties', ids: ['oman'] }]
    }));
    const grouped = applyGrouping([
      entry('bg', 80, 'security'), entry('nyt', 70, 'security'),
      entry('drone', 60, 'security'), entry('command', 40, 'politics'), entry('oman', 30, 'politics')
    ], groups);
    expect(grouped.map(g => g.story.id)).toEqual(['bg', 'drone', 'command', 'oman']);
    expect(grouped[0].related.map(s => s.id)).toEqual(['nyt']);
    expect(grouped.map(g => g.storyline)).toEqual([undefined, 'Black Sea security', 'Black Sea security', undefined]);
    expect(parseStorylines('nope').duplicates).toEqual([]);
  });

  it('keeps a sports story out of a storyline about something else', () => {
    const groups = parseStorylines(JSON.stringify({
      storylines: [{ label: 'Ukraine war', ids: ['starlink', 'ships', 'football'] }, { label: 'CSKA', ids: ['cska', 'coach'] }]
    }));
    const grouped = applyGrouping([
      entry('starlink', 60, 'politics'), entry('ships', 46, 'society'), entry('football', 43, 'sports'),
      entry('cska', 30, 'sports'), entry('coach', 28, 'sports')
    ], groups);
    expect(grouped.map(g => g.storyline)).toEqual(['Ukraine war', 'Ukraine war', undefined, 'CSKA', 'CSKA']);
  });

  it('ignores a duplicate list so long it must be a whole topic, not one happening', () => {
    const groups = parseStorylines(JSON.stringify({ duplicates: [['a', 'b', 'c', 'd', 'e', 'f', 'g']] }));
    expect(groups.duplicates).toEqual([]);
  });
});

describe('parseAiRatings', () => {
  it('reads the JSON around extra text, clamps values and keeps only known angles', () => {
    const ratings = parseAiRatings('Here: {"ratings":[{"id":"a","severity":7,"severityWhy":"29 killed","scale":2,"urgency":-1,"interest":1,"dimension":"nope","topic":"t","impacts":{"economic":"Fuel prices","political":"","weird":"x"}}]}');
    expect(ratings).toEqual([{
      id: 'a', severity: 3, severityWhy: '29 killed', scale: 2, scaleWhy: '', urgency: 0, urgencyWhy: '',
      interest: 1, interestWhy: '', dimension: 'other', impacts: { economic: 'Fuel prices' }
    }]);
    expect(parseAiRatings('not json')).toEqual([]);
  });
});

function pageData(html: string) {
  const json = html.match(/<script id="briefing-data" type="application\/json">([\s\S]*?)<\/script>/)?.[1] || '{}';
  return JSON.parse(json);
}

describe('buildBriefing', () => {
  it('uses the AI notes and impacts and ships the sliders with the page', async () => {
    const briefing = await buildBriefing([
      story({ id: 'calm', title: 'Local festival opens', coverUrl: 'https://img/x.jpg' }),
      story({ id: 'big', title: 'Government falls after vote', link: 'https://news/big' })
    ], {
      period: 'hour',
      scope: 'Feed',
      window: hour,
      rateWithAi: async candidates => candidates.map(c => ({
        id: c.id,
        severity: c.id === 'big' ? 3 : 0,
        severityWhy: c.id === 'big' ? 'cabinet of 20 ministers out' : '',
        scale: c.id === 'big' ? 3 : 0,
        scaleWhy: '',
        urgency: c.id === 'big' ? 3 : 0,
        urgencyWhy: '',
        interest: 1,
        interestWhy: 'first in 30 years',
        dimension: c.id === 'big' ? 'politics' : 'culture',
        impacts: { economic: `economic ${c.id}` }
      }))
    });
    expect(briefing.itemCount).toBe(2);
    const data = pageData(briefing.html);
    expect(data.stories.map((s: { title: string }) => s.title)).toEqual(['Government falls after vote', 'Local festival opens']);
    expect(data.stories[0].notes.severity).toBe('cabinet of 20 ministers out');
    // Scored above 0 without a reason from the AI: falls back to the words the rules found.
    expect(data.stories[0].notes.scale).toBe('“Government falls after vote”');
    // Zero scores carry a reason as well.
    expect(data.stories[1].notes.severity).toBe('No deaths, injuries, damage or money lost are mentioned');
    expect(data.stories[0].impacts.economic).toBe('economic big');
    expect(data.stories[1].coverUrl).toBe('https://img/x.jpg');
    expect(data.criteria.map((c: { key: string }) => c.key)).toEqual(['severity', 'scale', 'urgency', 'interest', 'coverage', 'relevance']);
    expect(data.presets.length).toBeGreaterThan(1);
    expect(briefing.html).toContain('id="eq-bands"');
    expect(briefing.html).toContain('judged by AI');
  });

  it('falls back to rules when the AI fails, and keeps story text out of the markup', async () => {
    const briefing = await buildBriefing([
      story({ title: '</script><script>alert(1)</script>', link: 'javascript:alert(1)', coverUrl: 'javascript:x' })
    ], { period: 'day', scope: 'All', window: hour, rateWithAi: async () => { throw new Error('down'); } });
    expect(briefing.html).not.toContain('<script>alert(1)');
    expect(briefing.html).not.toContain('javascript:');
    const data = pageData(briefing.html);
    expect(data.stories[0].title).toBe('</script><script>alert(1)</script>');
    expect(data.stories[0].link).toBe('');
    expect(briefing.html).toContain('keyword rules');
    expect(briefing.title).toMatch(/^Daily briefing · All/);
  });

  it('asks again for stories the AI skipped and keeps unchecked ones below High', async () => {
    const calls: string[][] = [];
    const briefing = await buildBriefing([
      story({ id: 'checked', title: 'Quiet council meeting' }),
      story({ id: 'skipped', title: 'Невиждан срив и загуби, жертви и криза в цялата страна' })
    ], {
      period: 'hour',
      scope: 'All',
      window: hour,
      rateWithAi: async candidates => {
        calls.push(candidates.map(c => c.id));
        return candidates.filter(c => c.id === 'checked').map(c => ({
          id: c.id, severity: 0, severityWhy: '', scale: 0, scaleWhy: '', urgency: 0, urgencyWhy: '',
          interest: 0, interestWhy: '', dimension: 'politics', impacts: {}
        }));
      }
    });
    expect(calls).toEqual([['skipped', 'checked'], ['skipped']]);
    const skipped = pageData(briefing.html).stories.find((s: { title: string }) => s.title.startsWith('Невиждан'));
    expect(skipped.ratedBy).toBe('rules');
    expect(pageData(briefing.html).aiRan).toBe(true);
    expect(pageData(briefing.html).uncheckedCap).toBeLessThan(50);
  });

  it('passes storylines to the page', async () => {
    const briefing = await buildBriefing([
      story({ id: 'drone', title: 'Drone strike in the Black Sea' }),
      story({ id: 'command', title: 'Romania offers joint naval command' }),
      story({ id: 'oman', title: 'Embassy opens in Oman' })
    ], {
      period: 'hour',
      scope: 'All',
      window: hour,
      groupWithAi: async () => ({
        duplicates: [],
        storylines: new Map([['drone', 'Black Sea security'], ['command', 'Black Sea security'], ['oman', 'Gulf ties']])
      })
    });
    const lines = Object.fromEntries(pageData(briefing.html).stories.map((s: { title: string; storyline: string }) => [s.title, s.storyline]));
    expect(lines['Drone strike in the Black Sea']).toBe('Black Sea security');
    expect(lines['Romania offers joint naval command']).toBe('Black Sea security');
    expect(lines['Embassy opens in Oman']).toBe('');
  });

  const statement = [
    story({ id: 'pm-a', title: 'Костов, Борисов, Петков и Денков призоваха Радев да защити националната сигурност', source: 'Свободна точка', link: 'https://a' }),
    story({ id: 'pm-b', title: 'Костов, Борисов и Петков: Мирът не се гарантира с надеждата, че Путин ще ни пощади', source: 'dnevnik.bg', link: 'https://b' }),
    story({ id: 'tesla', title: 'Tesla представи летящ Roadster', source: 'dnevnik.bg', link: 'https://c' })
  ];

  it('lets the AI decide on name-only matches, shows its reasons and counts the merged sources', async () => {
    const seen: Array<{ id: string; maybeSameAs?: string[] }> = [];
    const briefing = await buildBriefing(statement, {
      period: 'hour',
      scope: 'All',
      window: hour,
      groupWithAi: async items => {
        seen.push(...items);
        return parseStorylines(JSON.stringify({ duplicates: [{ ids: ['pm-a', 'pm-b'], why: 'Both report the joint statement' }] }));
      }
    });
    // Not merged up front: the AI got both, with the title rule's guess as a hint.
    expect(seen.find(item => item.id === 'pm-a')?.maybeSameAs).toEqual(['pm-b']);
    expect(seen.find(item => item.id === 'tesla')?.maybeSameAs).toBeUndefined();
    const lead = pageData(briefing.html).stories.find((s: { related: unknown[] }) => s.related.length);
    expect(lead.duplicateWhy).toBe('Both report the joint statement');
    expect(lead.scores.coverage).toBe(1);
    expect(lead.notes.coverage).toBe('Reported by Свободна точка, dnevnik.bg');
  });

  it('falls back to the title rule when the AI grouping fails', async () => {
    const briefing = await buildBriefing(statement, {
      period: 'hour', scope: 'All', window: hour, groupWithAi: async () => { throw new Error('down'); }
    });
    expect(pageData(briefing.html).stories).toHaveLength(2);
  });

  it('ships the AI summary with each line pointing at its story, folded reports included', async () => {
    const briefing = await buildBriefing(statement, {
      period: 'hour',
      scope: 'All',
      window: hour,
      groupWithAi: async () => parseStorylines(JSON.stringify({ duplicates: [['pm-a', 'pm-b']] })),
      digestWithAi: async items => {
        expect(items.map(item => item.id).sort()).toHaveLength(2);
        return parseDigest(JSON.stringify({ bullets: [
          { kind: 'critical', text: 'Former PMs press Radev', ids: ['pm-a', 'pm-b'] },
          { kind: 'odd', text: 'Tesla flies', ids: ['tesla', 'ghost'] },
          { kind: 'leading', text: '' }
        ] }));
      }
    });
    const data = pageData(briefing.html);
    const titleAt = (index: number) => data.stories[index].title;
    expect(data.digest).toHaveLength(2);
    expect(data.digest[0].kind).toBe('critical');
    expect(data.digest[0].targets).toHaveLength(1);
    expect(titleAt(data.digest[0].targets[0])).toMatch(/^Костов/);
    expect(data.digest[1]).toMatchObject({ kind: 'leading', text: 'Tesla flies' });
    expect(titleAt(data.digest[1].targets[0])).toMatch(/^Tesla/);
  });

  it('ships a page script that parses', async () => {
    const briefing = await buildBriefing([], { period: 'hour', scope: 'All', window: hour });
    const script = briefing.html.match(/<script>([\s\S]*?)<\/script>/)?.[1] || '';
    expect(() => new Function(script)).not.toThrow();
  });
});

describe('createBriefingStore', () => {
  it('saves, reloads, replaces a scheduled hour and prunes old files', async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'briefings-'));
    const store = createBriefingStore(dir, 2);
    const make = (h: number, scheduled: boolean, generatedAtMs: number) =>
      buildBriefing([], { period: 'hour', scope: 'All', window: { startMs: at(h), endMs: at(h + 1) }, generatedAtMs }, scheduled);
    const first = await make(10, true, 1);
    store.save(first);
    store.save(await make(11, true, 2));
    const redo = await make(11, true, 3);
    store.save(redo);
    store.save(await make(11, false, 4));

    const reloaded = createBriefingStore(dir, 2);
    expect(reloaded.list().map(r => [r.windowStartMs, r.scheduled])).toEqual([[at(11), false], [at(11), true]]);
    expect(reloaded.readHtml(redo.id)).toContain('<!doctype html>');
    expect(reloaded.readHtml(first.id)).toBeNull();
    expect(reloaded.readHtml('../index')).toBeNull();
    expect(fs.readdirSync(dir).filter(name => name.endsWith('.html'))).toHaveLength(2);
  });
});

describe('language', () => {
  it('writes the page and the keyword notes in Bulgarian when the briefing is in Bulgarian', async () => {
    const briefing = await buildBriefing([story({ title: 'Нов закон за пътищата', source: 'БНТ' })], {
      period: 'day', scope: 'Всички колони', window: hour, language: 'bg'
    });
    const data = pageData(briefing.html);
    expect(briefing.title).toMatch(/^Дневен бюлетин · Всички колони/);
    expect(briefing.html).toContain('<html lang="bg">');
    expect(data.stories[0].notes.coverage).toBe('Съобщава само БНТ');
    expect(data.stories[0].notes.severity).toBe('Не се споменават жертви, ранени, щети или загубени пари');
    expect(data.criteria[0].label).toBe('Тежест');
    expect(data.levelLabels.high).toBe('Важно');
    expect(data.text.atAGlance).toBe('Накратко');
    expect(briefing.html).toContain('Как се оценяват новините');
    expect(briefing.html).not.toContain('How stories are rated');
  });
});

describe('prompts', () => {
  it('tell the AI not to take a headline figure of speech literally', async () => {
    const { buildAiRatingPrompt, buildStorylinePrompt, buildDigestPrompt, LITERAL_FACTS_RULE } = await import('./briefing.js');
    expect(LITERAL_FACTS_RULE).toContain('figures of speech');
    expect(buildAiRatingPrompt([], 'bg', 'България')).toContain(LITERAL_FACTS_RULE);
    expect(buildStorylinePrompt([], 'bg')).toContain(LITERAL_FACTS_RULE);
    expect(buildDigestPrompt([], 'bg', 'България')).toContain(LITERAL_FACTS_RULE);
  });
});

describe('critical', () => {
  const scores = (severity: number, scale: number, urgency: number) => ({ severity, scale, urgency, interest: 2, coverage: 2, relevance: 0 });
  it('lets a severe local event happening now be critical, but not a grim background feature', async () => {
    const { criticalCap } = await import('./briefing.js');
    // A body found and a suspect held today, in one town.
    expect(criticalCap(scores(3, 1, 3))).toBeUndefined();
    expect(levelOf(scoreOf(scores(3, 1, 3)))).toBe('critical');
    // Child marriages in one far province, a long-running situation.
    expect(criticalCap(scores(3, 1, 1))).toBe('notNow');
    expect(levelOf(scoreOf({ ...scores(3, 3, 1), interest: 3 }))).not.toBe('critical');
    // Happening now but minor and local.
    expect(criticalCap(scores(2, 1, 3))).toBe('minor');
  });
});

describe('resolutions', () => {
  it('groups an event that began and ended in the period, resolution first', () => {
    const groups = parseStorylines(JSON.stringify({
      duplicates: [['found', 'found-2']],
      storylines: [{ label: 'Search', ids: ['missing', 'found', 'other'] }],
      resolutions: [{ ids: ['missing', 'search', 'found-2'], resolvedBy: 'found-2', label: 'Missing boy found', summary: 'Reported missing at 9:10, found unharmed at 11:40.' }]
    }));
    expect(groups.resolutions).toHaveLength(1);
    const grouped = applyGrouping([
      entry('found', 70, 'society'), entry('found-2', 50, 'society'), entry('missing', 60, 'society'),
      entry('search', 40, 'society'), entry('other', 30, 'society')
    ], groups);
    const roles = Object.fromEntries(grouped.map(g => [g.story.id, g.resolution?.role]));
    // "found-2" was folded into "found", so "found" resolves it.
    expect(roles).toEqual({ found: 'resolution', missing: 'start', search: 'update', other: undefined });
    expect(grouped.find(g => g.story.id === 'found')?.resolution?.summary).toBe('Reported missing at 9:10, found unharmed at 11:40.');
    // Items in a resolution leave their storyline, which then has too few stories.
    expect(grouped.map(g => g.storyline)).toEqual([undefined, undefined, undefined, undefined]);
  });

  it('ignores a resolution with a single story or no label', () => {
    const groups = parseStorylines(JSON.stringify({ resolutions: [{ ids: ['a'], label: 'x' }, { ids: ['a', 'b'], label: '' }] }));
    expect(groups.resolutions).toEqual([]);
  });

  it('ships the resolution with each story and the labels for the page', async () => {
    const briefing = await buildBriefing([
      story({ id: 'm', title: 'Boy missing near Varna', publishedMs: at(13, 5) }),
      story({ id: 'f', title: 'Missing boy found unharmed', publishedMs: at(13, 50) })
    ], {
      period: 'hour', scope: 'All', window: hour, language: 'bg',
      groupWithAi: async () => parseStorylines(JSON.stringify({ resolutions: [{ ids: ['m', 'f'], resolvedBy: 'f', label: 'Изчезнало момче', summary: 'Намерено.' }] }))
    });
    const data = pageData(briefing.html);
    const roles = data.stories.map((s: { resolution: { role: string } | null }) => s.resolution?.role).sort();
    expect(roles).toEqual(['resolution', 'start']);
    expect(data.text.resolved).toBe('Разрешено');
    expect(data.text.roleStart).toBe('Начало');
  });
});

describe('periods', () => {
  it('covers a week, a month or a custom number of hours, and grows the page with the period', async () => {
    const { rollingWindow, briefingSize, briefingTitle, MAX_CUSTOM_HOURS } = await import('./briefing.js');
    const now = at(14);
    const hoursOf = (w: { startMs: number; endMs: number }) => (w.endMs - w.startMs) / 3_600_000;
    expect(hoursOf(rollingWindow('week', now))).toBe(168);
    expect(hoursOf(rollingWindow('month', now))).toBe(720);
    expect(hoursOf(rollingWindow('custom', now, 72))).toBe(72);
    expect(hoursOf(rollingWindow('custom', now, 99_999))).toBe(MAX_CUSTOM_HOURS);
    expect(briefingSize(rollingWindow('hour', now))).toEqual({ limit: 12, pageSize: 36 });
    expect(briefingSize(rollingWindow('week', now))).toEqual({ limit: 25, pageSize: 70 });
    expect(briefingSize(rollingWindow('month', now))).toEqual({ limit: 30, pageSize: 80 });
    const week = rollingWindow('week', now);
    expect(briefingTitle('week', 'Всички колони', week.startMs, week.endMs, 'bg')).toMatch(/^Седмичен бюлетин · Всички колони · .+ – .+$/);
  });

  it('shows the date with each story time in a briefing longer than a day', async () => {
    const window = { startMs: at(14) - 7 * 86_400_000, endMs: at(14) };
    const briefing = await buildBriefing([story({ title: 'Old story', publishedMs: at(14) - 3 * 86_400_000 })], { period: 'week', scope: 'All', window });
    const time = pageData(briefing.html).stories[0].time;
    expect(time).toMatch(/\d{1,2}:\d{2}/);
    expect(time.length).toBeGreaterThan(5);
  });
});

describe('rating prompt', () => {
  it('asks for the main surprise of a story, not a side number', async () => {
    const { buildAiRatingPrompt } = await import('./briefing.js');
    const prompt = buildAiRatingPrompt([], 'bg', 'България');
    expect(prompt).toContain('main claim in the headline');
    expect(prompt).toContain('a car that flies, not its acceleration');
  });
});

describe('sameEventTitles', () => {
  it('matches two outlets on one event but not stories that only share a name', async () => {
    const { sameEventTitles } = await import('./briefing.js');
    expect(sameEventTitles('Пороен дъжд наводни Истанбул, трима загинали', 'Трима загинали при наводнения в Истанбул след пороен дъжд')).toBe(true);
    expect(sameEventTitles('Зеленски обсъди войната с европейските лидери', 'Зеленски посети болница в Лвов')).toBe(false);
  });
});

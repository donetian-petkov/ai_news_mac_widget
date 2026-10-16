import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const HOUR_MS = 60 * 60 * 1000;

export type BriefingPeriod = 'hour' | 'day';

export const IMPACT_DIMENSIONS = [
  'security', 'politics', 'economy', 'health', 'environment', 'society', 'technology', 'culture', 'sports', 'other'
] as const;
export type ImpactDimension = typeof IMPACT_DIMENSIONS[number];

const DIMENSION_LABELS: Record<ImpactDimension, string> = {
  security: 'Security & conflict',
  politics: 'Politics & governance',
  economy: 'Economy & money',
  health: 'Health',
  environment: 'Environment & disasters',
  society: 'Society & justice',
  technology: 'Technology',
  culture: 'Culture & entertainment',
  sports: 'Sports',
  other: 'Other'
};

/** The angles every story's impact is described from, so no story is seen from one side only. */
export const IMPACT_ANGLES = ['economic', 'political', 'social', 'security'] as const;
export type ImpactAngle = typeof IMPACT_ANGLES[number];
export type StoryImpacts = Partial<Record<ImpactAngle, string>>;

export type BriefingStory = {
  id: string;
  title: string;
  link?: string;
  source?: string;
  feedUrl: string;
  publishedMs: number;
  summary?: string;
  /** "Why it matters" text the story-impact AI feature already wrote, if any. */
  impact?: string;
  coverUrl?: string;
};

export const CRITERIA = ['severity', 'scale', 'urgency', 'interest', 'coverage', 'relevance'] as const;
export type Criterion = typeof CRITERIA[number];
/** Each criterion is scored 0 (none) to 3 (strong). */
export type CriteriaScores = Record<Criterion, number>;
/** The concrete fact behind each non-zero score. */
export type CriteriaNotes = Partial<Record<Criterion, string>>;

export type StoryRating = {
  scores: CriteriaScores;
  notes: CriteriaNotes;
  dimension: ImpactDimension;
  impacts: StoryImpacts;
  whyItMatters?: string;
  ratedBy: 'ai' | 'rules';
};

/** What the AI returns per candidate. Coverage and relevance stay computed from data. */
export type AiStoryRating = {
  id: string;
  severity: number;
  severityWhy: string;
  scale: number;
  scaleWhy: string;
  urgency: number;
  urgencyWhy: string;
  interest: number;
  interestWhy: string;
  dimension: ImpactDimension;
  impacts: StoryImpacts;
};

export type AiRatingCandidate = {
  id: string;
  title: string;
  summary: string;
  source: string;
  alsoReportedBy: string[];
};

export type PriorityLevel = 'critical' | 'high' | 'notable' | 'routine';

export type RatedStory = {
  story: BriefingStory;
  /** Same event reported by other sources. */
  related: BriefingStory[];
  rating: StoryRating;
  score: number;
  level: PriorityLevel;
  /** Larger ongoing situation shared with other, different stories (e.g. "Black Sea security"). */
  storyline?: string;
  /** The AI's one sentence on how the storyline's stories connect. */
  storylineWhy?: string;
  /** The AI's one sentence on why the folded reports are the same event. */
  duplicateWhy?: string;
};

/** Default importance of each criterion. The briefing page lets the reader slide these. */
export const DEFAULT_WEIGHTS: CriteriaScores = { severity: 3, scale: 2.5, urgency: 2, interest: 1.5, coverage: 1.5, relevance: 1 };

/** How far a single criterion at full score and full weight lifts a story on its own (0–1). */
const SINGLE_CRITERION_STRENGTH = 0.65;

const CRITERIA_TEXT: Record<Criterion, string> = {
  severity: 'harm to lives, safety, rights or money',
  scale: 'how many people it reaches (local, national, international)',
  urgency: 'whether it is unfolding now or needs action soon',
  interest: 'how surprising, new or revealing it is',
  coverage: 'how many sources report the same event',
  relevance: 'whether it touches your tracked topics or region'
};

const CRITERIA_LABELS: Record<Criterion, string> = {
  severity: 'Severity', scale: 'Scale', urgency: 'Urgency', interest: 'Interest', coverage: 'Coverage', relevance: 'Relevance'
};

const LEVEL_LABELS: Record<PriorityLevel, string> = { critical: 'Critical', high: 'High', notable: 'Notable', routine: 'Routine' };

export type BriefingLanguage = 'en' | 'bg';

/**
 * Everything the page and the keyword notes say, in the briefing's language, so labels
 * never come out in English beside Bulgarian AI text. `page` goes to the browser script;
 * "{n}"-style slots are filled there.
 */
const UI = {
  en: {
    locale: 'en-GB',
    dimensions: DIMENSION_LABELS,
    criteria: CRITERIA_LABELS,
    criteriaText: CRITERIA_TEXT,
    levels: LEVEL_LABELS,
    angles: { economic: 'Economic', political: 'Political', social: 'Social', security: 'Security' } as Record<ImpactAngle, string>,
    presets: ['Balanced', 'Critical first', 'Interesting', 'Close to home'],
    noHarmYet: (area: string) => `${area} story, but no harm is reported yet`,
    figureOfSpeech: (quote: string, area: string) => `${quote} — figure of speech in a ${area.toLowerCase()} story`,
    severalCountries: (list: string) => `Involves several countries: ${list}`,
    reportedBy: (names: string) => `Reported by ${names}`,
    onlyOne: (name: string) => `Only ${name} reports it`,
    oneSource: 'one source',
    zero: {
      severity: 'No deaths, injuries, damage or money lost are mentioned',
      scale: 'No country-wide or international reach is mentioned',
      urgency: 'No deadline, live event or warning is mentioned',
      interest: 'No first, record, surprise or new revelation in the headline'
    },
    yourTopics: (count: number) => (count > 1 ? 'your topics' : 'your topic'),
    yourRegion: 'your region',
    mentions: (parts: string[]) => `Mentions ${parts.join(' and ')}`,
    noneMentioned: (count: number, region: string) => `None of your ${count} topics${region ? ` or ${region}` : ''} is mentioned`,
    title: (period: BriefingPeriod) => (period === 'day' ? 'Daily briefing' : 'Hourly briefing'),
    countLine: (count: string, when: string) => `${count} stories · generated ${when}`,
    footer: (ai: boolean) => `<strong>How stories are rated.</strong> Each story gets 0–3 on six criteria, each with the fact behind it.
    The sliders set how much each criterion counts compared with the others (they are remembered for every briefing).
    The score is 0–100: one strong criterion is enough to lift a story, and each further one lifts it more, so a deadly attack
    does not also need to be surprising to rank high. The +numbers show each criterion's share of the score.
    Critical is ${LEVEL_THRESHOLDS.critical}+, High ${LEVEL_THRESHOLDS.high}+, Notable ${LEVEL_THRESHOLDS.notable}+, Routine below.
    ${ai
      ? 'The AI reads the stories together to merge reports of the same event under one story (open "more reports" to see them and why), to group different stories about one ongoing situation into a storyline, and to write the summary at the top.'
      : 'Reports with near-identical headlines are merged under one story (open "more reports" to see them).'}
    No single area takes more than about a third of the list.
    ${ai
      ? 'Severity, scale, urgency, interest and the economic, political, social and security impact are judged by AI; coverage and relevance come from your sources and topics.'
      : 'AI was off, so keyword rules did the rating and there is no impact write-up.'}`,
    importance: 'Importance',
    importanceAria: 'Importance of each criterion',
    importanceHint: 'How much each criterion counts. The stories re-rank as you slide.',
    close: 'Close',
    goTop: 'Go to top',
    goBottom: 'Go to bottom',
    page: {
      of: '{a} of {b}',
      notChecked: 'not checked by AI',
      keywordRated: 'keyword-rated',
      notCheckedTip: 'The AI did not answer for this story, so keyword rules rated it; it is kept below High until the AI checks it',
      keywordTip: 'AI is off, so keyword rules rated this story',
      whyItMatters: 'Why it matters',
      why: 'Why {level} · {score}/100',
      moreOne: '1 more report of this',
      moreMany: '{n} more reports of this',
      storyline: 'Storyline',
      differentStories: '{n} different stories',
      atAGlance: 'At a glance',
      writtenByAi: 'written by AI from the stories below',
      alsoInteresting: 'Also interesting',
      story: 'story',
      empty: 'No new stories were published in this period.',
      priority: 'Priority',
      alsoWorth: 'Also worth knowing',
      stories: 'Stories',
      moreStories: 'More stories ({n})',
      custom: 'Custom',
      bandAria: '{label} importance'
    }
  },
  bg: {
    locale: 'bg-BG',
    dimensions: {
      security: 'Сигурност и конфликти', politics: 'Политика и управление', economy: 'Икономика и пари', health: 'Здраве',
      environment: 'Природа и бедствия', society: 'Общество и правосъдие', technology: 'Технологии',
      culture: 'Култура и забавления', sports: 'Спорт', other: 'Друго'
    } as Record<ImpactDimension, string>,
    criteria: { severity: 'Тежест', scale: 'Обхват', urgency: 'Спешност', interest: 'Интерес', coverage: 'Отразяване', relevance: 'Значимост' } as Record<Criterion, string>,
    criteriaText: {
      severity: 'вреда за живот, безопасност, права или пари',
      scale: 'колко хора засяга (местно, национално, международно)',
      urgency: 'дали се случва сега или изисква действие скоро',
      interest: 'колко е изненадващо, ново или разкриващо',
      coverage: 'колко източника съобщават за същото събитие',
      relevance: 'дали засяга вашите теми или регион'
    } as Record<Criterion, string>,
    levels: { critical: 'Критично', high: 'Важно', notable: 'Забележимо', routine: 'Рутинно' } as Record<PriorityLevel, string>,
    angles: { economic: 'Икономика', political: 'Политика', social: 'Общество', security: 'Сигурност' } as Record<ImpactAngle, string>,
    presets: ['Балансирано', 'Първо критичното', 'Интересно', 'Близо до дома'],
    noHarmYet: (area: string) => `Новина от „${area}“, но не се съобщава за вреди`,
    figureOfSpeech: (quote: string, area: string) => `${quote} — в преносен смисъл, новина от „${area}“`,
    severalCountries: (list: string) => `Засяга няколко държави: ${list}`,
    reportedBy: (names: string) => `Съобщават: ${names}`,
    onlyOne: (name: string) => `Съобщава само ${name}`,
    oneSource: 'един източник',
    zero: {
      severity: 'Не се споменават жертви, ранени, щети или загубени пари',
      scale: 'Не се споменава национален или международен обхват',
      urgency: 'Не се споменава срок, събитие на живо или предупреждение',
      interest: 'В заглавието няма първо, рекорд, изненада или ново разкритие'
    },
    yourTopics: (count: number) => (count > 1 ? 'вашите теми' : 'вашата тема'),
    yourRegion: 'вашия регион',
    mentions: (parts: string[]) => `Споменава ${parts.join(' и ')}`,
    noneMentioned: (count: number, region: string) => `Не се споменава нито една от вашите ${count} теми${region ? ` или ${region}` : ''}`,
    title: (period: BriefingPeriod) => (period === 'day' ? 'Дневен бюлетин' : 'Часов бюлетин'),
    countLine: (count: string, when: string) => `${count} новини · създаден ${when}`,
    footer: (ai: boolean) => `<strong>Как се оценяват новините.</strong> Всяка новина получава 0–3 по шест критерия, всеки с факта зад оценката.
    Плъзгачите задават колко тежи всеки критерий спрямо другите (запомнят се за всеки бюлетин).
    Резултатът е 0–100: един силен критерий стига, за да издигне новината, а всеки следващ я издига още, така че смъртоносна атака
    не трябва да е и изненадваща, за да е високо. Числата +N показват дела на всеки критерий в резултата.
    Критично е ${LEVEL_THRESHOLDS.critical}+, Важно ${LEVEL_THRESHOLDS.high}+, Забележимо ${LEVEL_THRESHOLDS.notable}+, Рутинно под това.
    ${ai
      ? 'AI чете новините заедно: обединява съобщенията за едно и също събитие под една новина (отворете „още източника“, за да ги видите и защо), групира различни новини за една ситуация в сюжет и пише обобщението най-горе.'
      : 'Съобщения с почти еднакви заглавия се обединяват под една новина (отворете „още източника“, за да ги видите).'}
    Никоя област не заема повече от около една трета от списъка.
    ${ai
      ? 'Тежестта, обхватът, спешността, интересът и икономическото, политическото, социалното и свързаното със сигурността въздействие се оценяват от AI; отразяването и значимостта идват от вашите източници и теми.'
      : 'AI беше изключен, затова оценката е по ключови думи и няма описание на въздействието.'}`,
    importance: 'Важност',
    importanceAria: 'Важност на всеки критерий',
    importanceHint: 'Колко тежи всеки критерий. Новините се пренареждат, докато местите плъзгачите.',
    close: 'Затвори',
    goTop: 'Нагоре',
    goBottom: 'Надолу',
    page: {
      of: '{a} от {b}',
      notChecked: 'не е проверено от AI',
      keywordRated: 'оценено по ключови думи',
      notCheckedTip: 'AI не отговори за тази новина, затова е оценена по ключови думи; остава под „Важно“, докато AI я провери',
      keywordTip: 'AI е изключен, затова новината е оценена по ключови думи',
      whyItMatters: 'Защо е важно',
      why: 'Защо „{level}“ · {score}/100',
      moreOne: 'още 1 източник за същото',
      moreMany: 'още {n} източника за същото',
      storyline: 'Сюжет',
      differentStories: '{n} различни новини',
      atAGlance: 'Накратко',
      writtenByAi: 'написано от AI по новините по-долу',
      alsoInteresting: 'Още интересно',
      story: 'новина',
      empty: 'В този период няма нови новини.',
      priority: 'Приоритетни',
      alsoWorth: 'Също си струва',
      stories: 'Новини',
      moreStories: 'Още новини ({n})',
      custom: 'Ръчно',
      bandAria: 'Важност: {label}'
    }
  }
};
const LEVEL_THRESHOLDS = { critical: 70, high: 50, notable: 25 };
/** Highest score a keyword-rated story can get when the AI rated the rest of the briefing. */
const UNCHECKED_SCORE_CAP = LEVEL_THRESHOLDS.high - 1;

// ---- rule-based rating (used when AI is off, and for coverage/relevance always) ----

// Terms match the start of a word, so stems cover inflections ("атак" → "атака", "атаки").
// A trailing "$" means the whole word must match.
const DIMENSION_TERMS: Array<[ImpactDimension, string[]]> = [
  ['security', ['war$', 'wars$', 'attack', 'missile', 'airstrike', 'strikes$', 'military', 'army', 'troops', 'drone', 'terror', 'shooting', 'explosion', 'nato$', 'ceasefire', 'invasion', 'refiner', 'война', 'атак', 'ракет', 'удар', 'военн', 'армия', 'войск', 'дрон', 'терор', 'стрелб', 'взрив', 'нато', 'примири', 'обстрел', 'отбран', 'сигурност']],
  ['politics', ['election', 'government', 'parliament', 'minister', 'president', 'protest', 'sanction', 'vote', 'senate', 'congress', 'prosecutor', 'избор', 'правителств', 'парламент', 'министър', 'президент', 'протест', 'санкци', 'гласув', 'прокурор', 'депутат', 'партия', 'премиер']],
  ['economy', ['inflation', 'prices', 'market', 'bank', 'rates$', 'budget', 'tax', 'jobs$', 'oil$', 'gas$', 'tariff', 'euro$', 'stocks', 'assets', 'инфлаци', 'цени', 'цена', 'пазар', 'банк', 'лихв', 'бюджет', 'данъ', 'петрол', 'газ', 'мита', 'евро', 'актив', 'икономи', 'заплат', 'пенси', 'имот']],
  ['health', ['virus', 'outbreak', 'hospital', 'disease', 'vaccine', 'pandemic', 'cancer', 'вирус', 'огнищ', 'болниц', 'болест', 'ваксин', 'пандеми', 'здрав', 'нзок', 'лекар']],
  ['environment', ['earthquake', 'flood', 'wildfire', 'storm', 'climate', 'drought', 'hurricane', 'collapse', 'земетрес', 'наводн', 'пожар', 'буря', 'климат', 'суша', 'ураган', 'срути', 'бедстви']],
  ['society', ['court', 'arrest', 'police', 'crime', 'murder', 'accident', 'fraud', 'school', 'students', 'съд', 'арест', 'полици', 'престъп', 'убийств', 'катастроф', 'измам', 'разслед', 'стачк', 'училищ', 'студент', 'граждан']],
  ['technology', ['ai$', 'cyber', 'hack', 'chip', 'software', 'satellite', 'robot', 'изкуствен', 'кибер', 'хакер', 'чип', 'сателит', 'технолог']],
  ['culture', ['film', 'movie', 'music', 'festival', 'actor', 'episode', 'series', 'oscar', 'филм', 'музик', 'фестивал', 'актьор', 'турне', 'сериал', 'трейлър', 'концерт']],
  ['sports', ['football', 'match', 'league', 'championship', 'playoff', 'goal', 'coach', 'футбол', 'мач', 'лига', 'шампионат', 'титла', 'треньор', 'отбор', 'класико', 'волейбол', 'клуб', 'club', 'mvp$', 'реал$', 'nba$', 'nfl$', 'olympic', 'олимпи']]
];

const SEVERITY_TERMS = ['killed', 'killing', 'dead$', 'death', 'deaths', 'casualt', 'injured', 'emergency', 'crisis', 'collapse', 'evacuat', 'disaster', 'catastroph', 'victims', 'убит', 'загин', 'жертв', 'ранен', 'извънредн', 'криза', 'срив', 'евакуац', 'бедстви', 'катастроф', 'смърт', 'загуб'];
const SCALE_TERMS = ['national', 'nationwide', 'country', 'global', 'world', 'international', 'european', 'eu$', 'nato$', 'millions', 'government', 'parliament', 'национал', 'страната', 'цялата', 'светов', 'международ', 'европ', 'ес$', 'милион', 'правителств', 'парламент', 'държав'];
const URGENCY_TERMS = ['breaking', 'urgent', 'live$', 'now$', 'today', 'imminent', 'deadline', 'warning', 'alert', 'resume', 'извънредно', 'спешно', 'сега', 'днес', 'предупре', 'тревог', 'ултиматум', 'възобнов', 'незабавно'];
// Naming other countries or shared regions signals reach beyond one place.
const COUNTRY_TERMS = ['ukrain', 'russia', 'usa$', 'us$', 'america', 'romania', 'turkey', 'türk', 'greece', 'serbia', 'china', 'iran', 'israel', 'gaza', 'pakistan', 'india', 'germany', 'france', 'britain', 'poland', 'moldova', 'nato$', 'eu$', 'black$', 'украйн', 'русия', 'руск', 'сащ', 'америк', 'румъни', 'турци', 'гърци', 'сърби', 'македони', 'китай', 'иран', 'израел', 'газа', 'пакистан', 'индия', 'германи', 'франци', 'британ', 'полша', 'молдов', 'нато', 'ес$', 'черно', 'истанбул', 'киев', 'москва', 'брюксел', 'вашингтон', 'оман'];
const INTEREST_TERMS = ['first$', 'record', 'never', 'rare$', 'discover', 'unusual', 'secret', 'mystery', 'surpris', 'unexpected', 'breakthrough', 'reveal', 'първ', 'рекорд', 'никога', 'рядк', 'откри', 'необичайн', 'тайн', 'мистери', 'изненад', 'невиждан', 'уникал', 'пробив', 'разкри', 'любопит'];

function words(text: string): string[] {
  return String(text || '').toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean);
}

/** The words in the text that match the terms, in term order. */
function termHits(textWords: string[], terms: string[]): string[] {
  const hits: string[] = [];
  for (const term of terms) {
    const exact = term.endsWith('$');
    const stem = exact ? term.slice(0, -1) : term;
    const hit = textWords.find(word => (exact ? word === stem : word.startsWith(stem)));
    if (hit) hits.push(hit);
  }
  return hits;
}

/** The user's topics found in the text. Short topics ("AI", "ЕС") must match a whole word. */
function trackedHits(textWords: string[], trackedTerms: string[]): string[] {
  return trackedTerms.filter(term => {
    const parts = words(term);
    return parts.length > 0 && parts.every(part => textWords.some(word =>
      part.length <= 4 ? word === part : word.startsWith(part.slice(0, part.length - 1))));
  });
}

/** A few words around `hitWord`, taken from the title first and then the summary. */
function quoteAround(story: BriefingStory, hitWord: string, radius = 4): string {
  for (const text of [story.title, story.summary || '']) {
    const tokens = text.split(/\s+/).filter(Boolean);
    const index = tokens.findIndex(token => words(token).includes(hitWord));
    if (index < 0) continue;
    const from = Math.max(0, index - radius);
    const to = Math.min(tokens.length, index + radius + 1);
    return `“${from > 0 ? '…' : ''}${tokens.slice(from, to).join(' ')}${to < tokens.length ? '…' : ''}”`;
  }
  return `“${hitWord}”`;
}

const clamp = (value: number) => Math.max(0, Math.min(3, Math.round(Number(value) || 0)));

/**
 * How strongly each criterion pushes the story up (0–1): its score times its weight relative
 * to the heaviest slider. Sliders are relative, like an equalizer.
 */
function criterionLifts(scores: CriteriaScores, weights: CriteriaScores): number[] {
  const heaviest = Math.max(0, ...CRITERIA.map(key => weights[key]));
  if (!heaviest) return CRITERIA.map(() => 0);
  return CRITERIA.map(key => (Math.max(0, weights[key]) / heaviest) * (clamp(scores[key]) / 3) * SINGLE_CRITERION_STRENGTH);
}

/**
 * 0–100. Combined like independent chances, so one strong criterion is enough to make a
 * story matter (a deadly attack does not need to be surprising too), and each further
 * strong criterion lifts it more. An average would let the zeros drown the one big signal.
 * The briefing page runs the same formula in the browser.
 */
export function scoreOf(scores: CriteriaScores, weights: CriteriaScores = DEFAULT_WEIGHTS): number {
  const unlifted = criterionLifts(scores, weights).reduce((rest, lift) => rest * (1 - lift), 1);
  return Math.round((1 - unlifted) * 100);
}

export function levelOf(score: number): PriorityLevel {
  if (score >= LEVEL_THRESHOLDS.critical) return 'critical';
  if (score >= LEVEL_THRESHOLDS.high) return 'high';
  if (score >= LEVEL_THRESHOLDS.notable) return 'notable';
  return 'routine';
}

function distinctSources(stories: BriefingStory[]): string[] {
  return Array.from(new Set(stories.map(story => String(story.source || story.feedUrl).trim()).filter(Boolean)));
}

function coverageNote(names: string[], language: BriefingLanguage = 'en'): string {
  const t = UI[language];
  return names.length > 1 ? t.reportedBy(names.join(', ')) : t.onlyOne(names[0] || t.oneSource);
}

function coverageScore(sourceCount: number): number {
  return sourceCount >= 4 ? 3 : sourceCount === 3 ? 2 : sourceCount === 2 ? 1 : 0;
}

export function ruleRating(
  story: BriefingStory,
  related: BriefingStory[],
  window: { startMs: number; endMs: number },
  context: { localTerms?: string[]; trackedTerms?: string[]; region?: string; language?: BriefingLanguage } = {}
): StoryRating {
  const t = UI[context.language || 'en'];
  const textWords = words(`${story.title} ${story.summary || ''}`);
  // Sports and entertainment words are unambiguous context, while words like "war" or
  // "attack" are often used as metaphors there, so their hits count double.
  const dimensionHits = DIMENSION_TERMS.map(([dimension, terms]) => ({
    dimension,
    hits: termHits(textWords, terms).length * (dimension === 'sports' || dimension === 'culture' ? 2 : 1)
  }));
  const dimension = dimensionHits.reduce((top, entry) => (entry.hits > top.hits ? entry : top), { dimension: 'other' as ImpactDimension, hits: 0 }).dimension;
  const lightweight = dimension === 'sports' || dimension === 'culture';
  const notes: CriteriaNotes = {};

  const severityHits = termHits(textWords, SEVERITY_TERMS);
  let severity = severityHits.length >= 2 ? 3 : severityHits.length === 1 ? 2 : 0;
  if (severity) notes.severity = quoteAround(story, severityHits[0]);
  if (!severity && (dimension === 'security' || dimension === 'health' || dimension === 'environment')) {
    severity = 1;
    notes.severity = t.noHarmYet(t.dimensions[dimension]);
  }
  // Sports and entertainment borrow dramatic words ("war", "attack") without real-world harm.
  if (lightweight && severity > 1) {
    severity = 1;
    notes.severity = t.figureOfSpeech(quoteAround(story, severityHits[0]), t.dimensions[dimension]);
  }

  const scaleHits = termHits(textWords, SCALE_TERMS);
  const countryHits = termHits(textWords, COUNTRY_TERMS);
  const reach = Math.min(3, scaleHits.length + (countryHits.length >= 2 ? 2 : countryHits.length));
  const scale = lightweight ? Math.min(1, reach) : reach;
  if (scale) {
    notes.scale = countryHits.length >= 2
      ? t.severalCountries(countryHits.slice(0, 3).map(hit => `“${hit}”`).join(', '))
      : quoteAround(story, scaleHits[0] || countryHits[0]);
  }

  const urgencyHits = termHits(textWords, URGENCY_TERMS);
  const late = story.publishedMs >= window.endMs - (window.endMs - window.startMs) * 0.3;
  const urgency = Math.min(3, Math.min(2, urgencyHits.length) + (late && urgencyHits.length ? 1 : 0));
  if (urgency) notes.urgency = quoteAround(story, urgencyHits[0]);

  const interestHits = termHits(textWords, INTEREST_TERMS);
  const interest = Math.min(3, interestHits.length * 2);
  if (interest) notes.interest = quoteAround(story, interestHits[0]);

  const sources = distinctSources([story, ...related]);
  const coverage = coverageScore(sources.length);
  const names = sources.map(shortSource);
  notes.coverage = coverageNote(names, context.language);

  // Zero scores get a reason too, so the reader sees what was looked for and not found.
  if (!severity) notes.severity = t.zero.severity;
  if (!scale) notes.scale = t.zero.scale;
  if (!urgency) notes.urgency = t.zero.urgency;
  if (!interest) notes.interest = t.zero.interest;

  const topics = trackedHits(textWords, context.trackedTerms || []);
  const localHits = termHits(textWords, context.localTerms || []);
  const relevance = Math.min(3, (topics.length ? 1 : 0) + (topics.length > 1 ? 1 : 0) + (localHits.length ? 1 : 0));
  const relevanceParts: string[] = [];
  if (topics.length) relevanceParts.push(`${t.yourTopics(topics.length)} ${topics.slice(0, 3).map(topic => `“${topic}”`).join(', ')}`);
  if (localHits.length) relevanceParts.push(`${context.region || t.yourRegion} ${quoteAround(story, localHits[0], 2)}`);
  if (relevanceParts.length) notes.relevance = t.mentions(relevanceParts);
  else if (context.trackedTerms?.length || context.region) {
    notes.relevance = t.noneMentioned(context.trackedTerms?.length || 0, context.region || '');
  }

  return {
    scores: { severity, scale, urgency, interest, coverage, relevance },
    notes,
    dimension,
    impacts: {},
    whyItMatters: story.impact || undefined,
    ratedBy: 'rules'
  };
}

// ---- grouping the same event from several sources ----

const LATIN_OF: Record<string, string> = {
  а: 'a', б: 'b', в: 'v', г: 'g', д: 'd', е: 'e', ж: 'zh', з: 'z', и: 'i', й: 'y', к: 'k', л: 'l', м: 'm', н: 'n', о: 'o',
  п: 'p', р: 'r', с: 's', т: 't', у: 'u', ф: 'f', х: 'h', ц: 'ts', ч: 'ch', ш: 'sh', щ: 'sht', ъ: 'a', ь: 'y', ю: 'yu', я: 'ya'
};

/**
 * A key that survives spelling and script: Latin letters, vowels and doubled letters
 * dropped, first four consonants. "Тесла" and "Tesla" both give "tsl", "Роудстър" and
 * "Roadster" both "rdst", "strikes" and "strike" both "strk".
 */
function wordKey(word: string): string {
  const latin = Array.from(word.toLowerCase(), letter => LATIN_OF[letter] ?? letter).join('');
  return latin.replace(/[aeiouy]/g, '').replace(/(.)\1+/g, '$1').slice(0, 4);
}

/**
 * The title's word keys, and separately the names in it: capitalised words after the
 * first. A title in Title Case has no usable names, since every word is capitalised.
 */
function titleKeys(title: string): { keys: Set<string>; names: Set<string> } {
  const tokens = String(title || '').split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  const capitalised = (token: string) => /^\p{Lu}/u.test(token);
  const titleCase = tokens.filter(token => token.length > 1 && capitalised(token)).length > tokens.length / 2;
  const keys = new Set<string>();
  const names = new Set<string>();
  tokens.forEach((token, index) => {
    const key = wordKey(token);
    if (key.length < 3) return;
    const name = !titleCase && index > 0 && capitalised(token);
    if (token.length >= 4 || name) keys.add(key);
    if (name) names.add(key);
  });
  return { keys, names };
}

/**
 * Groups stories whose titles report the same event; the most informative one leads.
 * `loose` also merges titles that only share names, which is a guess: when the AI groups
 * the briefing it gets those as hints and decides, and the guess applies only without it.
 */
export function clusterStories(stories: BriefingStory[], loose = true): Array<{ story: BriefingStory; related: BriefingStory[] }> {
  const clusters: Array<{ members: BriefingStory[]; keys: Set<string>; names: Set<string> }> = [];
  const seenLinks = new Set<string>();
  const countShared = (a: Set<string>, b: Set<string>) => Array.from(a).filter(key => b.has(key)).length;
  for (const story of [...stories].sort((a, b) => a.publishedMs - b.publishedMs)) {
    const key = (story.link || story.title).trim().toLowerCase();
    if (!key || seenLinks.has(key)) continue;
    seenLinks.add(key);
    const { keys, names } = titleKeys(story.title);
    const match = clusters.find(cluster => {
      const shared = countShared(keys, cluster.keys);
      const union = new Set([...keys, ...cluster.keys]).size || 1;
      // Most of the words in common, or the same two people or things named plus one more
      // word: "Костов, Борисов, Петков и Денков призоваха…" and "Костов, Борисов и Петков: Мирът…"
      // quote different lines of one joint statement.
      return (shared >= 2 && shared / union >= 0.35) || (loose && countShared(names, cluster.names) >= 2 && shared >= 3);
    });
    if (match) {
      match.members.push(story);
      keys.forEach(item => match.keys.add(item));
      names.forEach(item => match.names.add(item));
    } else {
      clusters.push({ members: [story], keys, names });
    }
  }
  const informative = (story: BriefingStory) => (story.summary ? 2 : 0) + (story.coverUrl ? 1 : 0);
  return clusters.map(({ members }) => {
    const lead = [...members].sort((a, b) => informative(b) - informative(a) || a.publishedMs - b.publishedMs)[0];
    return { story: lead, related: members.filter(member => member !== lead) };
  });
}

// ---- AI rating ----

/**
 * Headlines speak in figures of speech ("Черно море удари българската реколта"); taken
 * literally they turn a sea into the one blocking grain exports. Every prompt that writes
 * text for the reader carries this rule.
 */
export const LITERAL_FACTS_RULE = [
  'Say who or what actually does each thing. Headlines use figures of speech: a sea, a market, a city or a country name',
  'often stands for people, ships, a government or a risk ("the Black Sea hit the harvest" means ships avoid the Black',
  'Sea, not that the sea acts). Never repeat such a figure as a fact. If the text does not say who or what causes',
  'something, describe what is known (ships refuse to come to Bulgarian ports) and do not invent or guess a cause.'
].join(' ');

export function buildAiRatingPrompt(candidates: AiRatingCandidate[], language: 'en' | 'bg', region: string): string {
  return [
    `You are a news editor rating how much each story matters to an ordinary reader in ${region || 'their country'}.`,
    'Use only each headline and summary. Be specific to each story: every explanation must name the concrete fact behind it',
    '(a number, place, person, decision, amount or date). Never write generic phrases such as "significant impact",',
    '"important development", "affects many people" or "relevant to readers".',
    LITERAL_FACTS_RULE,
    'Score four criteria from 0 (none) to 3 (strong):',
    `- severity: ${CRITERIA_TEXT.severity}. Sports, celebrity and entertainment score 0-1 even with dramatic words like "war" or "attack".`,
    '- scale: 1 one town or group, 2 a whole country, 3 several countries or the world.',
    '- urgency: 3 happening now or a deadline within days, 2 this week, 1 slow-moving, 0 none.',
    '- interest: how surprising, new or revealing it is (a first, a record, an unexpected twist, a hidden fact). Routine statements and scheduled events score 0-1.',
    'For each criterion add "<criterion>Why": at most 15 words naming the fact, e.g. "29 pupils killed when a school roof fell in Khyber Pakhtunkhwa".',
    'Fill it for low scores too, saying what this story lacks, e.g. severityWhy "A TV casting change; no one is harmed and no money is at stake".',
    'Add "impacts" with one specific sentence (at most 25 words) per angle about THIS story:',
    '- economic: prices, jobs, markets, budgets, trade, energy, investment. Always fill it; if the effect is indirect, explain the chain (e.g. strikes on refineries -> fuel supply -> pump prices).',
    '- political: governments, laws, elections, diplomacy, institutions.',
    '- social: daily life, health, education, rights, communities.',
    '- security: physical safety, conflict, crime, infrastructure.',
    'Fill at least two angles for every story, the economic one and the next most affected; use "" only where there is truly no effect.',
    `Pick one dimension from: ${IMPACT_DIMENSIONS.join(', ')}.`,
    `Write every text field in ${language === 'bg' ? 'Bulgarian' : 'English'}.`,
    'Return strict JSON only: {"ratings":[{"id":"...","severity":0,"severityWhy":"...","scale":0,"scaleWhy":"...","urgency":0,"urgencyWhy":"...","interest":0,"interestWhy":"...","dimension":"economy","impacts":{"economic":"...","political":"","social":"","security":""}}]}',
    'Include every candidate exactly once.',
    `Candidates: ${JSON.stringify(candidates)}`
  ].join('\n');
}

export function parseAiRatings(text: string): AiStoryRating[] {
  const raw = String(text || '');
  const start = raw.indexOf('{');
  const end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) return [];
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw.slice(start, end + 1));
  } catch {
    return [];
  }
  const list = (parsed as { ratings?: unknown })?.ratings;
  if (!Array.isArray(list)) return [];
  const textOf = (value: unknown, max: number) => (typeof value === 'string' ? value.trim().slice(0, max) : '');
  return list.flatMap((entry): AiStoryRating[] => {
    const item = (entry || {}) as Record<string, unknown>;
    const id = textOf(item.id, 200);
    if (!id) return [];
    const rawImpacts = (item.impacts || {}) as Record<string, unknown>;
    const impacts: StoryImpacts = {};
    for (const angle of IMPACT_ANGLES) {
      const value = textOf(rawImpacts[angle], 300);
      if (value) impacts[angle] = value;
    }
    return [{
      id,
      severity: clamp(item.severity as number),
      severityWhy: textOf(item.severityWhy, 200),
      scale: clamp(item.scale as number),
      scaleWhy: textOf(item.scaleWhy, 200),
      urgency: clamp(item.urgency as number),
      urgencyWhy: textOf(item.urgencyWhy, 200),
      interest: clamp(item.interest as number),
      interestWhy: textOf(item.interestWhy, 200),
      dimension: IMPACT_DIMENSIONS.includes(item.dimension as ImpactDimension) ? item.dimension as ImpactDimension : 'other',
      impacts
    }];
  });
}

/**
 * One short call over the headlines only: grouping needs every story in the same answer,
 * so labels stay consistent, while the detailed ratings run in parallel batches.
 */
export type GroupingItem = {
  id: string;
  title: string;
  summary?: string;
  /** Ids whose headlines name the same people or things: a hint to check, not a verdict. */
  maybeSameAs?: string[];
};
export type StoryGrouping = {
  /** Sets of ids that report the very same happening. */
  duplicates: string[][];
  /** Why each set in `duplicates` is one happening, by position. */
  duplicateWhy?: string[];
  /** id → label of the larger ongoing situation it belongs to. */
  storylines: Map<string, string>;
  /** Storyline label → how its stories connect. */
  storylineWhy?: Map<string, string>;
};

/**
 * One short call over all the headlines at once. Duplicates come back as explicit lists
 * of ids, not shared labels: separately written labels such as "military strike" match
 * by accident and glue unrelated stories together. Each group carries the AI's reason,
 * which the page shows, so a wrong group is easy to spot.
 */
export function buildStorylinePrompt(items: GroupingItem[], language: 'en' | 'bg'): string {
  return [
    'You are a news editor. You are given news items (id, headline, summary). Read what each one is actually about,',
    'who does what, where and when, and then do two things.',
    LITERAL_FACTS_RULE,
    '1. "duplicates": sets of ids that report the SAME happening: one announcement, statement, decision, incident,',
    '   product reveal or match, covered by different outlets. They are duplicates even when the headlines quote',
    '   different lines of it, use different words, another language or another spelling of a name (Tesla / Тесла,',
    '   Roadster / Роудстър). A joint statement by the same people reported twice is one happening. Two different',
    '   strikes, statements by one person on different subjects, or two events in the same war are NOT duplicates.',
    '   "maybeSameAs" lists items whose headlines name the same people or things. Check each of them against the',
    '   summaries and decide; sharing names alone does not make two items one happening.',
    '   For each set add "why": one sentence naming the shared happening, e.g. "Both report the four former prime',
    '   ministers\' joint call on Radev over national security".',
    '2. "storylines": larger ongoing situations that at least two DIFFERENT happenings belong to, for example a drone',
    '   strike on a ship, a naval command offer and a moratorium proposal that are all about Black Sea security.',
    '   A storyline is ONE specific situation with the same main actors or place (one war, one crisis, one negotiation),',
    '   never a broad theme: "military conflicts in the region", "the economy" or "world politics" are not storylines,',
    '   and strikes in the Persian Gulf and a grain blockade in the Black Sea are two different situations.',
    '   The label names the situation itself (who or where), e.g. "Iran\'s strikes on US bases".',
    '   Put an item in a storyline only if its subject IS that situation. A sports, celebrity or entertainment item',
    '   never joins a war, politics or economy storyline, even when it uses words like "war", "attack" or "drama".',
    `   Give each a 2-5 word label, a "why" sentence saying how its items connect, and the ids that belong to it.`,
    '   An item can be in at most one storyline. Most items belong to none.',
    `Write labels and reasons in ${language === 'bg' ? 'Bulgarian' : 'English'}.`,
    'Return strict JSON only: {"duplicates":[{"ids":["id","id"],"why":"..."}],"storylines":[{"label":"...","why":"...","ids":["id","id"]}]}',
    `Items: ${JSON.stringify(items)}`
  ].join('\n');
}

export function parseStorylines(text: string): StoryGrouping {
  const raw = String(text || '');
  const start = raw.indexOf('{');
  const end = raw.lastIndexOf('}');
  const result: StoryGrouping = { duplicates: [], duplicateWhy: [], storylines: new Map(), storylineWhy: new Map() };
  if (start < 0 || end <= start) return result;
  try {
    const parsed = JSON.parse(raw.slice(start, end + 1)) as { duplicates?: unknown; storylines?: unknown };
    const ids = (value: unknown) => (Array.isArray(value) ? value.filter((id): id is string => typeof id === 'string' && !!id.trim()).map(id => id.trim()) : []);
    const textOf = (value: unknown, max: number) => (typeof value === 'string' ? value.trim().slice(0, max) : '');
    if (Array.isArray(parsed?.duplicates)) {
      for (const set of parsed.duplicates) {
        // Either {"ids": [...], "why": "..."} or a bare list of ids.
        const members = Array.from(new Set(ids(Array.isArray(set) ? set : set?.ids)));
        // A long list is the model lumping a whole topic together, not one happening.
        if (members.length < 2 || members.length > 6) continue;
        result.duplicates.push(members);
        result.duplicateWhy!.push(Array.isArray(set) ? '' : textOf(set?.why, 240));
      }
    }
    if (Array.isArray(parsed?.storylines)) {
      for (const line of parsed.storylines) {
        const label = textOf(line?.label, 60);
        if (!label) continue;
        const why = textOf(line?.why, 240);
        if (why) result.storylineWhy!.set(label, why);
        for (const id of ids(line?.ids)) if (!result.storylines.has(id)) result.storylines.set(id, label);
      }
    }
  } catch {
    // No grouping.
  }
  return result;
}

/** Coverage counts every source that reported the event, including folded reports. */
function withCoverage(entry: RatedStory, aiRan: boolean, language: BriefingLanguage): RatedStory {
  const sources = distinctSources([entry.story, ...entry.related]);
  const names = sources.map(shortSource);
  const scores = { ...entry.rating.scores, coverage: coverageScore(sources.length) };
  const notes = { ...entry.rating.notes, coverage: coverageNote(names, language) };
  const raw = scoreOf(scores);
  const score = aiRan && entry.rating.ratedBy === 'rules' ? Math.min(raw, UNCHECKED_SCORE_CAP) : raw;
  return { ...entry, rating: { ...entry.rating, scores, notes }, score, level: levelOf(score) };
}

/**
 * Folds each set of duplicate reports into its strongest story (the others become the
 * "more reports" rows), then marks storylines that at least two remaining stories share.
 */
export function applyGrouping(rated: RatedStory[], grouping: StoryGrouping, aiRan = false, language: BriefingLanguage = 'en'): RatedStory[] {
  const byId = new Map(rated.map(entry => [entry.story.id, entry]));
  const absorbed = new Set<RatedStory>();
  const extraRelated = new Map<RatedStory, BriefingStory[]>();
  const reasons = new Map<RatedStory, string>();
  grouping.duplicates.forEach((set, index) => {
    const members = set.map(id => byId.get(id)).filter((entry): entry is RatedStory => !!entry && !absorbed.has(entry));
    if (members.length < 2) return;
    const [lead, ...rest] = members.sort((a, b) => b.score - a.score || b.story.publishedMs - a.story.publishedMs);
    for (const other of rest) {
      absorbed.add(other);
      extraRelated.set(lead, [...(extraRelated.get(lead) || []), other.story, ...other.related]);
    }
    const why = grouping.duplicateWhy?.[index];
    if (why && !reasons.has(lead)) reasons.set(lead, why);
  });
  const kept = rated
    .filter(entry => !absorbed.has(entry))
    .map(entry => (extraRelated.has(entry)
      ? withCoverage({ ...entry, related: [...entry.related, ...(extraRelated.get(entry) || [])], duplicateWhy: reasons.get(entry) }, aiRan, language)
      : entry));
  const lineOf = (entry: RatedStory) => topicKey(grouping.storylines.get(entry.story.id) || '');
  const members = new Map<string, RatedStory[]>();
  for (const entry of kept) {
    const key = lineOf(entry);
    if (key) members.set(key, [...(members.get(key) || []), entry]);
  }
  // A safety net under the AI: a sports or entertainment story stays in a storyline only
  // beside another of its kind, so a football row never sits inside a war storyline.
  const fits = (entry: RatedStory) => {
    const { dimension } = entry.rating;
    if (dimension !== 'sports' && dimension !== 'culture') return true;
    return (members.get(lineOf(entry)) || []).some(other => other !== entry && other.rating.dimension === dimension);
  };
  const counts = new Map<string, number>();
  for (const entry of kept) {
    const key = lineOf(entry);
    if (key && fits(entry)) counts.set(key, (counts.get(key) || 0) + 1);
  }
  return kept.map(entry => {
    const label = grouping.storylines.get(entry.story.id) || '';
    if (!fits(entry) || (counts.get(topicKey(label)) || 0) < 2) return entry;
    return { ...entry, storyline: label, storylineWhy: grouping.storylineWhy?.get(label) || undefined };
  });
}

/** Sets of ids the loose title rule thinks are the same event, as hints or a fallback. */
export function possibleDuplicates(rated: RatedStory[]): string[][] {
  return clusterStories(rated.map(entry => entry.story), true)
    .filter(cluster => cluster.related.length)
    .map(cluster => [cluster.story.id, ...cluster.related.map(other => other.id)]);
}

// ---- the editor's summary at the top ----

export type DigestKind = 'critical' | 'leading' | 'interesting';
export type DigestBullet = { kind: DigestKind; text: string; ids: string[] };
export type DigestItem = {
  id: string;
  title: string;
  summary: string;
  level: PriorityLevel;
  score: number;
  area: string;
  storyline: string;
  sources: number;
  impacts: StoryImpacts;
};

/**
 * One call over the stories the briefing shows, after rating and grouping: the AI reads
 * them together and writes what matters, joining stories about one situation into one
 * line instead of listing headlines.
 */
export function buildDigestPrompt(items: DigestItem[], language: 'en' | 'bg', region: string): string {
  return [
    `You are the editor of a short news briefing for a reader in ${region || 'their country'}.`,
    'Below are the stories it covers, strongest first, each with its rating level, score (0-100), area, storyline,',
    'number of sources and impacts. Write 3 to 6 bullets that tell the reader what matters in this period.',
    '- Start with what is critical, then what leads. Put stories about the same situation in one bullet and say how',
    '  they connect. Never join unrelated stories; a sports or entertainment story never shares a bullet with a war,',
    '  politics or economy story.',
    '- Each bullet is one or two plain sentences, at most 40 words: what happened, with the concrete fact (who, what,',
    '  number, place), and what it means for the reader. Do not just repeat the headline. No generic phrases such as',
    '  "significant development" or "affects many people".',
    `- ${LITERAL_FACTS_RULE} The story summaries below may themselves repeat a headline's figure of speech; do not copy it.`,
    '- Finish with one bullet of kind "interesting" for the most surprising or unusual story not covered above, if any.',
    '- kind: "critical" for bullets about stories rated critical, "leading" for the other important ones, "interesting" for the last.',
    '- ids: the ids of the stories the bullet is about.',
    `Write in ${language === 'bg' ? 'Bulgarian' : 'English'}.`,
    'Return strict JSON only: {"bullets":[{"kind":"critical","text":"...","ids":["id"]}]}',
    `Stories: ${JSON.stringify(items)}`
  ].join('\n');
}

export function parseDigest(text: string): DigestBullet[] {
  const raw = String(text || '');
  const start = raw.indexOf('{');
  const end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) return [];
  try {
    const list = (JSON.parse(raw.slice(start, end + 1)) as { bullets?: unknown })?.bullets;
    if (!Array.isArray(list)) return [];
    return list.flatMap((entry): DigestBullet[] => {
      const item = (entry || {}) as Record<string, unknown>;
      const text = typeof item.text === 'string' ? item.text.trim().slice(0, 400) : '';
      if (!text) return [];
      const kind: DigestKind = item.kind === 'critical' || item.kind === 'interesting' ? item.kind : 'leading';
      const ids = Array.isArray(item.ids) ? item.ids.filter((id): id is string => typeof id === 'string' && !!id.trim()).map(id => id.trim()) : [];
      return [{ kind, text, ids }];
    }).slice(0, 7);
  } catch {
    return [];
  }
}

function applyAiRating(rule: StoryRating, ai: AiStoryRating): StoryRating {
  const judged = { severity: ai.severityWhy, scale: ai.scaleWhy, urgency: ai.urgencyWhy, interest: ai.interestWhy };
  const notes: CriteriaNotes = { coverage: rule.notes.coverage, relevance: rule.notes.relevance };
  for (const key of Object.keys(judged) as Array<keyof typeof judged>) {
    notes[key] = judged[key] || rule.notes[key];
  }
  return {
    scores: { ...rule.scores, severity: ai.severity, scale: ai.scale, urgency: ai.urgency, interest: ai.interest },
    notes,
    dimension: ai.dimension,
    impacts: ai.impacts,
    whyItMatters: rule.whyItMatters,
    ratedBy: 'ai'
  };
}

// ---- picking a varied list ----

function topicKey(topic: string): string {
  return words(topic).join(' ');
}

/**
 * Highest score first, but no dimension takes more than ~30% of the list.
 * The cap is relaxed only when nothing else is left. The briefing page runs the
 * same rule in the browser when the reader moves the sliders.
 */
export function pickVaried(rated: RatedStory[], limit: number): RatedStory[] {
  const sorted = [...rated].sort((a, b) => b.score - a.score || b.story.publishedMs - a.story.publishedMs);
  const dimensionCap = Math.max(2, Math.ceil(limit * 0.3));
  const picked: RatedStory[] = [];
  const perDimension = new Map<ImpactDimension, number>();
  const overflow: RatedStory[] = [];
  for (const entry of sorted) {
    if (picked.length >= limit) break;
    const count = perDimension.get(entry.rating.dimension) || 0;
    if (count >= dimensionCap) {
      overflow.push(entry);
      continue;
    }
    perDimension.set(entry.rating.dimension, count + 1);
    picked.push(entry);
  }
  for (const entry of overflow) {
    if (picked.length >= limit) break;
    picked.push(entry);
  }
  return picked.sort((a, b) => b.score - a.score || b.story.publishedMs - a.story.publishedMs);
}

// ---- windows and titles ----

/** The hour or day that ends now. */
export function rollingWindow(period: BriefingPeriod, nowMs: number): { startMs: number; endMs: number } {
  return { startMs: nowMs - (period === 'day' ? 24 * HOUR_MS : HOUR_MS), endMs: nowMs };
}

function formatTime(ms: number, language: BriefingLanguage = 'en'): string {
  return new Date(ms).toLocaleTimeString(UI[language].locale, { hour: '2-digit', minute: '2-digit' });
}

function formatDay(ms: number, language: BriefingLanguage = 'en'): string {
  return new Date(ms).toLocaleDateString(UI[language].locale, { weekday: 'short', day: 'numeric', month: 'short' });
}

export function briefingTitle(period: BriefingPeriod, scope: string, startMs: number, endMs: number, language: BriefingLanguage = 'en'): string {
  const day = (ms: number) => formatDay(ms, language);
  const time = (ms: number) => formatTime(ms, language);
  const when = period === 'day'
    ? `${day(startMs)} ${time(startMs)} – ${day(endMs)} ${time(endMs)}`
    : `${day(startMs)}, ${time(startMs)}–${time(endMs)}`;
  return `${UI[language].title(period)} · ${scope} · ${when}`;
}

// ---- HTML ----

function escapeHtml(value: string): string {
  return String(value || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function safeUrl(link: string | undefined): string {
  const value = String(link || '').trim();
  return /^https?:\/\//i.test(value) ? value : '';
}

/** JSON that is safe to place inside a <script> element. */
function scriptJson(value: unknown): string {
  return JSON.stringify(value)
    .replace(/</g, '\\u003c')
    .replace(/\u2028/g, '\\u2028')
    .replace(/\u2029/g, '\\u2029');
}

const PRESETS: Array<{ name: string; weights: CriteriaScores }> = [
  { name: 'Balanced', weights: DEFAULT_WEIGHTS },
  { name: 'Critical first', weights: { severity: 5, scale: 3, urgency: 3, interest: 0.5, coverage: 2, relevance: 1 } },
  { name: 'Interesting', weights: { severity: 1, scale: 1, urgency: 0.5, interest: 5, coverage: 1, relevance: 2 } },
  { name: 'Close to home', weights: { severity: 2, scale: 1, urgency: 1.5, interest: 1.5, coverage: 1, relevance: 5 } }
];

// Runs in the browser: ranks and draws the stories with the reader's slider weights.
// It mirrors scoreOf, levelOf and pickVaried above and builds the DOM without innerHTML.
const PAGE_SCRIPT = String.raw`
(() => {
  const data = JSON.parse(document.getElementById('briefing-data').textContent);
  const T = data.text;
  const fill = (text, values) => text.replace(/\{(\w+)\}/g, (_, key) => String(values[key]));
  // Score breakdowns the reader opened stay open when the sliders redraw the list.
  const openWhy = new Set();
  const KEYS = data.criteria.map(c => c.key);
  const STORE = 'ai-news-briefing-weights';
  const sameWeights = (a, b) => KEYS.every(k => a[k] === b[k]);
  let weights = load();

  function load() {
    try {
      const saved = JSON.parse(localStorage.getItem(STORE) || 'null');
      if (saved && KEYS.every(k => typeof saved[k] === 'number')) return saved;
    } catch (e) {}
    return Object.assign({}, data.defaults);
  }
  function save() {
    try { localStorage.setItem(STORE, JSON.stringify(weights)); } catch (e) {}
  }
  function lifts(scores) {
    const heaviest = Math.max(0, ...KEYS.map(k => weights[k]));
    return KEYS.map(k => heaviest ? Math.max(0, weights[k]) / heaviest * scores[k] / 3 * data.strength : 0);
  }
  function scoreOf(scores) {
    return Math.round((1 - lifts(scores).reduce((rest, lift) => rest * (1 - lift), 1)) * 100);
  }
  function levelOf(score) {
    const t = data.thresholds;
    return score >= t.critical ? 'critical' : score >= t.high ? 'high' : score >= t.notable ? 'notable' : 'routine';
  }
  // A unit is one story, or a storyline: several different stories about one ongoing
  // situation, shown together and ranked by their strongest story.
  function rank() {
    const all = data.stories.map((story, index) => {
      const raw = scoreOf(story.scores);
      const score = data.aiRan && story.ratedBy === 'rules' ? Math.min(raw, data.uncheckedCap) : raw;
      return { story, index, score, level: levelOf(score) };
    }).sort((a, b) => b.score - a.score || b.story.publishedMs - a.story.publishedMs);
    const units = [], byLine = {};
    for (const entry of all) {
      const key = (entry.story.storyline || '').toLowerCase().trim();
      if (key && byLine[key]) { byLine[key].entries.push(entry); continue; }
      const unit = { label: entry.story.storyline || '', entries: [entry], score: entry.score, level: entry.level, dimension: entry.story.dimension, publishedMs: entry.story.publishedMs };
      if (key) byLine[key] = unit;
      units.push(unit);
    }
    const cap = Math.max(2, Math.ceil(data.limit * 0.3));
    const picked = [], overflow = [], per = {};
    for (const unit of units) {
      if (picked.length >= data.limit) break;
      if ((per[unit.dimension] || 0) >= cap) { overflow.push(unit); continue; }
      per[unit.dimension] = (per[unit.dimension] || 0) + 1;
      picked.push(unit);
    }
    while (picked.length < data.limit && overflow.length) picked.push(overflow.shift());
    const byScore = (a, b) => b.score - a.score || b.publishedMs - a.publishedMs;
    return { picked: picked.sort(byScore), rest: units.filter(unit => !picked.includes(unit)) };
  }

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }
  function link(href, text) {
    if (!href) return el('span', '', text);
    const a = el('a', '', text);
    a.href = href;
    a.target = '_blank';
    a.rel = 'noopener noreferrer';
    return a;
  }

  function card(entry) {
    const { story, score, level } = entry;
    const article = el('article', 'level-' + level);
    article.id = 's-' + entry.index;
    if (story.coverUrl) {
      const img = el('img', 'cover');
      img.src = story.coverUrl;
      img.alt = '';
      img.loading = 'lazy';
      img.referrerPolicy = 'no-referrer';
      img.onerror = () => img.remove();
      article.append(img);
    }
    const body = el('div', 'body');
    const meta = el('p', 'meta');
    meta.append(el('span', 'badge', data.levelLabels[level] + ' · ' + score), ' ' + [story.source, story.time, story.dimensionLabel].filter(Boolean).join(' · '));
    if (story.ratedBy === 'rules') {
      const tag = el('span', 'rules-tag', data.aiRan ? T.notChecked : T.keywordRated);
      tag.title = data.aiRan ? T.notCheckedTip : T.keywordTip;
      meta.append(' · ', tag);
    }
    const h3 = el('h3');
    h3.append(link(story.link, story.title));
    body.append(meta, h3);
    if (story.summary) body.append(el('p', 'summary', story.summary));

    const angles = data.angles.filter(a => story.impacts[a.key]);
    if (angles.length) {
      const box = el('div', 'impacts');
      for (const angle of angles) {
        const row = el('p', 'impact');
        row.append(el('span', 'angle angle-' + angle.key, angle.label), ' ' + story.impacts[angle.key]);
        box.append(row);
      }
      body.append(box);
    } else if (story.whyItMatters) {
      const row = el('p', 'impact');
      row.append(el('span', 'angle', T.whyItMatters), ' ' + story.whyItMatters);
      body.append(row);
    }

    // The breakdown is folded away; the badge already says the level and score.
    const rated = el('details', 'rated');
    rated.open = openWhy.has(entry.index);
    rated.addEventListener('toggle', () => { if (rated.open) openWhy.add(entry.index); else openWhy.delete(entry.index); });
    rated.append(el('summary', 'rated-head', fill(T.why, { level: data.levelLabels[level], score })));
    const list = el('ul');
    // Each criterion's share of the score, in proportion to how hard it pushed.
    const storyLifts = lifts(story.scores);
    const liftSum = storyLifts.reduce((sum, lift) => sum + lift, 0);
    data.criteria.forEach((c, i) => {
      const value = story.scores[c.key];
      const li = el('li', value ? '' : 'zero');
      const points = liftSum ? Math.round(score * storyLifts[i] / liftSum) : 0;
      li.append(
        el('span', 'cname', c.label),
        el('span', 'dots', '●'.repeat(value) + '○'.repeat(3 - value)),
        el('span', 'pts', '+' + points),
        el('span', 'note', story.notes[c.key] || c.text)
      );
      list.append(li);
    });
    rated.append(list);
    body.append(rated);

    if (story.related.length) {
      // Other reports of the same event, folded away under the main story.
      const dupes = el('details', 'dupes');
      const sources = Array.from(new Set(story.related.map(other => other.source).filter(Boolean)));
      dupes.append(el('summary', '', fill(story.related.length === 1 ? T.moreOne : T.moreMany, { n: story.related.length }) + (sources.length ? ' · ' + sources.slice(0, 3).join(', ') + (sources.length > 3 ? '…' : '') : '')));
      const rows = el('ul');
      if (story.duplicateWhy) rows.append(el('li', 'dupe-why', story.duplicateWhy));
      story.related.forEach(other => {
        const row = el('li');
        row.append(el('span', 'dupe-meta', [other.source, other.time].filter(Boolean).join(' · ')), link(other.link, other.title));
        rows.append(row);
      });
      dupes.append(rows);
      body.append(dupes);
    }
    article.append(body);
    return article;
  }

  function unitNode(unit) {
    if (unit.entries.length < 2) return card(unit.entries[0]);
    const box = el('div', 'storyline level-' + unit.level);
    const head = el('div', 'storyline-head');
    head.append(
      el('span', 'storyline-kicker', T.storyline),
      el('span', 'storyline-label', unit.label),
      el('span', 'storyline-count', fill(T.differentStories, { n: unit.entries.length }))
    );
    box.append(head);
    const why = unit.entries.map(entry => entry.story.storylineWhy).find(Boolean);
    if (why) box.append(el('p', 'storyline-why', why));
    unit.entries.forEach(entry => box.append(card(entry)));
    return box;
  }

  // The summary at the top. The AI writes it when it can, reading the stories together;
  // otherwise it lists every Critical and High story (up to five), topped up to three with
  // the next strongest, plus the most surprising one. Each line jumps to its card.
  function jumpTo(index, text) {
    const a = el('a', '', text);
    a.href = '#s-' + index;
    a.addEventListener('click', () => {
      // A story pushed under "More stories" by the sliders is folded away; open it first.
      const target = document.getElementById('s-' + index);
      const fold = target && target.closest('details:not([open])');
      if (fold) fold.open = true;
    });
    return a;
  }
  // No level words on the lines: the order already says what leads, and the AI tends to
  // call everything critical. The dot takes the colour of the strongest story a line
  // points to, at the current slider weights; only the closing curiosity is marked.
  function glanceLines(picked) {
    const entries = picked.flatMap(unit => unit.entries).sort((a, b) => b.score - a.score || b.story.publishedMs - a.story.publishedMs);
    const levelAt = {};
    entries.forEach(e => { levelAt[e.index] = e.level; });
    const order = ['critical', 'high', 'notable', 'routine'];
    const levelOfTargets = targets => order.find(level => targets.some(i => levelAt[i] === level)) || 'routine';
    if (data.digest.length) {
      return data.digest.map(bullet => ({
        cls: 'level-' + levelOfTargets(bullet.targets),
        tag: bullet.kind === 'interesting' ? T.alsoInteresting : '',
        text: bullet.text,
        targets: bullet.targets
      }));
    }
    const lead = entries.filter(e => e.level === 'critical' || e.level === 'high').slice(0, 5);
    for (const e of entries) {
      if (lead.length >= 3) break;
      if (!lead.includes(e)) lead.push(e);
    }
    const curious = entries
      .filter(e => !lead.includes(e) && e.story.scores.interest >= 2)
      .sort((a, b) => b.story.scores.interest - a.story.scores.interest || b.score - a.score)[0];
    const line = (e, tag) => ({ tag, cls: 'level-' + e.level, text: e.story.summary || e.story.title, targets: [e.index] });
    return lead.map(e => line(e, '')).concat(curious ? [line(curious, T.alsoInteresting)] : []);
  }
  function glance(picked) {
    const lines = glanceLines(picked);
    if (!lines.length) return null;
    const box = el('section', 'glance');
    const head = el('h2', '', T.atAGlance);
    if (data.digest.length) head.append(el('span', 'glance-by', T.writtenByAi));
    box.append(head);
    const list = el('ul');
    for (const line of lines) {
      const li = el('li', line.cls);
      if (line.tag) li.append(el('span', 'glance-tag', line.tag));
      if (line.targets.length === 1) {
        li.append(jumpTo(line.targets[0], line.text));
      } else {
        li.append(el('span', 'glance-text', line.text));
        line.targets.forEach(index => {
          const source = data.stories[index] && data.stories[index].source;
          li.append(' ', jumpTo(index, '→ ' + (source || T.story)));
        });
      }
      list.append(li);
    }
    box.append(list);
    return box;
  }

  function section(title, units) {
    const s = el('section');
    s.append(el('h2', '', title));
    units.forEach(unit => s.append(unitNode(unit)));
    return s;
  }

  function render() {
    const { picked, rest } = rank();
    const root = document.getElementById('stories');
    root.replaceChildren();
    if (!data.stories.length) {
      root.append(el('p', 'empty', T.empty));
    } else {
      const summary = glance(picked);
      if (summary) root.append(summary);
      const priority = picked.filter(e => e.level === 'critical' || e.level === 'high');
      const others = picked.filter(e => e.level !== 'critical' && e.level !== 'high');
      if (priority.length) root.append(section(T.priority, priority));
      if (others.length) root.append(section(priority.length ? T.alsoWorth : T.stories, others));
      if (rest.length) {
        const more = el('details', 'more');
        const restCount = rest.reduce((n, unit) => n + unit.entries.length, 0);
        more.append(el('summary', '', fill(T.moreStories, { n: restCount })));
        rest.forEach(unit => more.append(unitNode(unit)));
        root.append(more);
      }
    }
    const counts = {};
    const shown = picked.flatMap(unit => unit.entries);
    shown.forEach(e => { counts[e.story.dimensionLabel] = (counts[e.story.dimensionLabel] || 0) + 1; });
    const mix = document.getElementById('mix');
    mix.replaceChildren(...Object.entries(counts).sort((a, b) => b[1] - a[1]).map(([label, n]) => el('span', 'chip', label + ' ' + n)));
    document.getElementById('count').textContent = fill(T.of, { a: shown.length, b: data.storyCount });
    for (const k of KEYS) {
      document.getElementById('w-' + k).value = String(weights[k]);
      document.getElementById('v-' + k).textContent = String(weights[k]);
    }
    document.querySelectorAll('.preset').forEach(button => {
      button.classList.toggle('on', sameWeights(weights, data.presets[Number(button.dataset.i)].weights));
    });
    const preset = data.presets.find(p => sameWeights(weights, p.weights));
    document.getElementById('eq-current').textContent = preset ? preset.name : T.custom;
  }

  // The criteria side panel and the floating buttons work from anywhere on the page.
  const eqBox = document.getElementById('eq');
  const eqBackdrop = document.getElementById('eq-backdrop');
  const eqToggle = document.getElementById('eq-toggle');
  const wide = window.matchMedia('(min-width: 1240px)');
  function setEqOpen(open) {
    if (wide.matches) open = false;
    eqBox.setAttribute('aria-hidden', String(!open && !wide.matches));
    eqBox.classList.toggle('open', open);
    eqBackdrop.classList.toggle('open', open);
    eqToggle.setAttribute('aria-expanded', String(open));
  }
  eqToggle.addEventListener('click', () => setEqOpen(!eqBox.classList.contains('open')));
  document.getElementById('eq-close').addEventListener('click', () => setEqOpen(false));
  eqBackdrop.addEventListener('click', () => setEqOpen(false));
  document.addEventListener('keydown', event => { if (event.key === 'Escape') setEqOpen(false); });
  wide.addEventListener('change', () => setEqOpen(false));
  setEqOpen(false);
  document.getElementById('go-top').addEventListener('click', () => window.scrollTo({ top: 0, behavior: 'smooth' }));
  document.getElementById('go-bottom').addEventListener('click', () => window.scrollTo({ top: document.documentElement.scrollHeight, behavior: 'smooth' }));

  const eq = document.getElementById('eq-bands');
  for (const c of data.criteria) {
    const band = el('label', 'band');
    band.title = c.text;
    const value = el('span', 'bval');
    value.id = 'v-' + c.key;
    const input = el('input');
    input.type = 'range';
    input.min = '0';
    input.max = '5';
    input.step = '0.5';
    input.id = 'w-' + c.key;
    input.setAttribute('aria-label', fill(T.bandAria, { label: c.label }));
    input.addEventListener('input', () => {
      weights = Object.assign({}, weights, { [c.key]: Number(input.value) });
      save();
      render();
    });
    band.append(el('span', 'bname', c.label), value, input, el('span', 'bdesc', c.text));
    eq.append(band);
  }
  const presets = document.getElementById('eq-presets');
  data.presets.forEach((preset, i) => {
    const button = el('button', 'preset', preset.name);
    button.type = 'button';
    button.dataset.i = String(i);
    button.addEventListener('click', () => {
      weights = Object.assign({}, preset.weights);
      save();
      render();
    });
    presets.append(button);
  });
  render();
})();
`;

/** "Al Jazeera – Breaking News, World News…" → "Al Jazeera". */
function shortSource(source: string): string {
  return String(source || '').split(/\s+[–—|-]\s+/)[0].trim();
}

function pageStory(entry: RatedStory, language: BriefingLanguage) {
  const { story, rating } = entry;
  return {
    title: story.title,
    link: safeUrl(story.link),
    source: shortSource(story.source || ''),
    time: formatTime(story.publishedMs, language),
    publishedMs: story.publishedMs,
    summary: story.summary || '',
    coverUrl: safeUrl(story.coverUrl),
    dimension: rating.dimension,
    dimensionLabel: UI[language].dimensions[rating.dimension],
    scores: rating.scores,
    notes: rating.notes,
    impacts: rating.impacts,
    whyItMatters: rating.whyItMatters || '',
    ratedBy: rating.ratedBy,
    storyline: entry.storyline || '',
    storylineWhy: entry.storylineWhy || '',
    duplicateWhy: entry.duplicateWhy || '',
    related: entry.related
      .sort((a, b) => a.publishedMs - b.publishedMs)
      .map(other => ({ title: other.title, source: shortSource(other.source || ''), time: formatTime(other.publishedMs, language), link: safeUrl(other.link) }))
  };
}

export function renderBriefingHtml(
  title: string, stories: RatedStory[], limit: number, storyCount: number, generatedAtMs: number, aiRan = false, digest: DigestBullet[] = [],
  language: BriefingLanguage = 'en'
): string {
  const t = UI[language];
  const ratedByAi = stories.some(entry => entry.rating.ratedBy === 'ai');
  // A bullet may name a report that was folded under another story; it points to that story.
  const indexById = new Map<string, number>();
  stories.forEach((entry, index) => {
    for (const other of [entry.story, ...entry.related]) if (!indexById.has(other.id)) indexById.set(other.id, index);
  });
  const data = {
    stories: stories.map(entry => pageStory(entry, language)),
    digest: digest.map(bullet => ({
      kind: bullet.kind,
      text: bullet.text,
      targets: Array.from(new Set(bullet.ids.map(id => indexById.get(id)).filter((index): index is number => index !== undefined)))
    })),
    storyCount,
    limit,
    defaults: DEFAULT_WEIGHTS,
    strength: SINGLE_CRITERION_STRENGTH,
    aiRan,
    uncheckedCap: UNCHECKED_SCORE_CAP,
    thresholds: LEVEL_THRESHOLDS,
    presets: PRESETS.map((preset, index) => ({ ...preset, name: t.presets[index] || preset.name })),
    levelLabels: t.levels,
    criteria: CRITERIA.map(key => ({ key, label: t.criteria[key], text: t.criteriaText[key] })),
    angles: IMPACT_ANGLES.map(key => ({ key, label: t.angles[key] })),
    text: t.page
  };
  const legend = CRITERIA
    .map(key => `<li><strong>${escapeHtml(t.criteria[key])}</strong>: ${escapeHtml(t.criteriaText[key])}</li>`)
    .join('');
  const count = t.page.of.replace('{a}', String(Math.min(limit, stories.length))).replace('{b}', String(storyCount));
  return `<!doctype html>
<html lang="${language}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<style>
  :root { --bg: #f6f7f9; --card: #ffffff; --text: #16181d; --muted: #616875; --border: #e2e5ea; --accent: #2f6fde;
    --critical: #c62828; --high: #e07a00; --notable: #2f6fde; --routine: #8a919c; --chip: #eef1f5;
    --economic: #1f8a4c; --political: #6a4cc7; --social: #c2410c; --security: #b42318;
    --storyline: #4b5bbd; --storyline-bg: #eceefb; }
  @media (prefers-color-scheme: dark) {
    :root { --bg: #111317; --card: #1a1d23; --text: #e8eaee; --muted: #9aa1ad; --border: #2a2e36; --accent: #7aa7ff;
      --critical: #ff6b6b; --high: #ffa94d; --notable: #7aa7ff; --routine: #8a919c; --chip: #242830;
      --economic: #4ade80; --political: #a78bfa; --social: #fb923c; --security: #f87171;
      --storyline: #4652a8; --storyline-bg: #1c1f33; }
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--text); font: 15px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
  main { max-width: 860px; margin: 0 auto; padding: 32px 16px 64px; }
  header h1 { font-size: 23px; margin: 0 0 4px; }
  header p { color: var(--muted); margin: 0 0 12px; }
  .mix { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 8px; }
  .chip { background: var(--chip); border-radius: 999px; padding: 2px 10px; font-size: 12px; color: var(--muted); }
  /* The criteria live in a side panel that slides in from anywhere on the page. */
  .eq { position: fixed; top: 0; right: 0; z-index: 40; width: min(340px, 88vw); height: 100%; overflow-y: auto; background: var(--card); border-left: 1px solid var(--border); box-shadow: -8px 0 28px rgba(0, 0, 0, .18); padding: 16px 18px 24px; transform: translateX(105%); transition: transform .22s ease; }
  .eq.open { transform: none; }
  .eq-backdrop { position: fixed; inset: 0; z-index: 35; background: rgba(0, 0, 0, .32); opacity: 0; pointer-events: none; transition: opacity .22s ease; }
  .eq-backdrop.open { opacity: 1; pointer-events: auto; }
  .eq-head { display: flex; align-items: center; justify-content: space-between; }
  .eq-close { font: inherit; font-size: 16px; color: var(--muted); background: none; border: 0; cursor: pointer; padding: 4px 6px; }
  .eq-hint { font-size: 12.5px; color: var(--muted); margin: 6px 0 12px; }
  .fabs { position: fixed; right: 16px; bottom: 16px; z-index: 30; display: flex; gap: 8px; align-items: center; }
  .fab { font: inherit; font-size: 13px; font-weight: 600; color: var(--text); background: var(--card); border: 1px solid var(--border); border-radius: 999px; min-width: 40px; height: 40px; padding: 0 12px; cursor: pointer; box-shadow: 0 4px 14px rgba(0, 0, 0, .16); }
  .fab-eq #eq-current { color: var(--accent); }
  /* Wide windows have room for the criteria as a side menu that is always open, and the
     jump buttons sit half-way down the right edge where they are easy to see. */
  @media (min-width: 1240px) {
    body { padding-left: 330px; }
    .eq { transform: none; width: 330px; left: 0; right: auto; border-left: 0; border-right: 1px solid var(--border); box-shadow: none; transition: none; }
    .eq-close, .eq-backdrop, .fab-eq { display: none; }
    .fabs { flex-direction: column; top: 50%; bottom: auto; right: 24px; transform: translateY(-50%); }
    .fab { width: 46px; height: 46px; font-size: 18px; padding: 0; }
  }
  .eq-title { font-size: 13px; font-weight: 600; color: var(--muted); text-transform: uppercase; letter-spacing: .06em; }
  .preset { font: inherit; font-size: 12.5px; color: var(--muted); background: var(--chip); border: 1px solid transparent; border-radius: 999px; padding: 3px 11px; cursor: pointer; }
  .preset.on { color: var(--accent); border-color: var(--accent); }
  #eq-presets { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 2px; }
  #eq-bands { display: flex; flex-direction: column; gap: 14px; margin-top: 16px; }
  .band { display: grid; grid-template-columns: 1fr auto; gap: 2px 8px; cursor: pointer; }
  .band input { grid-column: 1 / -1; width: 100%; accent-color: var(--accent); margin: 2px 0; }
  .bval { font-size: 13px; font-weight: 600; color: var(--accent); font-variant-numeric: tabular-nums; }
  .bname { font-size: 13.5px; font-weight: 600; color: var(--text); }
  .bdesc { grid-column: 1 / -1; font-size: 12px; color: var(--muted); }
  main { padding-bottom: 88px; }
  h2 { font-size: 13px; letter-spacing: .06em; text-transform: uppercase; color: var(--muted); margin: 28px 0 10px; }
  article { display: flex; gap: 14px; background: var(--card); border: 1px solid var(--border); border-left: 4px solid var(--routine); border-radius: 12px; padding: 14px 16px; margin-bottom: 10px; }
  article.level-critical { border-left-color: var(--critical); }
  article.level-high { border-left-color: var(--high); }
  article.level-notable { border-left-color: var(--notable); }
  .cover { width: 150px; height: 100px; object-fit: cover; border-radius: 8px; flex: none; background: var(--chip); }
  .body { min-width: 0; flex: 1; }
  h3 { font-size: 16px; margin: 2px 0 4px; }
  a { color: var(--accent); text-decoration: none; }
  a:hover { text-decoration: underline; }
  p { margin: 6px 0 0; }
  .meta { color: var(--muted); font-size: 12.5px; margin-top: 0; }
  .badge { font-weight: 600; color: var(--routine); }
  .level-critical .badge { color: var(--critical); }
  .level-high .badge { color: var(--high); }
  .level-notable .badge { color: var(--notable); }
  .impacts { margin-top: 8px; }
  .impact { margin-top: 4px; }
  .angle { display: inline-block; min-width: 72px; font-size: 11.5px; font-weight: 600; text-transform: uppercase; letter-spacing: .04em; color: var(--muted); }
  .angle-economic { color: var(--economic); }
  .angle-political { color: var(--political); }
  .angle-social { color: var(--social); }
  .angle-security { color: var(--security); }
  .rated { margin-top: 10px; padding-top: 8px; border-top: 1px dashed var(--border); font-size: 13px; color: var(--muted); }
  .rated-head { font-weight: 600; cursor: pointer; width: fit-content; }
  .rated[open] .rated-head { margin-bottom: 4px; }
  .rated ul { list-style: none; margin: 0; padding: 0; }
  .rated li { display: grid; grid-template-columns: 88px 34px 34px 1fr; gap: 6px; align-items: baseline; }
  .cname { color: var(--text); white-space: nowrap; overflow-wrap: normal; }
  .dots { letter-spacing: 1px; color: var(--accent); font-size: 11px; white-space: nowrap; }
  .pts { font-variant-numeric: tabular-nums; color: var(--text); }
  .rated li.zero, .rated li.zero .cname, .rated li.zero .pts { opacity: .6; }
  .rules-tag { font-style: italic; }
  html { scroll-behavior: smooth; }
  article { scroll-margin-top: 16px; }
  article:target { box-shadow: 0 0 0 2px var(--accent); }
  .glance { background: var(--card); border: 1px solid var(--border); border-radius: 12px; padding: 12px 16px 14px; margin-top: 18px; }
  .glance h2 { margin: 0 0 6px; }
  .glance ul { margin: 0; padding-left: 18px; }
  .glance li { margin: 6px 0; }
  .glance a { color: var(--text); }
  .glance li::marker { color: var(--routine); font-size: 1.15em; }
  .glance li.level-critical::marker { color: var(--critical); }
  .glance li.level-high::marker { color: var(--high); }
  .glance li.level-notable::marker { color: var(--notable); }
  .glance-tag { font-size: 12.5px; font-weight: 600; color: var(--political); margin-right: 8px; }
  .glance-text ~ a { font-size: 12.5px; white-space: nowrap; color: var(--accent); }
  .glance-by { margin-left: 8px; font-size: 11.5px; font-weight: 400; letter-spacing: 0; text-transform: none; }
  .dupe-why { font-style: italic; }
  /* A storyline is framed in its own colour with a header bar, so it reads as one group
     and it is obvious where it ends and the next, unrelated story begins. */
  .storyline { border: 2px solid var(--storyline); border-radius: 14px; margin: 26px 0; background: var(--storyline-bg); overflow: hidden; }
  .storyline-head { display: flex; flex-wrap: wrap; align-items: baseline; gap: 4px 10px; padding: 10px 16px; background: var(--storyline); color: #fff; }
  .storyline-kicker { font-size: 11px; font-weight: 700; letter-spacing: .06em; text-transform: uppercase; opacity: .85; }
  .storyline-count { opacity: .85; }
  .storyline-why { margin: 10px 16px 0; font-size: 13px; color: var(--muted); }
  .storyline > article { margin: 10px 10px 0; }
  .storyline > article:last-child { margin-bottom: 10px; }
  .storyline-label { font-weight: 700; font-size: 15px; }
  .storyline-count { font-size: 12.5px; }
  .dupes { margin-top: 8px; font-size: 13px; color: var(--muted); }
  .dupes summary { cursor: pointer; }
  .dupes ul { list-style: none; margin: 6px 0 0; padding: 0 0 0 14px; border-left: 2px solid var(--border); }
  .dupes li { margin: 4px 0; }
  .dupe-meta { display: inline-block; min-width: 140px; margin-right: 8px; }
  .more { margin-top: 20px; }
  .more summary { cursor: pointer; color: var(--muted); margin-bottom: 10px; }
  .empty, footer { color: var(--muted); }
  footer { margin-top: 36px; font-size: 13px; }
  footer ul { padding-left: 18px; }
  main { overflow-wrap: anywhere; }
  @media (max-width: 560px) {
    main { padding: 20px 12px 48px; }
    header h1 { font-size: 20px; }
    .fabs { right: 12px; bottom: 12px; }
    .storyline > article { margin: 8px 6px 0; }
    article { flex-direction: column; padding: 12px; }
    .cover { width: 100%; height: 160px; }
    .rated li { grid-template-columns: 80px 36px 28px minmax(0, 1fr); gap: 4px; }
    .dots { letter-spacing: 0; }
    .dupe-meta { display: block; min-width: 0; }
  }
</style>
</head>
<body>
<main>
  <header>
    <h1>${escapeHtml(title)}</h1>
    <p>${t.countLine(`<span id="count">${count}</span>`, escapeHtml(new Date(generatedAtMs).toLocaleString(t.locale)))}</p>
    <div class="mix" id="mix"></div>
  </header>
  <div id="stories"></div>
  <footer>
    <p>${t.footer(ratedByAi)}</p>
    <ul>${legend}</ul>
  </footer>
</main>
<div class="eq-backdrop" id="eq-backdrop"></div>
<aside class="eq" id="eq" aria-label="${t.importanceAria}" aria-hidden="true">
  <div class="eq-head">
    <span class="eq-title">${t.importance}</span>
    <button type="button" class="eq-close" id="eq-close" aria-label="${t.close}">✕</button>
  </div>
  <p class="eq-hint">${t.importanceHint}</p>
  <div id="eq-presets"></div>
  <div id="eq-bands"></div>
</aside>
<div class="fabs">
  <button type="button" class="fab fab-eq" id="eq-toggle" aria-controls="eq" aria-expanded="false">${t.importance} · <span id="eq-current"></span></button>
  <button type="button" class="fab" id="go-top" aria-label="${t.goTop}">↑</button>
  <button type="button" class="fab" id="go-bottom" aria-label="${t.goBottom}">↓</button>
</div>
<script id="briefing-data" type="application/json">${scriptJson(data)}</script>
<script>${PAGE_SCRIPT}</script>
</body>
</html>
`;
}

// ---- building ----

export type BriefingOptions = {
  period: BriefingPeriod;
  scope: string;
  window: { startMs: number; endMs: number };
  localTerms?: string[];
  trackedTerms?: string[];
  region?: string;
  /** Rates candidates with AI; omitted or failing falls back to rules. */
  rateWithAi?: (candidates: AiRatingCandidate[]) => Promise<AiStoryRating[]>;
  /** Finds duplicates and storylines from the headlines; omitted or failing falls back to title rules. */
  groupWithAi?: (items: GroupingItem[]) => Promise<StoryGrouping>;
  /** Writes the summary at the top; omitted or failing shows the top stories' own summaries. */
  digestWithAi?: (items: DigestItem[]) => Promise<DigestBullet[]>;
  /** Language of the page and its notes; the AI prompts should use the same one. */
  language?: BriefingLanguage;
  generatedAtMs?: number;
};

export type BriefingRecord = {
  id: string;
  title: string;
  period: BriefingPeriod;
  scope: string;
  scheduled: boolean;
  windowStartMs: number;
  windowEndMs: number;
  generatedAtMs: number;
  itemCount: number;
};

export type Briefing = BriefingRecord & { html: string };

export async function buildBriefing(stories: BriefingStory[], options: BriefingOptions, scheduled = false): Promise<Briefing> {
  const { period, scope, window } = options;
  const generatedAtMs = options.generatedAtMs ?? Date.now();
  const limit = period === 'day' ? 20 : 12;
  const inWindow = stories.filter(story => story.publishedMs >= window.startMs && story.publishedMs < window.endMs);
  const language = options.language || 'en';
  const context = { localTerms: options.localTerms, trackedTerms: options.trackedTerms, region: options.region, language };
  // With the AI grouping the briefing, only near-identical titles are merged up front; looser
  // matches go to it as hints so it decides from what the stories say.
  let rated: RatedStory[] = clusterStories(inWindow, !options.groupWithAi).map(({ story, related }) => {
    const rating = ruleRating(story, related, window, context);
    const score = scoreOf(rating.scores);
    return { story, related, rating, score, level: levelOf(score) };
  });

  // The page holds more than it shows, so moving the sliders can bring other stories up.
  const pageSize = period === 'day' ? 60 : 36;
  let aiRan = false;
  if (options.rateWithAi && rated.length) {
    // Every story that can reach the page goes to the AI (a few spare, since merging the
    // same event shrinks the list), so keyword guesses never decide what leads.
    const candidates = [...rated].sort((a, b) => b.score - a.score).slice(0, pageSize + 10);
    const rateWithAi = options.rateWithAi;
    const toCandidate = (entry: RatedStory): AiRatingCandidate => ({
      id: entry.story.id,
      title: entry.story.title,
      summary: String(entry.story.summary || '').slice(0, 400),
      source: String(entry.story.source || ''),
      alsoReportedBy: distinctSources(entry.related)
    });
    // Small batches in parallel: each answer stays short enough to finish, and one failed
    // batch only leaves its own stories on rule ratings.
    const rateInBatches = async (entries: RatedStory[]) => {
      const batches: RatedStory[][] = [];
      for (let i = 0; i < entries.length; i += 10) batches.push(entries.slice(i, i + 10));
      const results = await Promise.allSettled(batches.map(batch => rateWithAi(batch.map(toCandidate))));
      return results.flatMap(result => (result.status === 'fulfilled' ? result.value : []));
    };
    const byId = new Map((await rateInBatches(candidates)).map(rating => [rating.id, rating]));
    // Answers sometimes skip a story or get cut off; ask once more for the ones missing.
    const missing = candidates.filter(entry => !byId.has(entry.story.id));
    if (missing.length && byId.size) {
      for (const rating of await rateInBatches(missing)) byId.set(rating.id, rating);
    }
    aiRan = byId.size > 0;
    const candidateSet = new Set(candidates);
    rated = rated.map(entry => {
      const ai = candidateSet.has(entry) ? byId.get(entry.story.id) : undefined;
      if (!ai) return entry;
      const rating = applyAiRating(entry.rating, ai);
      const score = scoreOf(rating.scores);
      return { ...entry, rating, score, level: levelOf(score) };
    });
    if (aiRan) {
      // A story the AI never checked cannot claim Critical or High from keywords alone.
      rated = rated.map(entry => {
        if (entry.rating.ratedBy === 'ai') return entry;
        const score = Math.min(entry.score, UNCHECKED_SCORE_CAP);
        return { ...entry, score, level: levelOf(score) };
      });
    }
  }

  let merged = [...rated].sort((a, b) => b.score - a.score || b.story.publishedMs - a.story.publishedMs).slice(0, pageSize);
  if (options.groupWithAi && merged.length >= 2) {
    const hints = possibleDuplicates(merged);
    try {
      const groups = await options.groupWithAi(merged.map(entry => {
        const maybeSameAs = hints.find(set => set.includes(entry.story.id))?.filter(id => id !== entry.story.id);
        return {
          id: entry.story.id,
          title: entry.story.title,
          summary: String(entry.story.summary || '').slice(0, 200),
          ...(maybeSameAs?.length ? { maybeSameAs } : {})
        };
      }));
      merged = applyGrouping(merged, groups, aiRan, language);
    } catch {
      // No AI answer: fall back to the title rule's guesses, without storylines.
      merged = applyGrouping(merged, { duplicates: hints, storylines: new Map() }, aiRan, language);
    }
  }
  const picked = pickVaried(merged, limit);
  let digest: DigestBullet[] = [];
  if (options.digestWithAi && picked.length) {
    try {
      digest = await options.digestWithAi(picked.map(entry => ({
        id: entry.story.id,
        title: entry.story.title,
        summary: String(entry.story.summary || '').slice(0, 300),
        level: entry.level,
        score: entry.score,
        area: UI[language].dimensions[entry.rating.dimension],
        storyline: entry.storyline || '',
        sources: distinctSources([entry.story, ...entry.related]).length,
        impacts: entry.rating.impacts
      })));
    } catch {
      // The page builds its own list from the top stories.
    }
  }
  const title = briefingTitle(period, scope, window.startMs, window.endMs, language);
  return {
    // Random part keeps the URL unguessable: the HTML page is served without a login.
    id: `${window.startMs}-${crypto.randomBytes(9).toString('hex')}`,
    title,
    period,
    scope,
    scheduled,
    windowStartMs: window.startMs,
    windowEndMs: window.endMs,
    generatedAtMs,
    itemCount: picked.length,
    html: renderBriefingHtml(title, merged, limit, inWindow.length, generatedAtMs, aiRan, digest, language)
  };
}

// ---- storage ----

const ID_PATTERN = /^\d+-[0-9a-f]{18}$/;

/** Keeps the newest `keep` briefings as HTML files plus an index.json in `dir`. */
export function createBriefingStore(dir: string, keep = 96) {
  const indexPath = path.join(dir, 'index.json');
  let records: BriefingRecord[] = [];
  try {
    const parsed = JSON.parse(fs.readFileSync(indexPath, 'utf8'));
    if (Array.isArray(parsed)) {
      records = parsed
        .filter(record => ID_PATTERN.test(String(record?.id)))
        .map(record => ({ period: 'hour', scope: 'All columns', scheduled: false, ...record }));
    }
  } catch {
    records = [];
  }

  function write() {
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(indexPath, JSON.stringify(records, null, 2), 'utf8');
  }

  return {
    list(): BriefingRecord[] {
      return records.slice();
    },
    latest(): BriefingRecord | null {
      return records[0] || null;
    },
    readHtml(id: string): string | null {
      if (!ID_PATTERN.test(id) || !records.some(record => record.id === id)) return null;
      try {
        return fs.readFileSync(path.join(dir, `${id}.html`), 'utf8');
      } catch {
        return null;
      }
    },
    save(briefing: Briefing) {
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, `${briefing.id}.html`), briefing.html, 'utf8');
      const { html: _html, ...record } = briefing;
      // A scheduled run replaces an earlier scheduled run for the same hour.
      const replaced = record.scheduled
        ? records.filter(existing => existing.scheduled && existing.windowStartMs === record.windowStartMs)
        : [];
      records = [record, ...records.filter(existing => !replaced.includes(existing))]
        .sort((a, b) => b.generatedAtMs - a.generatedAtMs);
      const dropped = [...replaced, ...records.slice(keep)];
      records = records.slice(0, keep);
      for (const old of dropped) fs.rmSync(path.join(dir, `${old.id}.html`), { force: true });
      write();
    }
  };
}

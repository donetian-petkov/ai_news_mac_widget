import { z } from 'zod';

export const summaryLangSchema = z.union([z.literal('bg'), z.literal('en'), z.literal('bilingual')]);
export const researchLangSchema = z.union([z.literal('bg'), z.literal('en')]);
export const feedKindSchema = z.union([z.literal('rss'), z.literal('reddit'), z.literal('youtube')]);
export const budgetModeSchema = z.union([z.literal('low'), z.literal('standard'), z.literal('high')]);
export const sortModeSchema = z.union([z.literal('newest'), z.literal('oldest'), z.literal('matched')]);
export const aiProviderSchema = z.union([z.literal('openai'), z.literal('claude'), z.literal('openrouter'), z.literal('local')]);
export const aiModelIdSchema = z.string().trim().min(1);
export const briefingDeliverySchema = z.union([z.literal('site'), z.literal('email')]);
export const briefingFormatSchema = z.union([z.literal('executive'), z.literal('bullets'), z.literal('narrative')]);
export const aiFeatureSettingsSchema = z.object({
  biasDetection: z.boolean().optional(),
  sensationalismDetection: z.boolean().optional(),
  factHighlights: z.boolean().optional(),
  storyImpact: z.boolean().optional(),
  dailyBriefing: z.boolean().optional(),
  topicTracking: z.boolean().optional(),
  perspectiveSimulator: z.boolean().optional(),
  emergingStoryDetector: z.boolean().optional(),
  historicalComparison: z.boolean().optional(),
  futureScenarioGenerator: z.boolean().optional(),
  localImpactDetector: z.boolean().optional()
});

export const columnFiltersSchema = z.object({
  onlyMatches: z.boolean(),
  onlyResearched: z.boolean(),
  onlySummaries: z.boolean(),
});

export const feedPageCursorSchema = z.object({
  beforePublishedMs: z.number(),
  beforeId: z.string().trim().min(1)
});

export const productFeatureKindSchema = z.union([
  z.literal('saved_story'),
  z.literal('collection'),
  z.literal('alert_rule'),
  z.literal('schedule'),
  z.literal('digest')
]);

export const productFeaturePayloadSchema = z.record(z.unknown()).default({});

export const savedStoryPayloadSchema = z.object({
  itemId: z.string().trim().min(1),
  feedUrl: z.string().trim().min(1),
  title: z.string().trim().min(1),
  link: z.string().trim().optional(),
  source: z.string().trim().optional(),
  coverUrl: z.string().trim().optional(),
  tags: z.array(z.string().trim().min(1)).max(40).default([]),
  note: z.string().trim().max(2000).default(''),
  read: z.boolean().default(false),
  archived: z.boolean().default(false)
});

export const alertRulePayloadSchema = z.object({
  enabled: z.boolean().default(true),
  name: z.string().trim().min(1).max(120),
  keywords: z.array(z.string().trim().min(1).max(80)).max(40).default([]),
  sources: z.array(z.string().trim().min(1).max(160)).max(40).default([]),
  moods: z.array(z.string().trim().min(1).max(40)).max(20).default([]),
  newsTypes: z.array(z.string().trim().min(1).max(40)).max(20).default([]),
  discordWebhookUrl: z.string().trim().max(500).default(''),
  lastCheckedAtMs: z.number().finite().nonnegative().default(0)
});

export const schedulePayloadSchema = z.object({
  enabled: z.boolean().default(true),
  name: z.string().trim().min(1).max(120),
  cadence: z.union([z.literal('hourly'), z.literal('daily'), z.literal('weekly')]).default('daily'),
  time: z.string().trim().max(20).default('08:00'),
  feedUrls: z.array(z.string().trim().min(1)).max(80).default([]),
  format: briefingFormatSchema.default('executive'),
  discordWebhookUrl: z.string().trim().max(500).default(''),
  nextRunAtMs: z.number().finite().nonnegative().default(0),
  lastRunAtMs: z.number().finite().nonnegative().default(0)
});

export const digestPayloadSchema = z.object({
  storyIds: z.array(z.string().trim().min(1)).max(80).default([]),
  feedUrls: z.array(z.string().trim().min(1)).max(80).default([]),
  body: z.string().trim().max(20000).default(''),
  format: briefingFormatSchema.default('executive'),
  discordWebhookUrl: z.string().trim().max(500).default('')
});

export const opmlFeedSchema = z.object({
  title: z.string().trim().min(1),
  xmlUrl: z.string().trim().min(1),
  htmlUrl: z.string().trim().optional()
});

export const shareKindSchema = z.union([
  z.literal('story'),
  z.literal('digest'),
  z.literal('collection')
]);

export const clientMsgSchema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('toggle_ai'), enabled: z.boolean() }),
  z.object({
    type: z.literal('set_ai_provider'),
    provider: aiProviderSchema,
    apiKey: z.string().optional(),
    authToken: z.string().optional()
  }),
  z.object({
    type: z.literal('set_ai_models'),
    summaryModel: aiModelIdSchema.optional(),
    researchModel: aiModelIdSchema.optional(),
    askModel: aiModelIdSchema.optional()
  }),
  z.object({ type: z.literal('set_summary_lang'), lang: summaryLangSchema }),
  z.object({ type: z.literal('set_research_lang'), lang: researchLangSchema }),
  z.object({ type: z.literal('set_title_display_language'), titleDisplayLanguage: z.union([z.literal('original'), z.literal('bg'), z.literal('en')]) }),
  z.object({
    type: z.literal('set_keywords'),
    keywords: z.union([
      z.string(),
      z.array(z.string())
    ])
  }),
  z.object({
    type: z.literal('set_ai_features'),
    features: aiFeatureSettingsSchema.optional(),
    localRegion: z.string().trim().min(1).max(120).optional(),
    trackedTopics: z.array(z.string().trim().min(1).max(120)).max(80).optional(),
    localBaseUrl: z.string().trim().min(1).max(500).optional()
  }),
  z.object({ type: z.literal('add_feed'), url: z.string(), label: z.string().optional(), kind: feedKindSchema.optional(), intervalSec: z.number().optional() }),
  z.object({ type: z.literal('remove_feed'), feedUrl: z.string() }),
  z.object({ type: z.literal('set_feed_summary'), feedUrl: z.string(), enabled: z.boolean() }),
  z.object({ type: z.literal('set_feed_translation'), feedUrl: z.string(), enabled: z.boolean() }),
  z.object({ type: z.literal('set_feed_neutral_titles'), feedUrl: z.string(), enabled: z.boolean() }),
  z.object({ type: z.literal('set_feed_research'), feedUrl: z.string(), enabled: z.boolean() }),
  z.object({ type: z.literal('set_feed_discord_webhook'), feedUrl: z.string(), webhookUrl: z.string() }),
  z.object({ type: z.literal('set_feed_budget'), feedUrl: z.string(), budget: budgetModeSchema }),
  z.object({ type: z.literal('set_all_budget'), budget: budgetModeSchema }),
  z.object({ type: z.literal('set_feed_interval'), feedUrl: z.string(), intervalSec: z.number() }),
  z.object({ type: z.literal('set_feed_column_settings'), feedUrl: z.string(), sortMode: sortModeSchema, filters: columnFiltersSchema }),
  z.object({ type: z.literal('hide_item'), id: z.string() }),
  z.object({ type: z.literal('unhide_item'), id: z.string() }),
  z.object({ type: z.literal('run_research_item'), id: z.string(), feedUrl: z.string() }),
  z.object({ type: z.literal('run_summary_item'), id: z.string(), feedUrl: z.string() }),
  z.object({
    type: z.literal('load_feed_page'),
    feedUrl: z.string(),
    limit: z.number().optional(),
    cursor: feedPageCursorSchema.optional(),
    replace: z.boolean().optional()
  }),
  z.object({
    type: z.literal('run_item_auto'),
    id: z.string(),
    feedUrl: z.string(),
    summary: z.boolean().optional(),
    research: z.boolean().optional(),
    titleTranslate: z.boolean().optional(),
    neutralTitle: z.boolean().optional(),
    mood: z.boolean().optional(),
    newsType: z.boolean().optional()
  }),
  z.object({
    type: z.literal('generate_daily_briefing'),
    delivery: briefingDeliverySchema.optional(),
    email: z.string().trim().max(200).optional(),
    format: briefingFormatSchema.optional(),
    includeAudio: z.boolean().optional(),
    feedUrls: z.array(z.string()).max(80).optional()
  }),
  z.object({ type: z.literal('ask_agent_item'), id: z.string(), feedUrl: z.string(), question: z.string(), researchMode: z.union([z.literal('auto'), z.literal('force'), z.literal('reuse')]).optional() }),
]);

export type ClientMsg = z.infer<typeof clientMsgSchema>;

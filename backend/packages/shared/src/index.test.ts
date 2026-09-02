import { describe, expect, it } from 'vitest';
import {
  alertRulePayloadSchema,
  clientMsgSchema,
  digestPayloadSchema,
  opmlFeedSchema,
  savedStoryPayloadSchema,
  schedulePayloadSchema,
  shareKindSchema
} from './index';

describe('shared clientMsgSchema', () => {
  it('accepts provider switching messages with supported providers', () => {
    const openAi = clientMsgSchema.safeParse({
      type: 'set_ai_provider',
      provider: 'openai',
      apiKey: 'sk-openai'
    });
    const claude = clientMsgSchema.safeParse({
      type: 'set_ai_provider',
      provider: 'claude',
      apiKey: 'sk-ant'
    });
    const openrouter = clientMsgSchema.safeParse({
      type: 'set_ai_provider',
      provider: 'openrouter',
      apiKey: 'sk-or'
    });

    expect(openAi.success).toBe(true);
    expect(claude.success).toBe(true);
    expect(openrouter.success).toBe(true);
  });

  it('accepts provider switching with auth token', () => {
    const result = clientMsgSchema.safeParse({
      type: 'set_ai_provider',
      provider: 'openai',
      authToken: 'token-123'
    });
    expect(result.success).toBe(true);
  });

  it('rejects unsupported provider values', () => {
    const result = clientMsgSchema.safeParse({
      type: 'set_ai_provider',
      provider: 'gemini',
      apiKey: 'x'
    });
    expect(result.success).toBe(false);
  });

  it('accepts ai toggle and language updates', () => {
    expect(clientMsgSchema.safeParse({ type: 'toggle_ai', enabled: true }).success).toBe(true);
    expect(clientMsgSchema.safeParse({ type: 'set_summary_lang', lang: 'bilingual' }).success).toBe(true);
    expect(clientMsgSchema.safeParse({ type: 'set_summary_lang', lang: 'de' }).success).toBe(false);
    expect(clientMsgSchema.safeParse({ type: 'set_research_lang', lang: 'bg' }).success).toBe(true);
    expect(clientMsgSchema.safeParse({ type: 'set_research_lang', lang: 'de' }).success).toBe(false);
    expect(clientMsgSchema.safeParse({ type: 'set_title_display_language', titleDisplayLanguage: 'bg' }).success).toBe(true);
    expect(clientMsgSchema.safeParse({ type: 'set_title_display_language', titleDisplayLanguage: 'de' }).success).toBe(false);
    expect(clientMsgSchema.safeParse({ type: 'set_feed_translation', feedUrl: 'https://feed.example/rss', enabled: false }).success).toBe(true);
    expect(clientMsgSchema.safeParse({ type: 'set_feed_discord_webhook', feedUrl: 'https://feed.example/rss', webhookUrl: 'https://discord.com/api/webhooks/1/abc' }).success).toBe(true);
    expect(clientMsgSchema.safeParse({ type: 'set_keywords', keywords: 'war, energy, budget' }).success).toBe(true);
    expect(clientMsgSchema.safeParse({ type: 'set_keywords', keywords: ['war', 'energy'] }).success).toBe(true);
  });

  it('accepts AI insight feature settings payloads', () => {
    expect(clientMsgSchema.safeParse({
      type: 'set_ai_features',
      features: {
        biasDetection: true,
        sensationalismDetection: true,
        factHighlights: true,
        storyImpact: false
      },
      localRegion: 'Bulgaria',
      trackedTopics: ['AI', 'War in Ukraine']
    }).success).toBe(true);
  });

  it('accepts daily briefing generation payloads', () => {
    expect(clientMsgSchema.safeParse({
      type: 'generate_daily_briefing',
      delivery: 'email',
      email: 'briefing@example.com',
      format: 'bullets',
      includeAudio: true,
      feedUrls: ['https://feed.example/rss']
    }).success).toBe(true);
    expect(clientMsgSchema.safeParse({
      type: 'generate_daily_briefing',
      format: 'weekly'
    }).success).toBe(false);
  });

  it('accepts AI insight feature settings payloads', () => {
    expect(clientMsgSchema.safeParse({
      type: 'set_ai_features',
      features: {
        biasDetection: true,
        sensationalismDetection: true,
        factHighlights: true,
        storyImpact: false
      },
      localRegion: 'Bulgaria',
      trackedTopics: ['AI', 'War in Ukraine']
    }).success).toBe(true);
  });

  it('accepts daily briefing generation payloads', () => {
    expect(clientMsgSchema.safeParse({
      type: 'generate_daily_briefing',
      delivery: 'email',
      email: 'briefing@example.com',
      format: 'bullets',
      includeAudio: true,
      feedUrls: ['https://feed.example/rss']
    }).success).toBe(true);
    expect(clientMsgSchema.safeParse({
      type: 'generate_daily_briefing',
      format: 'weekly'
    }).success).toBe(false);
  });

  it('accepts model update payloads', () => {
    expect(clientMsgSchema.safeParse({
      type: 'set_ai_models',
      summaryModel: 'gpt-4.1-nano'
    }).success).toBe(true);
    expect(clientMsgSchema.safeParse({
      type: 'set_ai_models',
      researchModel: 'gpt-4.1-mini',
      askModel: 'gpt-4.1-nano'
    }).success).toBe(true);
  });

  it('accepts viewport-triggered auto item requests', () => {
    const ok = clientMsgSchema.safeParse({
      type: 'run_item_auto',
      id: 'n1',
      feedUrl: 'https://feed',
      summary: true,
      research: true,
      titleTranslate: true
    });
    const bad = clientMsgSchema.safeParse({
      type: 'run_item_auto',
      id: 'n1',
      feedUrl: 'https://feed'
    });
    expect(ok.success).toBe(true);
    expect(bad.success).toBe(true);
  });

  it('accepts ask-agent research modes and rejects invalid mode', () => {
    const ok = clientMsgSchema.safeParse({
      type: 'ask_agent_item',
      id: 'n1',
      feedUrl: 'https://feed',
      question: 'What happened?',
      researchMode: 'force'
    });
    const bad = clientMsgSchema.safeParse({
      type: 'ask_agent_item',
      id: 'n1',
      feedUrl: 'https://feed',
      question: 'What happened?',
      researchMode: 'always'
    });
    expect(ok.success).toBe(true);
    expect(bad.success).toBe(false);
  });

  it('accepts product feature payloads', () => {
    expect(savedStoryPayloadSchema.safeParse({
      itemId: 'n1',
      feedUrl: 'https://feed.example/rss',
      title: 'Story',
      tags: ['important']
    }).success).toBe(true);
    expect(alertRulePayloadSchema.safeParse({
      name: 'NATO watch',
      keywords: ['NATO', 'Ukraine'],
      discordWebhookUrl: ''
    }).success).toBe(true);
    const sentenceRule = alertRulePayloadSchema.safeParse({
      name: 'Flu vaccines Bulgaria',
      criteria: 'when flu vaccinations will be available to the public in Bulgaria',
      dailyScanTime: '23:55'
    });
    expect(sentenceRule.success).toBe(true);
    expect(sentenceRule.success && sentenceRule.data.criteria).toBe('when flu vaccinations will be available to the public in Bulgaria');
    expect(schedulePayloadSchema.safeParse({
      name: 'Morning brief',
      cadence: 'daily',
      time: '08:00'
    }).success).toBe(true);
    expect(digestPayloadSchema.safeParse({
      storyIds: ['n1'],
      body: 'Digest body'
    }).success).toBe(true);
    expect(opmlFeedSchema.safeParse({
      title: 'Feed',
      xmlUrl: 'https://example.com/rss'
    }).success).toBe(true);
    expect(shareKindSchema.safeParse('digest').success).toBe(true);
  });
});

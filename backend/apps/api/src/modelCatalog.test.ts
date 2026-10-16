import { describe, expect, it } from 'vitest';
import { costLabel, fetchModels, isTextModel, pickDefault, priceKey, resolveChoice, withPrices, type ModelInfo } from './modelCatalog.js';

const day = (n: number) => Date.UTC(2026, 0, 1) + n * 86_400_000;
const model = (id: string, created: number, outputPerM?: number, inputPerM = (outputPerM ?? 0) / 5): ModelInfo =>
  withPrices('openai', [{ id, createdMs: day(created) }], new Map(outputPerM === undefined ? [] : [[priceKey('openai', id), { inputPerM, outputPerM }]]))[0];

describe('model catalog', () => {
  it('keeps text models and drops speech, images, snapshots and pro variants', () => {
    const ids = ['gpt-6-luna', 'gpt-6-luna-pro', 'gpt-4o-realtime', 'gpt-image-2', 'gpt-5.4-nano-2026-03-17', 'gpt-4-0613', 'text-embedding-3-small', 'gpt-5.3-codex', 'o3'];
    expect(ids.filter(id => isTextModel('openai', id))).toEqual(['gpt-6-luna', 'o3']);
    expect(isTextModel('claude', 'claude-haiku-5-5')).toBe(true);
  });

  it('matches Anthropic ids to OpenRouter price keys', () => {
    expect(priceKey('claude', 'claude-haiku-5-5')).toBe('anthropic/claude-haiku-5-5');
    expect(priceKey('claude', 'claude-opus-5-20260101')).toBe('anthropic/claude-opus-5');
    expect(costLabel('openai', 0.1, 0.5)).toBe('$ · $0.10 in / $0.50 out per 1M tokens');
    expect(costLabel('openai', 2, 10)).toBe('$$$ · $2 in / $10 out per 1M tokens');
    expect(costLabel('openai')).toBe('price unknown');
  });

  it('balanced: picks the newest cheap model for summaries and the newest mid-priced one for research', () => {
    const models = [model('flagship', 30, 50), model('mid-new', 29, 10), model('cheap-new', 28, 0.5), model('cheap-old', 1, 0.4), model('mid-old', 2, 8)];
    expect(pickDefault('summary', models, 'balanced')).toBe('cheap-new');
    expect(pickDefault('ask', models, 'balanced')).toBe('cheap-new');
    expect(pickDefault('research', models, 'balanced')).toBe('mid-new');
    expect(pickDefault('summary', [model('a', 1), model('b', 2)], 'balanced')).toBe('b');
  });

  it('by default gives every task the cheapest model of the newest generation', () => {
    const models = [
      model('gpt-6.1-sol', 30, 10), model('gpt-6-astra', 28, 50), model('gpt-6-luna', 27, 0.5),
      model('gpt-5-nano', 1, 0.4), model('gpt-5.6-terra', 20, 12)
    ];
    for (const kind of ['summary', 'research', 'ask'] as const) expect(pickDefault(kind, models)).toBe('gpt-6-luna');
    expect(pickDefault('research', models, 'balanced')).toBe('gpt-6.1-sol');
    // A newer generation takes over once it is listed.
    expect(pickDefault('summary', [...models, model('gpt-7-mini', 40, 3)])).toBe('gpt-7-mini');
  });

  it('keeps a chosen model while it is offered and replaces it when it is removed', () => {
    const models = [model('cheap', 5, 0.5), model('mid', 4, 10)];
    expect(resolveChoice('summary', { model: 'mid', byUser: true }, models)).toEqual({ model: 'mid', byUser: true });
    expect(resolveChoice('summary', { model: 'gone', byUser: true }, models)).toEqual({ model: 'cheap', byUser: false, replaced: 'gone' });
    // An automatic choice moves to the newest default.
    expect(resolveChoice('research', { model: 'old', byUser: false }, models, 'balanced')).toEqual({ model: 'mid', byUser: false });
  });

  it('reads the provider list, newest first', async () => {
    const fetchImpl = async () => ({ ok: true, status: 200, json: async () => ({ data: [
      { id: 'gpt-old', created: 10 }, { id: 'gpt-new', created: 20 }, { id: 'whisper-1', created: 30 }
    ] }) });
    expect((await fetchModels('openai', { apiKey: 'k', fetchImpl })).map(m => m.id)).toEqual(['gpt-new', 'gpt-old']);
    const failing = async () => ({ ok: false, status: 401, json: async () => ({}) });
    await expect(fetchModels('openai', { apiKey: 'bad', fetchImpl: failing })).rejects.toThrow('401');
  });
});

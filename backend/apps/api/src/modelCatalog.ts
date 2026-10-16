// The models each AI provider offers right now, with their prices. Nothing here names a
// model: the lists come from the providers' own model endpoints, prices from OpenRouter's
// public catalogue (which also lists OpenAI and Anthropic models at their own prices), and
// defaults are picked by price and age, so new models show up and retired ones drop out.

export type CatalogProvider = 'openai' | 'claude' | 'openrouter' | 'local';
export type ModelKind = 'summary' | 'research' | 'ask';

export type ModelInfo = {
  id: string;
  createdMs: number;
  /** USD per million input / output tokens, when known. */
  inputPerM?: number;
  outputPerM?: number;
  /** 1 cheap … 4 most expensive, from the output price. */
  costTier?: 1 | 2 | 3 | 4;
  /** Short text for menus, e.g. "$ · $0.10 in / $0.50 out per 1M tokens". */
  costLabel: string;
};

/** `fromEnv`: pinned by an env variable rather than picked in the app. */
export type ModelChoice = { model: string; byUser: boolean; fromEnv?: boolean };

type FetchLike = (url: string, init?: { headers?: Record<string, string>; signal?: AbortSignal }) => Promise<{
  ok: boolean;
  status: number;
  json(): Promise<unknown>;
}>;

// Ids that are not general text models (speech, images, embeddings, coding agents), dated
// snapshots of a model that is listed anyway, and "-pro" variants, which only run through
// background requests. Patterns describe kinds of models, not particular ones.
const NOT_FOR_TEXT = /(audio|realtime|tts|transcribe|whisper|image|dall-e|sora|search|embed|moderation|codex|computer-use|live|instruct|babbage|davinci)/i;
const DATED_SNAPSHOT = /-(\d{4}-?\d{2}-?\d{2}|\d{4})$/;
const PRO_VARIANT = /-pro(-|$)/i;

export function isTextModel(provider: CatalogProvider, id: string): boolean {
  const value = String(id || '').trim();
  if (!value) return false;
  if (provider === 'local') return true;
  if (NOT_FOR_TEXT.test(value) || PRO_VARIANT.test(value) || value.includes(':')) return false;
  if (provider === 'openai') return /^(gpt-|o\d|chatgpt-)/i.test(value) && !DATED_SNAPSHOT.test(value) && !/chat-latest$/i.test(value);
  if (provider === 'claude') return /^claude-/i.test(value);
  return true;
}

/** "anthropic/claude-haiku-5.5" and Anthropic's "claude-haiku-5-5" give the same key. */
export function priceKey(provider: CatalogProvider, id: string): string {
  const prefix = provider === 'openai' ? 'openai/' : provider === 'claude' ? 'anthropic/' : '';
  const bare = String(id || '').trim().toLowerCase().replace(/-\d{8}$/, '');
  return `${prefix}${bare}`.replace(/\./g, '-');
}

export function costTier(outputPerM?: number): ModelInfo['costTier'] {
  if (outputPerM === undefined || !Number.isFinite(outputPerM)) return undefined;
  if (outputPerM <= 1) return 1;
  if (outputPerM <= 5) return 2;
  if (outputPerM <= 20) return 3;
  return 4;
}

function money(value: number): string {
  if (value === 0) return '$0';
  return value < 1 ? `$${value.toFixed(2)}` : `$${Number(value.toFixed(2))}`;
}

export function costLabel(provider: CatalogProvider, inputPerM?: number, outputPerM?: number): string {
  if (provider === 'local') return 'local · no cost';
  if (inputPerM === undefined || outputPerM === undefined) return 'price unknown';
  if (inputPerM === 0 && outputPerM === 0) return 'free';
  const tier = '$'.repeat(costTier(outputPerM) || 1);
  return `${tier} · ${money(inputPerM)} in / ${money(outputPerM)} out per 1M tokens`;
}

export function withPrices(provider: CatalogProvider, models: Array<{ id: string; createdMs: number }>, prices: Map<string, { inputPerM: number; outputPerM: number }>): ModelInfo[] {
  return models.map(model => {
    const price = provider === 'local' ? undefined : prices.get(priceKey(provider, model.id));
    return {
      id: model.id,
      createdMs: model.createdMs,
      inputPerM: price?.inputPerM,
      outputPerM: price?.outputPerM,
      costTier: costTier(price?.outputPerM),
      costLabel: costLabel(provider, price?.inputPerM, price?.outputPerM)
    };
  });
}

const newestFirst = (a: ModelInfo, b: ModelInfo) => b.createdMs - a.createdMs || a.id.length - b.id.length || a.id.localeCompare(b.id);

/**
 * Summaries and quick questions run on every story, so they get the newest cheap model
 * (at most $1 per million output tokens). Research and briefings get the newest mid-priced
 * one (up to $15), not the most expensive flagship. Without prices: the newest model.
 */
export function pickDefault(kind: ModelKind, models: ModelInfo[]): string | undefined {
  const sorted = [...models].sort(newestFirst);
  const priced = sorted.filter(model => model.outputPerM !== undefined);
  if (!priced.length) return sorted[0]?.id;
  const out = (model: ModelInfo) => model.outputPerM as number;
  const pick = kind === 'research'
    ? priced.find(model => out(model) > 1 && out(model) <= 15)
    : priced.find(model => out(model) <= 1);
  if (pick) return pick.id;
  // Nothing in that price band: the cheapest (or for research the dearest) of the newest few.
  const recent = priced.slice(0, 6).sort((a, b) => (kind === 'research' ? out(b) - out(a) : out(a) - out(b)));
  return recent[0]?.id;
}

/**
 * Keeps a model the user chose while the provider still offers it. When it is gone, or
 * the choice was automatic, the default for that kind takes over; `replaced` says what
 * was dropped so the user can be told.
 */
export function resolveChoice(kind: ModelKind, current: ModelChoice | undefined, models: ModelInfo[]): ModelChoice & { replaced?: string } {
  const offered = new Set(models.map(model => model.id));
  if (current?.model && current.byUser && offered.has(current.model)) return current;
  const fallback = pickDefault(kind, models) || current?.model || '';
  if (current?.byUser && current.model && !offered.has(current.model)) {
    return { model: fallback, byUser: false, replaced: current.model };
  }
  return { model: fallback, byUser: false };
}

async function getJson(fetchImpl: FetchLike, url: string, headers: Record<string, string> = {}): Promise<unknown> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 15_000);
  try {
    const res = await fetchImpl(url, { headers, signal: controller.signal });
    if (!res.ok) throw new Error(`${url} answered ${res.status}`);
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}

/** OpenRouter's public catalogue: USD per million tokens by price key. No key needed. */
export async function fetchPrices(fetchImpl: FetchLike = fetch as unknown as FetchLike): Promise<Map<string, { inputPerM: number; outputPerM: number }>> {
  const body = await getJson(fetchImpl, 'https://openrouter.ai/api/v1/models') as { data?: Array<{ id?: string; pricing?: { prompt?: string; completion?: string } }> };
  const prices = new Map<string, { inputPerM: number; outputPerM: number }>();
  for (const model of body?.data || []) {
    const id = String(model?.id || '');
    const input = Number(model?.pricing?.prompt);
    const output = Number(model?.pricing?.completion);
    if (!id || id.includes(':') || !Number.isFinite(input) || !Number.isFinite(output) || input < 0 || output < 0) continue;
    prices.set(id.toLowerCase().replace(/\./g, '-'), { inputPerM: input * 1e6, outputPerM: output * 1e6 });
  }
  return prices;
}

/** The provider's own list of models for this key, text models only, newest first. */
export async function fetchModels(
  provider: CatalogProvider,
  options: { apiKey?: string; localBaseUrl?: string; fetchImpl?: FetchLike }
): Promise<Array<{ id: string; createdMs: number }>> {
  const fetchImpl = options.fetchImpl || (fetch as unknown as FetchLike);
  let rows: Array<{ id: string; createdMs: number }> = [];
  if (provider === 'openai') {
    const body = await getJson(fetchImpl, 'https://api.openai.com/v1/models', { Authorization: `Bearer ${options.apiKey || ''}` }) as { data?: Array<{ id?: string; created?: number }> };
    rows = (body?.data || []).map(model => ({ id: String(model?.id || ''), createdMs: Number(model?.created || 0) * 1000 }));
  } else if (provider === 'claude') {
    const body = await getJson(fetchImpl, 'https://api.anthropic.com/v1/models?limit=1000', {
      'x-api-key': options.apiKey || '',
      'anthropic-version': '2023-06-01'
    }) as { data?: Array<{ id?: string; created_at?: string }> };
    rows = (body?.data || []).map(model => ({ id: String(model?.id || ''), createdMs: Date.parse(String(model?.created_at || '')) || 0 }));
  } else if (provider === 'openrouter') {
    const body = await getJson(fetchImpl, 'https://openrouter.ai/api/v1/models') as {
      data?: Array<{ id?: string; created?: number; architecture?: { output_modalities?: string[] } }>;
    };
    rows = (body?.data || [])
      .filter(model => !model?.architecture?.output_modalities || model.architecture.output_modalities.includes('text'))
      .map(model => ({ id: String(model?.id || ''), createdMs: Number(model?.created || 0) * 1000 }));
  } else {
    const base = String(options.localBaseUrl || '').trim().replace(/\/+$/, '');
    if (!base) return [];
    const body = await getJson(fetchImpl, `${base}/models`) as { data?: Array<{ id?: string; created?: number }> };
    rows = (body?.data || []).map(model => ({ id: String(model?.id || ''), createdMs: Number(model?.created || 0) * 1000 }));
  }
  const seen = new Set<string>();
  const models = rows
    .filter(row => isTextModel(provider, row.id) && !seen.has(row.id) && seen.add(row.id))
    .sort((a, b) => b.createdMs - a.createdMs);
  // OpenRouter lists hundreds of models; the newest are the ones worth offering.
  return provider === 'openrouter' ? models.slice(0, 120) : models;
}

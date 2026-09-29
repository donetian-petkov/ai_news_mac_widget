/**
 * Caches the set of significant words (longer than 3 characters) in each
 * story's title, so comparing one story against every other recent story does
 * not re-split every title each time. An entry is rebuilt when the title text
 * changes, and dropped automatically when the story object goes away.
 */
export function createTitleTokenCache(normalize: (text: string) => string) {
  const cache = new WeakMap<object, { title: string; tokens: Set<string> }>();
  return function tokensFor(item: { title: string }): Set<string> {
    const cached = cache.get(item);
    if (cached && cached.title === item.title) return cached.tokens;
    const tokens = new Set(normalize(item.title).split(/\s+/g).filter(token => token.length > 3));
    cache.set(item, { title: item.title, tokens });
    return tokens;
  };
}

const sharedCaches = new WeakMap<(text: string) => string, (item: { title: string }) => Set<string>>();

/**
 * Module-level cache per normalizer. Safe to call from anywhere in server.ts,
 * including code that runs before server.ts's own top-level constants exist.
 */
export function titleTokens(item: { title: string }, normalize: (text: string) => string): Set<string> {
  let tokensFor = sharedCaches.get(normalize);
  if (!tokensFor) {
    tokensFor = createTitleTokenCache(normalize);
    sharedCaches.set(normalize, tokensFor);
  }
  return tokensFor(item);
}

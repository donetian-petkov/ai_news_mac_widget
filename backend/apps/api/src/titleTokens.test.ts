import { describe, expect, it } from 'vitest';
import { createTitleTokenCache } from './titleTokens.js';

describe('createTitleTokenCache', () => {
  it('tokenises once per title and rebuilds when the title changes', () => {
    let calls = 0;
    const tokensFor = createTitleTokenCache(text => {
      calls += 1;
      return text.toLowerCase();
    });
    const item = { title: 'Big Storm Hits Coast Today' };
    const first = tokensFor(item);
    expect(Array.from(first)).toEqual(['storm', 'hits', 'coast', 'today']);
    expect(tokensFor(item)).toBe(first);
    expect(calls).toBe(1);

    item.title = 'Storm Moves Inland';
    expect(Array.from(tokensFor(item))).toEqual(['storm', 'moves', 'inland']);
    expect(calls).toBe(2);
  });

  it('keeps separate entries per story object', () => {
    const tokensFor = createTitleTokenCache(text => text);
    expect(tokensFor({ title: 'alpha beta' })).not.toBe(tokensFor({ title: 'alpha beta' }));
  });
});

describe('titleTokens', () => {
  it('reuses the cached set for the same normalizer', async () => {
    const { titleTokens } = await import('./titleTokens.js');
    const normalize = (text: string) => text.toLowerCase();
    const item = { title: 'Alpha Bravo Charlie' };
    const first = titleTokens(item, normalize);
    expect(titleTokens(item, normalize)).toBe(first);
    expect(Array.from(first)).toEqual(['alpha', 'bravo', 'charlie']);
  });
});

import { describe, expect, it } from 'vitest';
import { contextWithFullTitle, headlineFromFeedTitle, MAX_HEADLINE_CHARS } from './feedTitle';

const filler = (n: number) => Array.from({ length: n }, (_, i) => `дума${i}`).join(' ');

describe('headlineFromFeedTitle', () => {
  it('keeps real headlines, long ones too', () => {
    const long = 'Camera-Shy Chrissie Hynde on Finally Allowing a Definitive Doc to Be Made About ‘The Pretenders,’ Bowing in Toronto: ‘I Just Wanted to Be in a Band. I’ve Never Graduated Beyond That Initial Interest in It’';
    expect(headlineFromFeedTitle(long)).toEqual({ title: long, fullText: '' });
    expect(headlineFromFeedTitle('  Short   headline ')).toEqual({ title: 'Short headline', fullText: '' });
  });

  it('cuts a title that is a whole article to its first sentence and keeps the full text', () => {
    const raw = `Първото изречение е заглавието.<br />${filler(80)}. Още едно изречение. <br />`;
    const result = headlineFromFeedTitle(raw);
    expect(result.title).toBe('Първото изречение е заглавието.');
    expect(result.fullText).toContain('Още едно изречение.');
    expect(result.fullText).not.toContain('<br');
  });

  it('cuts at a word when the first sentence is itself too long', () => {
    const result = headlineFromFeedTitle(`${filler(100)}. Край.`);
    expect(result.title.length).toBeLessThanOrEqual(MAX_HEADLINE_CHARS);
    expect(result.title.endsWith('…')).toBe(true);
    expect(result.title).not.toMatch(/\s…$/);
  });
});

describe('contextWithFullTitle', () => {
  it('puts the full title text in front of the context once', () => {
    expect(contextWithFullTitle('', 'ctx')).toBe('ctx');
    expect(contextWithFullTitle('Full text.', 'ctx')).toBe('Full text.\n\nctx');
    expect(contextWithFullTitle('Full text.', undefined)).toBe('Full text.');
    expect(contextWithFullTitle('Full text.', 'Full text.\n\nctx')).toBe('Full text.\n\nctx');
  });
});

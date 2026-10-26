// Some feeds put a whole article, or a whole newsletter, in the item's title. Every screen
// shows the title as the headline, so a title longer than any real headline is cut to its
// first sentence, and the full text is kept as context for the summary and the briefing.

// Real headlines reach about 210 characters (long entertainment headlines with a quote).
export const MAX_HEADLINE_CHARS = 240;
const SENTENCE_END = /[.!?…]["“”»)]?(?=\s|$)/g;

function plain(text: string): string {
  return String(text || '')
    .replace(/<[^>]*>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** The headline to show, and the full text when the title had to be cut ('' otherwise). */
export function headlineFromFeedTitle(raw: string): { title: string; fullText: string } {
  const original = String(raw || '').replace(/\s+/g, ' ').trim();
  if (original.length <= MAX_HEADLINE_CHARS) return { title: original, fullText: '' };
  const text = plain(original);
  if (text.length <= MAX_HEADLINE_CHARS) return { title: text, fullText: '' };
  const firstEnd = Array.from(text.matchAll(SENTENCE_END))
    .map(match => (match.index ?? 0) + match[0].length)
    .find(end => end >= 20);
  if (firstEnd && firstEnd <= MAX_HEADLINE_CHARS) return { title: text.slice(0, firstEnd).trim(), fullText: text };
  const cut = text.slice(0, MAX_HEADLINE_CHARS - 1);
  const space = cut.lastIndexOf(' ');
  return { title: `${(space > 40 ? cut.slice(0, space) : cut).replace(/[\s,;:–—-]+$/, '')}…`, fullText: text };
}

/** Context with the full title text in front, unless the context already starts with it. */
export function contextWithFullTitle(fullText: string, context: string | undefined): string | undefined {
  if (!fullText) return context;
  const rest = String(context || '').trim();
  if (rest && plain(rest).startsWith(fullText.slice(0, 120))) return rest;
  return rest ? `${fullText}\n\n${rest}` : fullText;
}

// Story summaries are asked for as one short sentence, but models do not always comply:
// some write two or three sentences, some run out of room mid-word, some write a sentence
// explaining that there is nothing to add and then the NO_SUMMARY marker. Every summary
// goes through here before it is stored, so the widget, the briefings and the apps that
// read it all get the same clean text.

const SENTENCE_END = /[.!?…]["“”»)]?(?=\s|$)/g;
// The prompt asks for at most 22 words.
const MAX_WORDS = 22;

function words(text: string): number {
  return text.split(/\s+/).filter(Boolean).length;
}

/**
 * Text cut off mid-sentence keeps only its whole sentences; line breaks become spaces.
 * A single sentence without a final full stop is left as it is.
 */
export function wholeSentences(text: string): string {
  const flat = String(text || '').replace(/\s+/g, ' ').trim();
  if (!flat || /[.!?…"“”»)]$/.test(flat)) return flat;
  const end = Math.max(...['.', '!', '?', '…'].map(mark => flat.lastIndexOf(mark)));
  return end > 0 ? flat.slice(0, end + 1) : flat;
}

/** The first sentence, plus the next ones while the whole stays within MAX_WORDS. */
function shortSummary(text: string): string {
  const whole = wholeSentences(text);
  const ends = Array.from(whole.matchAll(SENTENCE_END)).map(match => (match.index ?? 0) + match[0].length);
  if (ends.length <= 1) return whole;
  let keep = ends[0];
  for (const end of ends.slice(1)) {
    if (words(whole.slice(0, end)) > MAX_WORDS) break;
    keep = end;
  }
  return whole.slice(0, keep).trim();
}

/**
 * A clean summary, or '' when the model said it had nothing to add. Bilingual summaries
 * ("Bulgarian / English") are cleaned part by part.
 */
export function cleanSummary(raw: string): string {
  const text = String(raw || '').trim();
  if (!text || /NO_SUMMARY/i.test(text)) return '';
  const parts = text.split(/\s\/\s/).map(part => shortSummary(part)).filter(Boolean);
  return parts.join(' / ');
}

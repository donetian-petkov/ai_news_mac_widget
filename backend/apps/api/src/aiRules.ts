// Rules every local-model call starts with, whichever local model is loaded. generateAiText puts them before
// the task's own prompt when the provider is local; the local-model test kit reads the same text.
export const AI_RULES = [
  'Rules for every answer:',
  '- Use only the text you are given. Never invent facts, people, sources, outlets, quotes, dates, numbers, places or events.',
  '- Never say what other media, sources or experts report unless their reports are in the text you are given.',
  '- Keep the text\'s own certainty. "May", "alleged", "according to", "може да", "според" and "твърди" stay. A guess or a claim is never written as a fact.',
  '- Keep every statement with the person who made it.',
  '- If the text does not say something, do not fill the gap. Say it is not stated, or leave it out.',
  '- If you need more information to answer, say what is missing.',
  '- If you do not know, say you do not know.',
  '- If you cannot decide (a mood, a type, a label, a comparison), say it is unclear. Never pick one at random.',
  '- If you cannot confirm something from the text, say it is not confirmed.'
].join('\n');

/** The task prompt with the rules loaded first. */
export function withAiRules(input: string): string {
  return `${AI_RULES}\n\n${input}`;
}

import { describe, expect, it } from 'vitest';
import { AI_RULES, withAiRules } from './aiRules';

describe('withAiRules', () => {
  it('puts the no-invention rules before the task prompt', () => {
    const prompt = withAiRules('Summarise this story.');
    expect(prompt.startsWith(AI_RULES)).toBe(true);
    expect(prompt.endsWith('Summarise this story.')).toBe(true);
  });

  it('tells the model to say when it does not know, cannot decide or cannot confirm', () => {
    expect(AI_RULES).toMatch(/do not know/);
    expect(AI_RULES).toMatch(/cannot decide/);
    expect(AI_RULES).toMatch(/cannot confirm/);
    expect(AI_RULES).toMatch(/Never invent/);
  });
});

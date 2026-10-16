import { describe, expect, it } from 'vitest';
import { cleanSummary, wholeSentences } from './summaryText.js';

describe('cleanSummary', () => {
  it('drops a sentence the model cut off and joins its lines', () => {
    expect(cleanSummary('Полицията задържа 21-годишен мъж.  \nРазследването продължава.  \n\nЗадържаният е бил'))
      .toBe('Полицията задържа 21-годишен мъж. Разследването продължава.');
  });

  it('keeps one sentence, and the next only while the whole stays short', () => {
    const first = 'Сушата съсипва поминъка в афганистанската провинция Бадгис и семействата продават дъщерите си, за да погасят дълговете.';
    expect(cleanSummary(`${first} Хатира е сгодена на 11 години. Тя е бременна на 14.`)).toBe(`${first} Хатира е сгодена на 11 години.`);
    expect(cleanSummary(`${first} ${first}`)).toBe(first);
    expect(cleanSummary('Летищата в Рим затвориха. Полетите са отменени.')).toBe('Летищата в Рим затвориха. Полетите са отменени.');
  });

  it('treats any mention of NO_SUMMARY as no summary', () => {
    expect(cleanSummary('Няма наличен допълнителен факт в контекста. NO_SUMMARY')).toBe('');
    expect(cleanSummary('NO_SUMMARY.')).toBe('');
  });

  it('cleans each half of a bilingual summary', () => {
    expect(cleanSummary('Летищата затвориха. Полетите / Airports closed. Flights were'))
      .toBe('Летищата затвориха. / Airports closed.');
  });

  it('leaves a single sentence without a full stop alone', () => {
    expect(wholeSentences('Радев призова ЕС да засили охраната')).toBe('Радев призова ЕС да засили охраната');
  });
});

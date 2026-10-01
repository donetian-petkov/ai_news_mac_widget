# Features

The full feature list for AI News macOS Floating Widgets. The README only keeps the highlights.

## Account And Feeds

- Local account login and local provider-key storage.
- Default feeds imported from the AI News project.
- Per-feed controls from the main page: turn feed fetching off/on and pause/resume AI.
- Filtered Feed as its own first-class feed driven by keyword rules.
- Fast keyword matching for filtered stories before slower semantic work finishes.
- Sidebar health indicators showing loaded, pending, budget-blocked, hidden, and active feed state.
- Hidden categories are presentation-level visibility; use feed controls to stop fetching or pause AI.

## AI

- AI actions for summaries, research, translations, neutral title rewrites, model/provider settings, usage totals, and budget/pending counts.
- Optional neutral-title filter for English and Bulgarian headlines, with global, per-feed, and per-category controls plus an on-demand story action.

## Stories

- Story cards with images, summaries, research state, translation state, share action, save/pin actions, and source links.
- Images are supported in the management app and floating widgets when enabled.

## Floating Widgets

- Individual feed widgets, a filtered feed widget, and merged feed widgets.
- Column view and stack view.
- Solid, transparent and macOS background modes. The macOS mode uses the same frosted glass as the system desktop widgets (macOS 26 or later), so the widget and its text take on the colours of the wallpaper behind it.
- Always-on-top behavior.
- Per-widget size and position persistence.
- Share button on each story.
- NEW label for unseen stack stories.
- Stack navigation and stack load-more controls.
- Drag-over merging for feed widgets, with title-chip unmerge.
- Saved Views page for saving, applying, editing, deleting, and rearranging widget layouts.
- Menu bar icon with quick app/widget actions.

## AI Budget Plan

Neutral title rewriting is one extra AI request for each story that gets rewritten. The current prompt sends the source, original title, optional Bulgarian/English titles, summary, and RSS context, then asks for strict JSON. Budget estimate:

- About `250` AI tokens per neutralized story.
- About `2.5k` tokens for 10 stories.
- About `25k` tokens for 100 stories.
- About `250k` tokens for 1,000 stories.

Budget behavior:

- `Low` - neutral titles are manual only.
- `Standard` - neutral titles run for visible/on-demand stories only.
- `High` - neutral titles also run in the background for newly fetched stories and backfills.

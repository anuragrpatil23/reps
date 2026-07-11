# Reps Design Direction — "The Ledger"

Reps is a **training journal, not a fitness dashboard**. The design thesis comes straight from the journey map: three years of effort failed for lack of *consistent daily record-keeping*, not lack of intensity. So the app should feel like a beautiful ledger you're proud to keep — calm, ink-on-paper, data-quiet — and pointedly unlike the black-and-neon, streak-shaming genre.

## Palette

Light-first. One accent, spent deliberately.

| Token      | Hex       | Role |
|------------|-----------|------|
| `paper`    | `#FAFAF7` | Background — warm-neutral off-white (not cream) |
| `ink`      | `#1C1B18` | Primary text, filled spine ticks |
| `graphite` | `#6E6B63` | Secondary text; hairlines at 35% opacity |
| `chalk`    | `#EFEEE9` | Card fill, inset surfaces |
| `madder`   | `#8C3A2E` | The only color: today's spine tick, PR moments, record affordances |

Discipline rule: **madder never decorates.** It marks *now* and *personal records*, nothing else. "Done" is encoded by ink weight, not color.

Dark mode later: ink and paper invert to warm graphite-black `#161511` / bone `#E8E6DF`; madder brightens one step. Not in v1.

## Typography

All native (nothing shipped, nothing licensed):

- **New York (serif)** — display only: the date masthead and the big weight numeral. Light weight at large sizes; tabular figures.
- **SF Pro** — all body/UI text. Sentence case everywhere.
- **SF Mono** — set data (`8 × 95`), deltas, timestamps. The ledger's column voice.

The serif numeral is the elegance carrier; the mono set-notation is the "journal kept by an engineer" texture.

## Signature: the Spine

A horizontal strip of day ticks along the bottom of the Today page — part measuring tape, part ledger edge. It is also the primary navigation: scrub it to flip between day pages.

Tick encoding (structure *is* information — this is the consistency record made ambient):

- **Full-height ink stroke** — trained that day
- **Mid-height stroke** — logged something (food/weight) but no workout
- **Faint dot** — empty day
- **Madder stroke** — today

Months are marked by a slightly longer baseline tick with a tiny mono label. A year of consistency should be *visible at a glance* as ink density.

## Today page layout

```
  THU · JULY 11                    ← eyebrow: SF Pro caps, graphite
  138.2                            ← New York light, huge
     lbs  ▾ 0.4 this week          ← mono, graphite

  Move 520 · Exercise 42m · Stand 11   ← one quiet line, hairline arcs

  ┌─ Push A ──────────── 18:05 ─┐  ← chalk card, prefilled from last time
  │ Bench press   8×95 8×95 6×100
  │ Lat pulldown  10×115 10×115 │
  │ Incline walk  20m @ 12%     │
  └──── [ Log it — edit deltas ]┘

  Food ····························  ← ledger lines: time · text
  08:30  oats + Oikos + blueberries

  Pics  [front] [side] [ + ]

  ═╷╷·╷╷╷·╷╷█╷═                    ← the Spine (madder = today)
```

Activity rings are deliberately *not* Apple's thick rings — thin hairline arcs beside the numbers, graphite, filled only when a ring closes. Quiet.

## Motion

Two moments only, both honoring Reduce Motion:

1. **Day flip** — scrubbing the spine crossfades the page with a slight vertical settle; the weight numeral counts to its value.
2. **Tick growth** — completing a log draws the day's spine tick upward once. That's the reward. No confetti, no streaks, no badges.

## Copy voice

Plain verbs, sentence case, first-person-adjacent calm. "Log it," not "Crush it." Empty day page reads: "Nothing logged yet." A skipped workout is a fact, not a failure state — never red, never nagging.

## Anti-default check

- Not the black + acid-green fitness genre; not an Apple Fitness clone (rings demoted to a hairline row).
- Not the cream/serif/terracotta template: paper is cooler and quieter, the serif is native New York used only at two sizes, and madder is a plate-red mark, not a decorative accent.
- The one aesthetic risk: navigation *is* the consistency chart (the Spine). It's unusual, but it makes the app's entire reason for existing visible on every open.

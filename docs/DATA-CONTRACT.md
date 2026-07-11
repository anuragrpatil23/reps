# Reps Data Contract

The contract between the Reps app, the vault, and the AI trainer. Everything else (Swift models, cache DB, charts, AI-trainer prompts) derives from this file. Change it deliberately and bump `schema_version`.

## 1. Data home

All app data lives in the Obsidian iCloud vault under:

```
Long-Term-Memory-iCloud/lifeblood_systems/Understanding Myself/Body/
├── sffit/
│   ├── log/
│   │   └── 2026/
│   │       ├── 2026-07-11.md          ← one daily log per day (THE core file)
│   │       └── ...
│   ├── templates/
│   │   ├── push-a.md                  ← workout templates (sticky defaults)
│   │   └── ...
│   ├── progress-pics/
│   │   └── 2026-07/
│   │       ├── 2026-07-11_front.jpg
│   │       └── 2026-07-11_side.jpg
│   ├── routine/                       ← existing yearly prose (untouched)
│   ├── AI body trainer/               ← existing Claude workspace (reads logs)
│   └── ...
└── sffood/                            ← existing recipe notes (read + link only)
```

Rules:
- The app **owns** `log/`, `templates/`, `progress-pics/` — it is the *sole writer* there.
- The app **never writes** anywhere else in the vault (`sffood/`, `routine/`, `AI body trainer/` are read-only to it).
- Hierarchy is by date-named files, not YAML `parent` links — logs are leaf data, not organizer nodes.

## 2. Daily log file

Path: `sffit/log/YYYY/YYYY-MM-DD.md`. One file per calendar day, created on first log event of the day. Frontmatter is the machine-readable record; the markdown body is optional free prose.

```markdown
---
schema_version: 1
type: sffit-daily-log
uuid: "generated-uuid-v4"
date: 2026-07-11
source: reps-app
created_at: 2026-07-11T07:42:00-05:00
updated_at: 2026-07-11T21:10:00-05:00

# ── Body metrics (from HealthKit; FitDays scale syncs into Apple Health) ──
metrics:
  weight_lbs: 138.2
  body_fat_pct: 24.1          # omit keys with no sample that day
  lean_mass_lbs: 99.7
  measured_at: 2026-07-11T07:30:00-05:00

# ── Apple Activity (from HealthKit, written at end of day or on app open next morning) ──
activity:
  move_kcal: 520
  exercise_min: 42
  stand_hours: 11
  steps: 8934

# ── Workout ──
workout:
  status: done                # done | partial | skipped | rest
  template: push-a            # template key, or omit for freeform
  started_at: 2026-07-11T18:05:00-05:00
  duration_min: 55
  exercises:
    - name: Bench Press
      sets:
        - { reps: 8, weight_lbs: 95 }
        - { reps: 8, weight_lbs: 95 }
        - { reps: 6, weight_lbs: 100 }
    - name: Lat Pulldown
      sets:
        - { reps: 10, weight_lbs: 115 }
        - { reps: 10, weight_lbs: 115 }
    - name: Incline Walk
      duration_min: 20        # cardio entries use duration instead of sets
      incline_pct: 12
      speed_mph: 3.0

# ── Food (dumb-simple v1: text, photo, or recipe link — no macros in-app) ──
food:
  - at: "08:30"
    text: "oats + Oikos yogurt + blueberries"
  - at: "13:00"
    recipe: "sffood/Korean/main dishes/Kimchi Rice.md"   # vault-relative from Body/
    text: "half portion"
  - at: "19:30"
    photo: "sffit/progress-pics/2026-07/2026-07-11_dinner.jpg"

# ── Progress pics (vault-relative from Body/) ──
pics:
  - path: "sffit/progress-pics/2026-07/2026-07-11_front.jpg"
    pose: front               # front | side | back | other
  - path: "sffit/progress-pics/2026-07/2026-07-11_side.jpg"
    pose: side
---

Felt strong on bench. Right wrist slightly tender on last set — watch it.
```

Conventions:
- **Units are fixed:** `weight_lbs`, `body_fat_pct`, `duration_min`, `move_kcal`. Unit lives in the key name; no per-file unit fields.
- **Omit, don't null.** A key with no data that day is absent, not `null`/`0`.
- **Times are ISO-8601 with offset** for timestamps; bare `"HH:MM"` local time is allowed only in `food[].at`.
- **Paths are vault-relative from `Body/`** so links survive vault moves and work as Obsidian links.
- **Exercise `name` is the identity key** across days (used for sticky defaults and progress charts). Keep names stable; renames are a manual migration.

## 3. Workout templates

Path: `sffit/templates/<key>.md`. A template defines a workout's exercise list and *baseline* sets. Sticky defaults resolve as: **last completed log entry for this template → falls back to template baseline**.

```markdown
---
schema_version: 1
type: sffit-workout-template
key: push-a                   # stable id referenced by daily logs
title: Push A
days: [mon, thu]              # optional scheduling hint
exercises:
  - name: Bench Press
    sets: [ { reps: 8, weight_lbs: 95 }, { reps: 8, weight_lbs: 95 }, { reps: 6, weight_lbs: 100 } ]
  - name: Lat Pulldown
    sets: [ { reps: 10, weight_lbs: 115 }, { reps: 10, weight_lbs: 115 } ]
  - name: Incline Walk
    duration_min: 20
    incline_pct: 12
    speed_mph: 3.0
---

Notes on form cues, substitutions, etc.
```

## 4. Progress pics

- Path: `sffit/progress-pics/YYYY-MM/YYYY-MM-DD_<pose>.jpg` (add `_2`, `_3` for same-day duplicates).
- The photo file plus its `pics[]` entry in that day's log are written together.
- HEIC converted to JPEG (quality ~0.85) at write time so the vault stays universally readable.

## 5. Write rules (iCloud safety)

1. **Local-first:** every log event commits to the app's local cache DB immediately; vault flush is async and retried. Gym logging never blocks on iCloud.
2. **Atomic file writes:** write to a temp file, then rename over the target. Never partial writes.
3. **Read-merge-write within the day:** before flushing, re-read the day file and merge (the app is the only writer, so this only defends against its own multi-device future).
4. **Never destructive:** the app never deletes or rewrites past days except through an explicit user edit of that day.

## 6. Cache rules

- The local DB (SwiftData/GRDB) is an **index only**: parsed logs, template state, chart aggregates.
- Invariant: delete the DB, rescan `Body/sffit/`, and the app is fully restored. Any feature that would break this invariant is rejected.
- HealthKit is likewise re-queryable; nothing HealthKit-derived is authoritative in the DB.

## 7. Schema evolution

- `schema_version` is per-file. The app reads all versions it knows, writes only the newest.
- Additive changes (new optional keys) don't bump the version. Renames/semantic changes do, with a migration note appended to this doc.

## Version history

- **v1** (2026-07-11): initial contract — daily log, templates, pics, food-as-text/link.

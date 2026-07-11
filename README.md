# Reps

Companion iOS app for the sffit daily loop — log workouts, weight, food, and progress pics with near-zero friction, storing everything as markdown + YAML in the Long-Term-Memory vault.

## Why

Three years of fitness attempts, same weight band. The diagnosis (per the sffit journey map) is a body-composition problem whose missing ingredient was consistent daily data. Reps closes that gap: the daily log becomes structured raw material for the AI trainer living in the vault.

## Core principles

1. **Vault is the source of truth.** Every log materializes as a markdown file with YAML frontmatter under `lifeblood_systems/Understanding Myself/Body/` in the Obsidian iCloud vault. The app's local database is a rebuildable cache, never canonical — the app must always be able to delete its DB and rebuild from the folder.
2. **Sticky defaults.** Workouts hardly change day to day. Open app → today pre-filled from last time → edit deltas → done in seconds.
3. **One integration surface: HealthKit.** Apple Activity rings and FitDays scale data (synced to Apple Health) are both read via HealthKit. No third-party APIs.
4. **Append-mostly, one file per day.** The app is the sole writer of its own log files, keeping the iCloud conflict surface near zero. Writes land locally first and flush to the vault opportunistically — gym logging never blocks on iCloud sync.
5. **Dumb food logging first.** v1 food entries are free text, a photo, or a link to an existing `sffood/` recipe note. Macro parsing is the AI trainer's job, later.

## v1 scope

- Workout log with sticky defaults (edit reps/weight deltas only)
- Weight + body-comp pull from HealthKit (FitDays scale)
- Apple Activity ring pull from HealthKit
- Progress pic camera → `sffit/progress-pics/YYYY-MM/`
- Simple food entries (text / photo / sffood link)

## Data home

`.../Long-Term-Memory-iCloud/lifeblood_systems/Understanding Myself/Body/`
- `sffit/log/YYYY/YYYY-MM-DD.md` — daily log (workout, food, metrics)
- `sffit/progress-pics/YYYY-MM/` — progress photos
- `sffood/` — existing recipe knowledge base (read + link)

## Stack

Swift / SwiftUI, HealthKit, security-scoped bookmark to the vault folder. Local cache DB (SwiftData or GRDB — TBD) as index only.

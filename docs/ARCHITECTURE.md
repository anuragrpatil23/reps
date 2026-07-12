# Reps Architecture

Reps is a native SwiftUI iOS app. It borrows the **lego-blocks + orchestrators**
split from the Thinking Space project (`CLAUDE.md`) for readability, adapted to
Swift idioms (plain `struct`/`enum`/`class`, no `*Block`/`*Orch` type-name
suffixes — the folder communicates the role).

## Layers

```
Reps/
  RepsApp.swift                     app entry
  Models/                           plain data types (shared kernel)
    DailyLog, WorkoutTemplate, Trends
  services/                         logic + IO
    lego_blocks/
      units/                        pure / leaf primitives
        DailyLogCodec   markdown+YAML (de)serialization
        TelemetryCsv    body-composition.csv / activity.csv codec
        ProgressImage   downscale + JPEG compression
      integrations/                 composite reusable services (do IO, compose units)
        VaultStore      security-scoped folder access, file/CSV read+write
        HealthKitService weight + activity queries
    orchestrators/
      LogStore          @Observable workflow store — composes the above,
                        owns the joined in-memory model, all app writes
  components/                       UI
    lego_blocks/
      units/                        small reusable views + design tokens
        Theme, SpineView, MetricChartCard, CompositionChartCard,
        WorkoutCardView, ActivityLineView, CameraCapture
      integrations/                 composite modal flows (compose units + store)
        WorkoutEditSheet, FoodEntrySheet, SettingsSheet
    orchestrators/                  screens
        RootView (tabs), TodayView, TrendsView
```

## Rules

- **units** = reusable primitives with no knowledge of the app's workflow. Pure
  transforms (`DailyLogCodec`, `TelemetryCsv`, `ProgressImage`) or small views
  driven only by their inputs (`MetricChartCard`, `SpineView`).
- **integrations** = reusable pieces that compose units and touch the outside
  world (`VaultStore` files, `HealthKitService`) or compose units into a modal
  flow (`WorkoutEditSheet`).
- **orchestrators** = the thin workflow/screen layer. `LogStore` is the single
  service orchestrator; the screen views orchestrate UI. Keep them thin — push
  reusable logic down into blocks.

Single Swift module, so files see each other without imports; folders are purely
organizational. Data-storage contract lives in `docs/DATA-CONTRACT.md`.

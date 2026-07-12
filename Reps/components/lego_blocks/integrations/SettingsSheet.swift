import SwiftUI
import UniformTypeIdentifiers

struct SettingsSheet: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showingFolderPicker = false
    @State private var healthStatus: String?
    @State private var showingProgram = false
    @State private var showingMealPlan = false
    @AppStorage("reps.targetBodyFatPct") private var targetBodyFatPct = 0.0
    @AppStorage("reps.lockPhotos") private var lockPhotos = true

    // Energy & macro knobs. Every field is editable; the defaults produce the
    // auto-suggested targets (baseline 0 = compute from lean mass).
    @AppStorage("reps.baselineBurn") private var baselineBurn = 0.0
    @AppStorage("reps.dailyDeficit") private var dailyDeficit = 500.0
    @AppStorage("reps.proteinPerLbLean") private var proteinPerLbLean = 1.0
    @AppStorage("reps.fatPerLbBody") private var fatPerLbBody = 0.35

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showingProgram = true
                    } label: {
                        HStack {
                            Text("Training program").font(Typo.body).foregroundStyle(Palette.ink)
                            Spacer()
                            Text(store.activeProgram?.title ?? "None")
                                .font(Typo.monoSmall).foregroundStyle(Palette.graphite)
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Palette.hairline)
                        }
                    }
                } header: {
                    Text("Training")
                } footer: {
                    Text("Set up your workouts and the weekly rotation that schedules them.")
                }

                Section {
                    Button {
                        showingMealPlan = true
                    } label: {
                        HStack {
                            Text("Meal plan").font(Typo.body).foregroundStyle(Palette.ink)
                            Spacer()
                            Text(store.activeMealPlan?.title ?? "None")
                                .font(Typo.monoSmall).foregroundStyle(Palette.graphite)
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Palette.hairline)
                        }
                    }
                } header: {
                    Text("Nutrition")
                } footer: {
                    Text("Your daily staples — the meals that don't change — pre-filled for one-tap logging.")
                }

                Section {
                    HStack {
                        Text("Target body fat").font(Typo.body).foregroundStyle(Palette.ink)
                        Spacer()
                        TextField("e.g. 15", value: $targetBodyFatPct, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(Typo.mono)
                            .frame(width: 60)
                        Text("%").font(Typo.monoSmall).foregroundStyle(Palette.graphite)
                    }
                } header: {
                    Text("Goal")
                } footer: {
                    Text("Today shows how much body fat is left to lose to hit this, holding lean mass steady. Set 0 to hide it.")
                }

                Section {
                    numberRow("Baseline burn", value: $baselineBurn, unit: "kcal", placeholder: "auto")
                    numberRow("Daily deficit", value: $dailyDeficit, unit: "kcal", placeholder: "500")
                    numberRow("Protein", value: $proteinPerLbLean, unit: "g/lb lean", placeholder: "1.0")
                    numberRow("Fat", value: $fatPerLbBody, unit: "g/lb body", placeholder: "0.35")
                } header: {
                    Text("Energy & macros")
                } footer: {
                    Text("Today shows calories out (resting + activity) vs in, and macro targets. Leave baseline burn at 0 to compute it from your lean mass (Katch–McArdle); set any value to override. Carbs fill the calories left after protein and fat.")
                }

                Section {
                    Toggle(isOn: $lockPhotos) {
                        Text("Lock progress photos").font(Typo.body).foregroundStyle(Palette.ink)
                    }
                    .tint(Palette.madder)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Blurs your progress photos in the day view and requires Face ID to open them. Turn off to show them normally.")
                }

                Section("Vault") {
                    if store.vaultConfigured {
                        Label {
                            Text(store.vault.rootURL?.lastPathComponent ?? "Connected")
                                .font(Typo.body)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Palette.ink)
                        }
                    }
                    Button(store.vaultConfigured ? "Change vault folder" : "Choose vault folder (Body/)") {
                        showingFolderPicker = true
                    }
                    .foregroundStyle(Palette.madder)
                }
                Section {
                    Button("Connect Apple Health") {
                        Task {
                            do {
                                try await HealthKitService.requestAuthorization()
                                healthStatus = "Syncing…"
                                await store.syncHealth(around: Date())
                                healthStatus = "Synced. Weigh-ins from FitDays and Activity now fill in automatically."
                            } catch {
                                healthStatus = "Health access failed: \(error.localizedDescription)"
                            }
                        }
                    }
                    .foregroundStyle(Palette.madder)
                    if let healthStatus {
                        Text(healthStatus)
                            .font(.footnote)
                            .foregroundStyle(Palette.graphite)
                    }
                    #if DEBUG
                    Button("Seed sample weigh-ins (debug)") {
                        Task {
                            do {
                                try await HealthKitService.seedSampleWeighIns()
                                await store.syncHealth(around: Date())
                                healthStatus = "Seeded sample weigh-ins and synced."
                            } catch {
                                healthStatus = "Seed failed: \(error.localizedDescription)"
                            }
                        }
                    }
                    .foregroundStyle(Palette.graphite)
                    #endif
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("FitDays writes your weight and body composition into Apple Health; Reps reads it from there. Set FitDays → Settings → System Permission to share with Health.")
                }
                Section {
                    Button("Rescan vault") { store.load() }
                        .foregroundStyle(Palette.ink)
                    Button("Clean up daily notes") { store.cleanupDailyDocs() }
                        .foregroundStyle(Palette.madder)
                    if let summary = store.cleanupSummary {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(Palette.graphite)
                    }
                } footer: {
                    Text("The vault files are the source of truth — rescanning rebuilds everything the app shows. Clean up moves weight/activity into the CSVs and removes old telemetry-only daily files (your notes and workouts are kept).")
                }
                if let error = store.lastError {
                    Section("Last error") {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Palette.madder)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Palette.madder)
                }
            }
            .fileImporter(
                isPresented: $showingFolderPicker,
                allowedContentTypes: [.folder]
            ) { result in
                if case .success(let url) = result {
                    store.connectVault(to: url)
                }
            }
            .sheet(isPresented: $showingProgram) { ProgramSheet() }
            .sheet(isPresented: $showingMealPlan) { MealPlanSheet() }
        }
    }

    /// A labelled decimal field; shows `placeholder` (the default/auto value)
    /// when left at 0, so the user sees what the suggestion will use.
    private func numberRow(_ label: String, value: Binding<Double>, unit: String, placeholder: String) -> some View {
        HStack {
            Text(label).font(Typo.body).foregroundStyle(Palette.ink)
            Spacer()
            TextField(placeholder, value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(Typo.mono)
                .frame(width: 60)
            Text(unit).font(Typo.monoSmall).foregroundStyle(Palette.graphite)
                .frame(width: 66, alignment: .leading)
        }
    }
}

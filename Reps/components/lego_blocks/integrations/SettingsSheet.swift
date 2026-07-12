import SwiftUI
import UniformTypeIdentifiers

struct SettingsSheet: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showingFolderPicker = false
    @State private var healthStatus: String?
    @State private var showingProgram = false
    @AppStorage("reps.targetBodyFatPct") private var targetBodyFatPct = 0.0

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
        }
    }
}

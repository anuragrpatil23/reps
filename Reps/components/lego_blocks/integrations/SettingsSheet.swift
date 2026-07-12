import SwiftUI
import UniformTypeIdentifiers

struct SettingsSheet: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showingFolderPicker = false
    @State private var healthStatus: String?

    var body: some View {
        NavigationStack {
            List {
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
                } footer: {
                    Text("The vault files are the source of truth — rescanning rebuilds everything the app shows.")
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
        }
    }
}

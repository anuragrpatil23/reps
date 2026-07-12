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
                Section("Apple Health") {
                    Button("Connect Apple Health") {
                        Task {
                            do {
                                try await HealthKitService.requestAuthorization()
                                healthStatus = "Connected — weight, body comp, and activity will fill in automatically."
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

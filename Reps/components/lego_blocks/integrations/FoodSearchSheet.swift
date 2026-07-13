import SwiftUI

/// Look a food up online and pick a candidate to prefill the new-food form.
/// For when there's no label to scan — approximate numbers the user then
/// confirms. Explicitly opt-in: the only place the app sends a query off-device.
struct FoodSearchSheet: View {
    @Environment(\.dismiss) private var dismiss

    var initialQuery: String = ""
    /// The chosen candidate's nutrition, handed back to the form.
    var onPick: (FoodSearchResult) -> Void

    @State private var query = ""
    @State private var results: [FoodSearchResult] = []
    @State private var searching = false
    @State private var searched = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                content
            }
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Search online")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.graphite)
                }
            }
            .onAppear {
                query = initialQuery
                focused = true
                if !initialQuery.trimmingCharacters(in: .whitespaces).isEmpty { runSearch() }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.graphite)
            TextField("e.g. vanilla whey protein", text: $query)
                .font(Typo.body)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit(runSearch)
            if !query.isEmpty {
                Button { query = ""; results = []; searched = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.hairline)
                }
            }
        }
        .padding(12)
        .background(Palette.chalk, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if searching {
            Spacer()
            ProgressView().tint(Palette.madder)
            Spacer()
        } else if searched && results.isEmpty {
            Spacer()
            Text("No matches. Try a simpler name.")
                .font(Typo.body).foregroundStyle(Palette.graphite)
            Spacer()
        } else if results.isEmpty {
            Spacer()
            Text("Search a food database for approximate\nnutrition — you'll confirm every field.")
                .font(Typo.body).foregroundStyle(Palette.graphite)
                .multilineTextAlignment(.center)
            Spacer()
        } else {
            List(results) { result in
                Button { onPick(result); dismiss() } label: { row(result) }
                    .listRowBackground(Palette.paper)
                    .listRowSeparatorTint(Palette.hairline)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ result: FoodSearchResult) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name).font(Typo.body).foregroundStyle(Palette.ink)
                Text(result.detail).font(Typo.monoSmall).foregroundStyle(Palette.graphite)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let kcal = result.calories {
                Text("\(Int(kcal.rounded()))")
                    .font(Typo.mono).foregroundStyle(Palette.graphite)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        focused = false
        searching = true
        Task {
            let found = await FoodSearchService.search(q)
            await MainActor.run {
                results = found
                searching = false
                searched = true
            }
        }
    }
}

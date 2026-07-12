import SwiftUI

/// Log a meal: pick from your food database, set servings. "New food" opens the
/// form (with label scanning). This is the two-tap logger the small personal DB
/// makes possible.
struct FoodPickerSheet: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let onLog: (FoodEntry) -> Void

    @State private var search = ""
    @State private var showNewFood = false
    @State private var servingFor: Food?

    private var filtered: [Food] {
        let all = store.foods.sorted { $0.name.lowercased() < $1.name.lowercased() }
        guard !search.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.foods.isEmpty {
                    Text("No foods yet. Add one — scan a label or enter it once, and it's here for good.")
                        .font(Typo.body)
                        .foregroundStyle(Palette.graphite)
                        .listRowBackground(Color.clear)
                }
                ForEach(filtered) { food in
                    Button { servingFor = food } label: { row(food) }
                        .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .searchable(text: $search, prompt: "Search foods")
            .navigationTitle("Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.graphite)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showNewFood = true } label: { Label("New food", systemImage: "plus") }
                        .foregroundStyle(Palette.madder)
                }
            }
            .sheet(isPresented: $showNewFood) { FoodFormSheet() }
            .sheet(item: $servingFor) { food in
                ServingEditor(food: food) { entry in
                    onLog(entry)
                    dismiss()
                }
            }
        }
    }

    private func row(_ food: Food) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name).font(Typo.body).foregroundStyle(Palette.ink)
                if !food.servingDesc.isEmpty {
                    Text(food.servingDesc).font(Typo.monoSmall).foregroundStyle(Palette.graphite)
                }
            }
            Spacer()
            Text("\(Int(food.calories.rounded())) kcal")
                .font(Typo.mono).foregroundStyle(Palette.graphite)
        }
        .contentShape(Rectangle())
        .listRowBackground(Color.clear)
    }
}

/// Choose how many servings, preview the scaled macros, add to the day.
private struct ServingEditor: View {
    @Environment(\.dismiss) private var dismiss
    let food: Food
    let onAdd: (FoodEntry) -> Void

    @State private var servings = 1.0

    private var scaled: Macros { food.macros.scaled(by: servings) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(food.name).font(Typo.display).foregroundStyle(Palette.ink)

                Stepper(value: $servings, in: 0.25...20, step: 0.25) {
                    HStack {
                        Text("Servings").font(Typo.body).foregroundStyle(Palette.ink)
                        Spacer()
                        Text(servings.formatted(.number.precision(.fractionLength(0...2))))
                            .font(Typo.mono).foregroundStyle(Palette.madder)
                    }
                }
                .tint(Palette.madder)

                HStack(spacing: 18) {
                    macro("\(Int(scaled.calories.rounded()))", "kcal")
                    macro("\(Int(scaled.proteinG.rounded()))", "P")
                    macro("\(Int(scaled.carbsG.rounded()))", "C")
                    macro("\(Int(scaled.fatG.rounded()))", "F")
                    Spacer()
                }
                Spacer()
            }
            .padding(20)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Servings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.graphite)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let at = Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                        onAdd(FoodEntry(at: at, text: food.name, foodId: food.id, servings: servings))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.madder)
                }
            }
            .presentationDetents([.height(280)])
        }
    }

    private func macro(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(Typo.mono).foregroundStyle(Palette.ink)
            Text(label).font(Typo.monoSmall).foregroundStyle(Palette.graphite)
        }
    }
}

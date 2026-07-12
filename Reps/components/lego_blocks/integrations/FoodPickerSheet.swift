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
    @State private var editingFood: Food?

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
                        .contextMenu {
                            Button { editingFood = food } label: {
                                Label("Edit food", systemImage: "pencil")
                            }
                            Button(role: .destructive) { store.deleteFood(food.id) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
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
            .sheet(item: $editingFood) { FoodFormSheet(editing: $0) }
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
                if !food.servingLabel.isEmpty {
                    Text(food.servingLabel).font(Typo.monoSmall).foregroundStyle(Palette.graphite)
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

/// Choose the amount, preview the scaled macros, add to the day. Set what one
/// serving weighs and you can log by grams — enter "150 g" and the app works out
/// the serving fraction for you. The weight is remembered on the food.
///
/// Reused to edit an already-logged entry: pass `editing` to pre-fill its
/// servings and keep its time, so `onAdd` yields an updated entry (same id).
struct ServingEditor: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let food: Food
    let editing: FoodEntry?
    let onAdd: (FoodEntry) -> Void

    @State private var servings: Double
    @State private var servingGrams: Double?
    @FocusState private var focus: Field?

    private enum Field { case grams, pieces }

    init(food: Food, editing: FoodEntry? = nil, onAdd: @escaping (FoodEntry) -> Void) {
        self.food = food
        self.editing = editing
        self.onAdd = onAdd
        _servings = State(initialValue: editing?.servings ?? 1)
        // Fall back to a gram weight embedded in the serving text ("4 oz (112g)").
        _servingGrams = State(initialValue: food.servingGrams ?? Self.gramsInText(food.servingDesc))
    }

    /// Pull a "<n>g" weight out of a free-text serving description.
    private static func gramsInText(_ text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*g\b"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range])
    }

    private var scaled: Macros { food.macros.scaled(by: servings) }
    private var hasWeight: Bool { (servingGrams ?? 0) > 0 }
    private var hasPieces: Bool { (food.servingPieces ?? 0) > 0 }

    /// Grams eaten ⇄ servings, once a serving weight is known.
    private var gramsBinding: Binding<Double> {
        Binding(
            get: { servings * (servingGrams ?? 0) },
            set: { grams in
                if let per = servingGrams, per > 0 { servings = grams / per }
            }
        )
    }

    /// Pieces eaten ⇄ servings, once a per-serving piece count is known.
    private var piecesBinding: Binding<Double> {
        Binding(
            get: { servings * (food.servingPieces ?? 0) },
            set: { pieces in
                if let per = food.servingPieces, per > 0 { servings = pieces / per }
            }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name).font(Typo.display).foregroundStyle(Palette.ink)
                    if !food.servingLabel.isEmpty {
                        Text(food.servingLabel).font(Typo.monoSmall).foregroundStyle(Palette.graphite)
                    }
                }

                Stepper(value: $servings, in: 0.25...50, step: 0.25) {
                    HStack {
                        Text("Servings").font(Typo.body).foregroundStyle(Palette.ink)
                        Spacer()
                        Text(servings.formatted(.number.precision(.fractionLength(0...2))))
                            .font(Typo.mono).foregroundStyle(Palette.madder)
                    }
                }
                .tint(Palette.madder)

                // Log by pieces or grams — both come from the food (set when
                // editing it) and just re-express the serving count.
                if hasPieces {
                    fieldRow("Pieces eaten", unit: "pcs", field: .pieces) {
                        TextField("pieces", value: piecesBinding, format: .number.precision(.fractionLength(0...1)))
                            .focused($focus, equals: .pieces)
                    }
                }
                if hasWeight {
                    fieldRow("Amount eaten", unit: "g", field: .grams) {
                        TextField("grams", value: gramsBinding, format: .number.precision(.fractionLength(0...1)))
                            .focused($focus, equals: .grams)
                    }
                }

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
            .navigationTitle("Amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.graphite)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save") { add() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.madder)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }.foregroundStyle(Palette.madder)
                }
            }
            .presentationDetents([.height(320 + (hasPieces ? 44 : 0) + (hasWeight ? 44 : 0))])
        }
    }

    /// A full-width tappable row — the whole row focuses the field, so the tap
    /// target isn't just the little number box.
    private func fieldRow(_ label: String, unit: String, field: Field,
                          @ViewBuilder _ input: () -> some View) -> some View {
        HStack {
            Text(label).font(Typo.body).foregroundStyle(Palette.ink)
            Spacer()
            input()
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(Typo.mono).foregroundStyle(Palette.madder)
                .frame(width: 90)
            Text(unit).font(Typo.monoSmall).foregroundStyle(Palette.graphite)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { focus = field }
    }

    private func add() {
        // Remember the serving weight on the food for next time.
        if servingGrams != food.servingGrams {
            var updated = food
            updated.servingGrams = servingGrams
            store.saveFood(updated)
        }
        // Keep the entry's original time when editing; stamp now when adding.
        let at = editing?.at ?? Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        onAdd(FoodEntry(at: at, text: food.name, foodId: food.id, servings: servings))
        dismiss()
    }

    private func macro(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(Typo.mono).foregroundStyle(Palette.ink)
            Text(label).font(Typo.monoSmall).foregroundStyle(Palette.graphite)
        }
    }
}

import SwiftUI

/// The nutrition hub: pick the active meal plan and edit each plan's daily
/// staples — the foods you eat every day, so only the one meal that changes
/// needs logging. Mirrors `ProgramSheet` on the training side.
struct MealPlanSheet: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var editingPlan: MealPlan?
    @State private var newPlan = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.mealPlans.isEmpty {
                        Text("No meal plans yet. Create one for your daily staples — the meals that don't change — and log them in a tap each day.")
                            .font(Typo.body).foregroundStyle(Palette.graphite)
                    }
                    ForEach(store.mealPlans) { plan in
                        Button { editingPlan = plan } label: { planRow(plan) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { $0.map { store.mealPlans[$0] }.forEach { store.deleteMealPlan($0.key) } }
                    Button { newPlan = true } label: {
                        Label("New meal plan", systemImage: "plus").foregroundStyle(Palette.madder)
                    }
                } header: {
                    Text("Meal plans")
                } footer: {
                    Text("The active plan (checked) pre-fills its staples on each day. Log them with one tap, then add whatever else you ate.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Meal plans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Palette.madder)
                }
            }
            .sheet(item: $editingPlan) { MealPlanEditSheet(editing: $0) }
            .sheet(isPresented: $newPlan) { MealPlanEditSheet(editing: nil) }
        }
    }

    private func planRow(_ plan: MealPlan) -> some View {
        HStack {
            Image(systemName: store.activeMealPlanKey == plan.key ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(store.activeMealPlanKey == plan.key ? Palette.madder : Palette.hairline)
                .onTapGesture { store.activeMealPlanKey = plan.key }
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.title).font(Typo.body).foregroundStyle(Palette.ink)
                Text("\(plan.phase.label) · \(plan.staples.count) staple\(plan.staples.count == 1 ? "" : "s")")
                    .font(Typo.monoSmall).foregroundStyle(Palette.graphite)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Palette.hairline)
        }
        .contentShape(Rectangle())
        .listRowBackground(Color.clear)
    }
}

/// Edit one meal plan: title, phase, and the ordered list of daily staples,
/// each added from the food database (with servings).
private struct MealPlanEditSheet: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let editing: MealPlan?

    @State private var title = ""
    @State private var phase: TrainingPhase = .cut
    @State private var staples: [FoodEntry] = []
    @State private var addingStaple = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan") {
                    TextField("Name (e.g. Cut staples)", text: $title).font(Typo.body)
                    Picker("Phase", selection: $phase) {
                        ForEach(TrainingPhase.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section {
                    if staples.isEmpty {
                        Text("Add the foods you eat every day.")
                            .font(Typo.body).foregroundStyle(Palette.graphite)
                    }
                    ForEach(staples) { staple in
                        stapleRow(staple)
                    }
                    .onDelete { staples.remove(atOffsets: $0) }
                    Button { addingStaple = true } label: {
                        Label("Add staple", systemImage: "plus").foregroundStyle(Palette.madder)
                    }
                } header: {
                    Text("Daily staples")
                } footer: {
                    Text("These pre-fill every day for one-tap logging. Servings are remembered per food.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .environment(\.editMode, .constant(.active))
            .navigationTitle(editing == nil ? "New meal plan" : "Edit meal plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.graphite)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold).foregroundStyle(Palette.madder)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $addingStaple) {
                FoodPickerSheet { entry in staples.append(entry) }
            }
            .onAppear { if let editing { populate(editing) } }
        }
    }

    private func stapleRow(_ staple: FoodEntry) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label(staple)).font(Typo.body).foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
            if let m = store.macros(for: staple) {
                Text("\(Int(m.calories.rounded())) kcal")
                    .font(Typo.mono).foregroundStyle(Palette.graphite)
            }
        }
    }

    /// "Kimchi Rice ×2" for DB foods, else the free text.
    private func label(_ entry: FoodEntry) -> String {
        if entry.foodId != nil {
            let servings = entry.servings ?? 1
            let suffix = servings == 1 ? "" : " ×\(servings.formatted(.number.precision(.fractionLength(0...2))))"
            return (entry.text ?? "food") + suffix
        }
        return entry.text ?? entry.recipe ?? "food"
    }

    private func populate(_ plan: MealPlan) {
        title = plan.title
        phase = plan.phase
        staples = plan.staples
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let key = editing?.key ?? store.uniqueMealPlanKey(for: trimmed)
        store.saveMealPlan(MealPlan(key: key, title: trimmed, phase: phase, staples: staples))
        dismiss()
    }
}

import SwiftUI
import PhotosUI

/// Create or edit a food. Scan a nutrition label to prefill (Vision OCR +
/// on-device model), then confirm/edit — everything stays editable. Captures the
/// full Nutrition Facts panel; the fat/carb breakdown and micros are optional.
struct FoodFormSheet: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var editing: Food?
    var onSaved: (Food) -> Void = { _ in }

    @State private var name = ""
    @State private var servingDesc = ""
    @State private var servingGrams: Double?
    @State private var servingsPerContainer: Double?
    @State private var n = Macros()

    @State private var scanning = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var photoItem: PhotosPickerItem?
    @FocusState private var focus: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Menu {
                        if CameraCapture.isAvailable {
                            Button { showCamera = true } label: { Label("Scan with camera", systemImage: "camera") }
                        }
                        Button { showLibrary = true } label: { Label("Choose label photo", systemImage: "photo.on.rectangle") }
                    } label: {
                        Label("Scan nutrition label", systemImage: "text.viewfinder")
                            .foregroundStyle(Palette.madder)
                    }
                    if scanning {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Reading label…").font(Typo.body).foregroundStyle(Palette.graphite)
                        }
                    }
                } footer: {
                    Text("Snap the Nutrition Facts panel; the fields below fill in for you to confirm.")
                }

                Section("Food") {
                    TextField("Name", text: $name).font(Typo.body)
                    TextField("Serving (e.g. 1 cup / 170g)", text: $servingDesc).font(Typo.body)
                    optField("Serving weight", value: $servingGrams, unit: "g")
                    optField("Servings / container", value: $servingsPerContainer, unit: "")
                }

                Section("Per serving") {
                    macroField("Calories", value: $n.calories, unit: "kcal")
                    macroField("Protein", value: $n.proteinG, unit: "g")
                    macroField("Total carbs", value: $n.carbsG, unit: "g")
                    macroField("Total fat", value: $n.fatG, unit: "g")
                }

                Section("Fat breakdown") {
                    macroField("Saturated fat", value: $n.satFatG, unit: "g")
                    macroField("Trans fat", value: $n.transFatG, unit: "g")
                    macroField("Cholesterol", value: $n.cholesterolMg, unit: "mg")
                }

                Section("Carb breakdown") {
                    macroField("Fiber", value: $n.fiberG, unit: "g")
                    macroField("Total sugars", value: $n.totalSugarsG, unit: "g")
                    macroField("Added sugars", value: $n.addedSugarsG, unit: "g")
                    macroField("Sodium", value: $n.sodiumMg, unit: "mg")
                }

                Section("Micronutrients") {
                    macroField("Vitamin D", value: $n.vitaminDMcg, unit: "mcg")
                    macroField("Calcium", value: $n.calciumMg, unit: "mg")
                    macroField("Iron", value: $n.ironMg, unit: "mg")
                    macroField("Potassium", value: $n.potassiumMg, unit: "mg")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle(editing == nil ? "New food" : "Edit food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.graphite)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.madder)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }.foregroundStyle(Palette.madder)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCapture { image in Task { await scan(image) } }.ignoresSafeArea()
            }
            .photosPicker(isPresented: $showLibrary, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) {
                guard let photoItem else { return }
                Task {
                    if let data = try? await photoItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await scan(image)
                    }
                    self.photoItem = nil
                }
            }
            .onAppear { if let editing { populate(editing) } }
        }
    }

    private func macroField(_ label: String, value: Binding<Double>, unit: String) -> some View {
        fieldRow(label, unit: unit) {
            TextField(label, value: value, format: .number).focused($focus, equals: label)
        }
    }

    /// Like macroField but for an optional value (blank when unset).
    private func optField(_ label: String, value: Binding<Double?>, unit: String) -> some View {
        fieldRow(label, unit: unit) {
            TextField(label, value: value, format: .number).focused($focus, equals: label)
        }
    }

    /// A row whose whole width is the tap target — tapping anywhere focuses the
    /// field, so you don't have to hit the small number box on the right.
    private func fieldRow(_ label: String, unit: String,
                          @ViewBuilder _ input: () -> some View) -> some View {
        HStack {
            Text(label).font(Typo.body).foregroundStyle(Palette.ink)
            Spacer()
            input()
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(Typo.mono)
                .frame(width: 90)
            if !unit.isEmpty {
                Text(unit).font(Typo.monoSmall).foregroundStyle(Palette.graphite)
                    .frame(width: 30, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focus = label }
    }

    private func scan(_ image: UIImage) async {
        scanning = true
        let facts = await NutritionExtractor.extract(from: image)
        if let v = facts.name, !v.isEmpty, name.isEmpty { name = v }
        if let v = facts.servingDesc, !v.isEmpty { servingDesc = v }
        if let v = facts.servingGrams { servingGrams = v }
        if let v = facts.servingsPerContainer { servingsPerContainer = v }
        if let v = facts.calories { n.calories = v }
        if let v = facts.proteinG { n.proteinG = v }
        if let v = facts.carbsG { n.carbsG = v }
        if let v = facts.fatG { n.fatG = v }
        if let v = facts.satFatG { n.satFatG = v }
        if let v = facts.transFatG { n.transFatG = v }
        if let v = facts.cholesterolMg { n.cholesterolMg = v }
        if let v = facts.sodiumMg { n.sodiumMg = v }
        if let v = facts.fiberG { n.fiberG = v }
        if let v = facts.totalSugarsG { n.totalSugarsG = v }
        if let v = facts.addedSugarsG { n.addedSugarsG = v }
        if let v = facts.vitaminDMcg { n.vitaminDMcg = v }
        if let v = facts.calciumMg { n.calciumMg = v }
        if let v = facts.ironMg { n.ironMg = v }
        if let v = facts.potassiumMg { n.potassiumMg = v }
        scanning = false
    }

    private func populate(_ food: Food) {
        name = food.name
        servingDesc = food.servingDesc
        servingGrams = food.servingGrams
        servingsPerContainer = food.servingsPerContainer
        n = food.nutrition
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let id = editing?.id ?? store.uniqueFoodId(for: trimmed)
        let food = Food(
            id: id, name: trimmed, servingDesc: servingDesc,
            servingGrams: servingGrams, servingsPerContainer: servingsPerContainer,
            nutrition: n, barcode: editing?.barcode, updatedAt: nil
        )
        store.saveFood(food)
        onSaved(food)
        dismiss()
    }
}

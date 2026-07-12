import SwiftUI
import PhotosUI

/// Create or edit a food. Scan a nutrition label to prefill (Vision OCR +
/// on-device model), then confirm/edit — everything stays editable.
struct FoodFormSheet: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var editing: Food?
    var onSaved: (Food) -> Void = { _ in }

    @State private var name = ""
    @State private var servingDesc = ""
    @State private var calories = 0.0
    @State private var protein = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0

    @State private var scanning = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var photoItem: PhotosPickerItem?

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
                }

                Section("Per serving") {
                    macroField("Calories", value: $calories, unit: "kcal")
                    macroField("Protein", value: $protein, unit: "g")
                    macroField("Carbs", value: $carbs, unit: "g")
                    macroField("Fat", value: $fat, unit: "g")
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
        HStack {
            Text(label).font(Typo.body).foregroundStyle(Palette.ink)
            Spacer()
            TextField(label, value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(Typo.mono)
                .frame(width: 80)
            Text(unit).font(Typo.monoSmall).foregroundStyle(Palette.graphite)
        }
    }

    private func scan(_ image: UIImage) async {
        scanning = true
        let facts = await NutritionExtractor.extract(from: image)
        if let v = facts.name, !v.isEmpty, name.isEmpty { name = v }
        if let v = facts.servingDesc, !v.isEmpty { servingDesc = v }
        if let v = facts.calories { calories = v }
        if let v = facts.proteinG { protein = v }
        if let v = facts.carbsG { carbs = v }
        if let v = facts.fatG { fat = v }
        scanning = false
    }

    private func populate(_ food: Food) {
        name = food.name
        servingDesc = food.servingDesc
        calories = food.calories
        protein = food.proteinG
        carbs = food.carbsG
        fat = food.fatG
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let id = editing?.id ?? store.uniqueFoodId(for: trimmed)
        let food = Food(
            id: id, name: trimmed, servingDesc: servingDesc,
            calories: calories, proteinG: protein, carbsG: carbs, fatG: fat,
            barcode: editing?.barcode, updatedAt: nil
        )
        store.saveFood(food)
        onSaved(food)
        dismiss()
    }
}

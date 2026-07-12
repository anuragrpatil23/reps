import SwiftUI

/// Dumb-simple by design (contract §food): a time and a line of text.
/// Macro parsing is the AI trainer's job, not this sheet's.
struct FoodEntrySheet: View {
    let onSave: (FoodEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()
    @State private var text = ""
    @FocusState private var textFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .font(Typo.body)
                    .tint(Palette.madder)
                TextField("What did you eat?", text: $text, axis: .vertical)
                    .font(Typo.body)
                    .lineLimit(2...4)
                    .padding(12)
                    .background(Palette.paper, in: RoundedRectangle(cornerRadius: 10))
                    .focused($textFocused)
                Spacer()
            }
            .padding(20)
            .background(Palette.butter.ignoresSafeArea())
            .navigationTitle("Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Palette.graphite)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let at = time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                        onSave(FoodEntry(at: at, text: text.trimmingCharacters(in: .whitespacesAndNewlines)))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.madder)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { textFocused = true }
        }
        .presentationDetents([.height(300)])
    }
}

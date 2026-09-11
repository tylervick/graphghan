import SwiftUI

struct JumpToRowSheet: View {
    @Environment(\.dismiss) private var dismiss
    let rowCount: Int
    let current: Int
    let onJump: (Int) -> Void
    @State private var row: Int

    init(rowCount: Int, current: Int, onJump: @escaping (Int) -> Void) {
        self.rowCount = rowCount
        self.current = current
        self.onJump = onJump
        _row = State(initialValue: current)
    }

    var body: some View {
        NavigationStack {
            Form {
                Stepper(value: $row, in: 1...max(1, rowCount)) { Text("Row \(row) of \(rowCount)") }
                TextField("Row", value: $row, format: .number).keyboardType(.numberPad)
            }
            .navigationTitle("Jump to row")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Jump") { onJump(min(max(1, row), rowCount)); dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

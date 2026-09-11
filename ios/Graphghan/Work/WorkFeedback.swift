import GraphghanCore

enum WorkFeedback: Equatable {
    case run, row, newColor, finished
}

/// Which haptic a step deserves. Pure so it is testable; Haptics plays it.
enum WorkFeedbackRule {
    static func feedback(for step: WorkStep, from previous: Cursor, in seq: WorkSequence) -> WorkFeedback? {
        if step.kind == .back { return nil }
        if step.finished { return .finished }
        guard let pass = seq.pass(at: step.cursor.row), step.cursor.run < pass.runs.count else { return nil }
        let code = pass.runs[step.cursor.run].code
        let previousRowCodes = Set(seq.pass(at: step.cursor.row - 1)?.runs.map(\.code) ?? [])
        let introducesColor = seq.pass(at: step.cursor.row - 1) != nil && !previousRowCodes.contains(code)
        if introducesColor { return .newColor }
        return step.startedNewRow ? .row : .run
    }
}

import GraphghanCore

enum WorkFeedback: Equatable {
    case step, run, row, newColor, finished
}

/// Which haptic a step deserves. Pure so it is testable; Haptics plays it.
enum WorkFeedbackRule {
    static func feedback(for step: WorkStep, in seq: WorkSequence) -> WorkFeedback? {
        if step.kind == .back { return nil }
        if step.finished { return .finished }
        if step.atBoundary { return .row }
        if step.cursor.stitch > 0 { return .step }
        guard let pass = seq.pass(at: step.cursor.row), step.cursor.run < pass.runs.count else { return nil }
        let code = pass.runs[step.cursor.run].code
        let previousRowCodes = Set(seq.pass(at: step.cursor.row - 1)?.runs.map(\.code) ?? [])
        let introducesColor = seq.pass(at: step.cursor.row - 1) != nil && !previousRowCodes.contains(code)
        if introducesColor { return .newColor }
        // The row haptic already fired at the turn, so an advance that walked through a boundary
        // step does not repeat it here. A jump never passes the turn, so landing on another row is
        // still a row change and still plays it.
        if step.startedNewRow, step.kind != .advance || !seq.hasBoundaryStep(after: step.cursor.row - 1) { return .row }
        return .run
    }
}

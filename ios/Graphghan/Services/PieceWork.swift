import GraphghanCore

/// The current piece of a project, ready to work: a chart and its sequence, or written rows.
enum PieceWork {
    case chart(Chart, WorkSequence)
    case written(WrittenSequence)
    var model: PieceModel {
        switch self {
        case .chart(_, let seq): .chart(seq)
        case .written(let seq): .written(seq)
        }
    }
}

/// One piece copy as the project screen lists it (spec 2026-09-25 §6.2).
struct PieceStatus: Equatable, Identifiable {
    let piece: ManifestPiece
    let copy: Int
    let isWritten: Bool
    let line: String
    let finished: Bool
    let isCurrent: Bool
    var id: PieceKey { PieceKey(piece: piece.id, copy: copy) }
}

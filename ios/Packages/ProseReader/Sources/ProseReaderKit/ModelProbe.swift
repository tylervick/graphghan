// Asking the model three ever-larger questions, to find out which one it refuses (#176).

import Foundation
import FoundationModels

/// What three probes of the model answered, in the order the issue asks them in: a one-line
/// prompt to a plain session, the same prompt under the row instructions, and a one-row
/// structured answer. The first one that fails says where the trouble is — the app's relationship
/// with the model, the size of the instructions, or structured generation — and each step keeps
/// its own reason, so a refusal that is not a rate limit is not mistaken for one.
public struct ModelProbe: Sendable, Equatable {
    /// Which question was asked, so the finding below does not have to guess from a position.
    public enum Kind: String, Sendable {
        /// Not a question at all: the model is not on this device.
        case availability
        /// A one-line prompt to a session with no instructions.
        case bare
        /// The same prompt under the row instructions, at whatever size they are.
        case instructed
        /// A `@Generable` answer, which is what the reader actually asks for.
        case structured
    }

    public struct Step: Sendable, Equatable {
        public let kind: Kind
        public let name: String
        public let ok: Bool
        /// The answer's first words, or the failure's own description.
        public let detail: String
        public let seconds: Double
        public init(kind: Kind, name: String, ok: Bool, detail: String, seconds: Double) {
            self.kind = kind
            self.name = name
            self.ok = ok
            self.detail = detail
            self.seconds = seconds
        }
    }

    public let steps: [Step]
    /// Whatever the caller knows and the reader does not: the app's foreground state when the
    /// check began, say. Printed under the steps.
    public let context: [String]

    public init(steps: [Step], context: [String] = []) {
        self.steps = steps
        self.context = context
    }

    /// The sentence that names what the steps implicate, which is the point of running them.
    public var finding: String {
        guard let failed = steps.first(where: { !$0.ok }) else {
            return "Every probe answered, so the model is reachable from here; the check's refusal was not its first request."
        }
        switch failed.kind {
        case .availability:
            return "There is no model to ask on this iPhone, so nothing below was run."
        case .bare:
            return "The very first one-line request is refused, so this is the app's relationship with the model, not the reader's prompts."
        case .instructed:
            return "A bare prompt answers and the same prompt under the row instructions does not, so the instructions are too big for this phone."
        case .structured:
            return "Plain text answers and a structured answer does not, so it is @Generable output on this phone."
        }
    }

    /// The whole report as the sheet prints it.
    public var text: String {
        (steps.map { "\($0.ok ? "ok" : "no") · \($0.name): \($0.detail) (\(String(format: "%.1f", $0.seconds)) s)" }
            + context + [finding]).joined(separator: "\n")
    }
}

@available(macOS 26.0, iOS 26.0, *)
extension ProseReader {
    /// Runs the three probes against this reader's own model and instructions, once each and with
    /// no retrying: what is wanted is the first answer, exactly as the check would have got it.
    /// Stops at the first refusal, because the larger questions cannot clear a smaller one's.
    public func probe(context: [String] = []) async -> ModelProbe {
        var steps: [ModelProbe.Step] = []
        var context = context
        if let why = unavailableReason() {
            return ModelProbe(steps: [.init(kind: .availability, name: "the model is there", ok: false, detail: why, seconds: 0)], context: context)
        }
        context.append("instructions: \(rowInstructionsInUse.count) characters\(options.examples ? ", with the grammar examples" : "")")

        func step(_ kind: ModelProbe.Kind, _ name: String, _ body: () async throws -> String) async -> Bool {
            let started = Date()
            do {
                let answer = try await body()
                steps.append(.init(kind: kind, name: name, ok: true, detail: String(answer.prefix(60)), seconds: Date().timeIntervalSince(started)))
                return true
            } catch {
                steps.append(.init(kind: kind, name: name, ok: false, detail: ProseReader.failureText(error), seconds: Date().timeIntervalSince(started)))
                return false
            }
        }

        let hello = "Reply with the single word ready."
        guard await step(.bare, "a one-line prompt, no instructions", {
            try await self.bareSession().respond(to: hello).content
        }) else { return ModelProbe(steps: steps, context: context) }

        guard await step(.instructed, "the same prompt under the row instructions", {
            try await self.makeSession(instructions: self.rowInstructionsInUse).respond(to: hello).content
        }) else { return ModelProbe(steps: steps, context: context) }

        _ = await step(.structured, "a one-row structured answer", {
            let got = try await self.makeSession(instructions: self.rowInstructionsInUse)
                .respond(to: "Transcribe this row:\nRow 1: 3 A, 2 B", generating: WrittenRowOut.self).content
            return "row \(got.row), \(got.runs.count) runs"
        })
        return ModelProbe(steps: steps, context: context)
    }
}

// Asking the model ever-larger questions, to find out which one it refuses (#176).

import Foundation
import FoundationModels

/// What the probes of the model answered, in the order the issue asks them in: a one-line prompt
/// to a plain session, the same prompt under the row instructions, and a one-row structured
/// answer. When one of the larger two is refused the bare prompt is asked a second time, because
/// without that control a refusal that follows the *number* of requests looks exactly like one
/// that follows what is in them. Each step keeps its own reason, so a refusal that is not a rate
/// limit is not mistaken for one.
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
        /// The bare prompt asked again after a later one was refused: the control that tells
        /// "this request's content is refused" apart from "another request is refused".
        case control
        /// `LimitReport`: small requests asked one after another, to find how many are allowed.
        case burst
        /// `LimitReport`: one prompt the size the front-matter read sends.
        case bigPrompt
        /// `LimitReport`: whether a refusal clears on its own, and after how long.
        case recovery
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

    /// What the steps show, and only what they show. Where a cause is named it is the control
    /// that licenses naming it; with no control the sentence stays an observation.
    public var finding: String {
        guard let failed = steps.first(where: { !$0.ok }) else {
            return "Every probe answered, so the model is reachable from here; the check's refusal was not its first request."
        }
        let control = steps.first { $0.kind == .control }
        switch failed.kind {
        case .availability:
            return "There is no model to ask on this iPhone, so nothing below was run."
        case .burst, .bigPrompt, .recovery:
            return "Measured by `LimitReport`, which words its own finding."
        case .bare, .control:
            return "The first one-line request, with no instructions and no structure, was refused. Nothing smaller can be asked, so this is the app's relationship with the model rather than anything in the reader's prompts."
        case .instructed:
            if control?.ok == false {
                return "A bare prompt answered, the same prompt under the row instructions did not, and the bare prompt is then refused as well: the refusals follow how many requests have been made, not what is in them."
            }
            return "A bare prompt answered and the same prompt under the row instructions did not, while a bare prompt still answers afterwards: the instructions are what this phone will not take."
        case .structured:
            if control?.ok == false {
                return "Plain text answered twice and a structured answer did not, but the bare prompt is then refused as well: the refusals follow how many requests have been made, not what is in them."
            }
            return "Plain text answers and a structured answer does not, while a bare prompt still answers afterwards: it is @Generable output this phone will not take."
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
    /// Runs the probes against this reader's own model and instructions, once each and with no
    /// retrying: what is wanted is the first answer, exactly as the check would have got it.
    /// Stops at the first refusal, because a larger question cannot clear a smaller one's -- but
    /// asks the bare prompt once more when the refusal came from one of the larger two.
    ///
    /// Only the availability step can run where there is no model, which includes every simulator.
    public func probe(context: [String] = []) async -> ModelProbe {
        var steps: [ModelProbe.Step] = []
        var context = context
        if let why = unavailableReason() {
            return ModelProbe(steps: [.init(kind: .availability, name: "the model is there", ok: false, detail: why, seconds: 0)], context: context)
        }
        context.append("instructions: \(rowInstructionsInUse.count) characters\(options.examples ? ", with the grammar examples" : "")")

        let hello = "Reply with the single word ready."
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
        func bare(_ kind: ModelProbe.Kind, _ name: String) async -> Bool {
            await step(kind, name) { try await self.bareSession().respond(to: hello).content }
        }
        // The control: the smallest question again, after a bigger one was refused.
        func control() async {
            _ = await bare(.control, "the one-line prompt again, as a control")
        }

        guard await bare(.bare, "a one-line prompt, no instructions") else {
            return ModelProbe(steps: steps, context: context)
        }
        guard await step(.instructed, "the same prompt under the row instructions", {
            try await self.makeSession(instructions: self.rowInstructionsInUse).respond(to: hello).content
        }) else {
            await control()
            return ModelProbe(steps: steps, context: context)
        }
        let structured = await step(.structured, "a one-row structured answer", {
            let got = try await self.makeSession(instructions: self.rowInstructionsInUse)
                .respond(to: "Transcribe this row:\nRow 1: 3 A, 2 B", generating: WrittenRowOut.self).content
            return "row \(got.row), \(got.runs.count) runs"
        })
        if !structured { await control() }
        return ModelProbe(steps: steps, context: context)
    }
}

// Measuring what the phone will actually let the app ask for (#176, round two).
//
// The three probes in `ModelProbe` answered on the device that refuses the check: a bare prompt,
// the same prompt under the row instructions, and a structured row, all in about two seconds
// each, with the app active. So the refusal follows none of those things. What is left is the
// shape of the check itself -- how much it asks for, and how fast -- and that is what this
// measures, because a limit nobody has measured cannot be paced against.

import Foundation
import FoundationModels

/// What a burst of requests found: how many the model answered before refusing one, whether one
/// large prompt is enough on its own to bring the refusal on, and how long a refusal lasts.
/// Together those say which kind of limit this is, and a pacer can then be built to the number
/// rather than to a guess.
public struct LimitReport: Sendable, Equatable {
    public let steps: [ModelProbe.Step]
    public let context: [String]

    public init(steps: [ModelProbe.Step], context: [String] = []) {
        self.steps = steps
        self.context = context
    }

    func step(_ kind: ModelProbe.Kind) -> ModelProbe.Step? { steps.first { $0.kind == kind } }

    /// What the measurement shows. Each branch names a different limit and a different fix, so
    /// this is the sentence the next commit is written from.
    public var finding: String {
        if let unavailable = step(.availability), !unavailable.ok {
            return "There is no model to ask on this iPhone, so nothing was measured."
        }
        let burst = step(.burst)
        let big = step(.bigPrompt)
        let recovery = step(.recovery)
        if burst?.ok == true, big?.ok != false {
            return "Nothing was refused: neither a run of small requests nor one large prompt brought it on. Whatever the check trips is not reproduced by this measurement, so the next thing to look at is the pattern's own text rather than the pace."
        }
        var said: [String] = []
        if let burst, !burst.ok { said.append("small requests one after another are refused after a few, so the limit counts requests or the tokens in them, and the reader has to be paced") }
        if let big, !big.ok { said.append("one 5000-character prompt is enough on its own to bring the refusal on, which points at the front-matter read (#178) rather than at the rows") }
        if let recovery {
            said.append(recovery.ok
                ? "the refusal clears on its own after a wait, so the waits the reader already has are the right shape and only too short"
                : "the refusal had not cleared after the longest wait tried, so waiting is not the answer and the request rate has to come down")
        }
        return said.joined(separator: "; ") + "."
    }

    public var text: String {
        (steps.map { "\($0.ok ? "ok" : "no") · \($0.name): \($0.detail) (\(String(format: "%.1f", $0.seconds)) s)" }
            + context + [finding]).joined(separator: "\n")
    }
}

@available(macOS 26.0, iOS 26.0, *)
extension ProseReader {
    /// Small requests asked one after another before the measurement gives up and calls the
    /// burst unlimited. Thirty is well past the handful the probes proved and well short of the
    /// hundreds a pattern needs.
    public static let burstLimit = 30
    /// The waits tried after a refusal, to find how long one lasts.
    public static let recoveryWaits = [15, 30, 60]

    /// Asks the model the same small structured question over and over, then once with a prompt
    /// the size of the ones `readFront` sends, then again after waiting. Takes a few minutes on
    /// a device and nothing at all on a simulator, which has no model to ask.
    ///
    /// Cancellation stops it between requests and keeps what it has.
    public func measureRequestLimit(context: [String] = [], progress: (@Sendable (String) -> Void)? = nil) async -> LimitReport {
        var steps: [ModelProbe.Step] = []
        var context = context
        if let why = unavailableReason() {
            return LimitReport(steps: [.init(kind: .availability, name: "the model is there", ok: false, detail: why, seconds: 0)], context: context)
        }
        let row = "Transcribe this row:\nRow 1: 3 A, 2 B"
        // One session, turned over on the same budget the reader uses, so what is measured is the
        // request rate and not the transcript filling up.
        var session: LanguageModelSession? = nil
        var used = 0
        func small() async throws {
            if session == nil || used >= ReaderSession<Int>.requestBudget {
                session = makeSession(instructions: rowInstructionsInUse)
                used = 0
            }
            _ = try await session!.respond(to: row, generating: WrittenRowOut.self).content
            used += 1
        }

        // How many small requests in a row the model will answer.
        let burstStarted = Date()
        var answered = 0
        var refusal: String? = nil
        for i in 1...Self.burstLimit {
            progress?("request \(i) of \(Self.burstLimit)")
            do { try await small() } catch {
                refusal = ProseReader.failureText(error)
                session = nil
                break
            }
            answered += 1
            if Task.isCancelled { break }
        }
        let burstSeconds = Date().timeIntervalSince(burstStarted)
        steps.append(.init(
            kind: .burst, name: "small requests one after another", ok: refusal == nil,
            detail: refusal == nil
                ? "\(answered) answered, none refused"
                : "\(answered) answered, then refused (\(refusal!))",
            seconds: burstSeconds))
        context.append(answered > 0 ? String(format: "about %.1f s a request", burstSeconds / Double(answered)) : "no request answered")

        // One prompt the size the front-matter read sends, then a small one straight after: if
        // that alone brings the refusal on, the rows were never the problem.
        if !Task.isCancelled {
            progress?("one 5000-character prompt")
            let bigStarted = Date()
            let filler = String(repeating: Self.grammarExamples + "\n", count: 12).prefix(5000)
            var detail = ""
            var ok = true
            do {
                _ = try await makeSession(instructions: Self.frontProbeInstructions)
                    .respond(to: "Read this page:\n" + filler, generating: FrontOut.self).content
                detail = "the large prompt answered, "
            } catch {
                detail = "the large prompt was refused (\(ProseReader.failureText(error))), "
                ok = false
            }
            do {
                session = nil
                try await small()
                detail += "the small one after it answered"
            } catch {
                detail += "the small one after it was refused (\(ProseReader.failureText(error)))"
                ok = false
            }
            steps.append(.init(kind: .bigPrompt, name: "a 5000-character prompt, then a small one", ok: ok,
                               detail: detail, seconds: Date().timeIntervalSince(bigStarted)))
        }

        // How long a refusal lasts, asked only once something has actually been refused.
        if steps.contains(where: { !$0.ok }), !Task.isCancelled {
            let recoveryStarted = Date()
            var cleared: Int? = nil
            var last = ""
            for wait in Self.recoveryWaits {
                progress?("waiting \(wait) s to see whether it clears")
                try? await Task.sleep(for: .seconds(wait))
                if Task.isCancelled { break }
                session = nil
                do {
                    try await small()
                    cleared = wait
                    break
                } catch { last = ProseReader.failureText(error) }
            }
            steps.append(.init(
                kind: .recovery, name: "waiting after a refusal", ok: cleared != nil,
                detail: cleared.map { "answered again after \($0) s" } ?? "still refused after \(Self.recoveryWaits.last ?? 0) s (\(last))",
                seconds: Date().timeIntervalSince(recoveryStarted)))
        }
        return LimitReport(steps: steps, context: context)
    }
}

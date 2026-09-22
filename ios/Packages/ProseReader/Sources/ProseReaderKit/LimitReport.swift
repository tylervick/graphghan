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

    /// What the measurement shows. The order the phases run in is what makes these readable:
    /// the large prompt goes first, on a budget nothing has spent, and the burst is counted only
    /// from a state known to be answering.
    public var finding: String {
        if let unavailable = step(.availability), !unavailable.ok {
            return "There is no model to ask on this iPhone, so nothing was measured."
        }
        let big = step(.bigPrompt)
        let burst = step(.burst)
        let recovery = step(.recovery)
        if big?.ok == true, burst?.ok == true, recovery == nil {
            return "Nothing was refused: neither one large prompt on an untouched budget nor a run of small requests after it. Whatever the check trips is not reproduced here, so the pattern's own text is the next thing to look at rather than the pace."
        }
        var said: [String] = []
        if let big {
            if big.detail.contains("does not fit the window") {
                said.append("a 5000-character prompt does not fit the on-device window at all, so the front-matter read was never a limit to pace against but a prompt to make smaller (#178)")
            } else {
                said.append(big.ok
                    ? "one 5000-character prompt of the kind the front-matter read sends did not bring the refusal on by itself"
                    : "one 5000-character prompt of the kind the front-matter read sends was enough on its own, on a budget nothing had spent, to bring the refusal on, which puts the front-matter read (#178) ahead of the rows")
            }
        }
        if let burst {
            said.append(burst.ok
                ? "a run of small requests was not refused"
                : "small requests one after another are refused after a few, so the limit counts requests or the tokens in them and the reader has to be paced to it")
        } else {
            said.append("the burst was not counted, because the refusal never cleared and a count taken while refused would mean nothing")
        }
        if let recovery {
            said.append(recovery.ok
                ? "a refusal clears on its own after a wait, so the waits the reader already has are the right shape and only too short"
                : "a refusal had not cleared after the longest wait tried, so waiting is not the answer and the request rate has to come down")
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
    /// What is left between the large prompt and the burst when nothing was refused, so the
    /// count that follows is the limit's and not the two requests just before it.
    public static let settleSeconds = 15

    /// Measures what this phone will take, in the order that keeps the answers readable:
    ///
    /// 1. one prompt the size the front-matter read sends, on a budget nothing has spent, so a
    ///    refusal there is the prompt's own doing and not the leftovers of something else;
    /// 2. a wait, whenever something has just been refused, both to measure how long a refusal
    ///    lasts and to get back to a state worth counting from;
    /// 3. the same small request over and over, counted only from that known-good state.
    ///
    /// Takes a few minutes on a device and nothing at all where there is no model to ask.
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
        /// Waits until a small request answers again, recording how long was waited in total
        /// rather than how long the last wait was. Answers whether it cleared.
        func recover() async -> Bool {
            let started = Date()
            var waited = 0
            var last = ""
            for wait in Self.recoveryWaits {
                progress?("waiting \(wait) s to see whether it clears")
                try? await Task.sleep(for: .seconds(wait))
                waited += wait
                if Task.isCancelled { break }
                session = nil
                do {
                    try await small()
                    steps.append(.init(kind: .recovery, name: "waiting after a refusal", ok: true,
                                       detail: "answered again after \(waited) s of waiting in all",
                                       seconds: Date().timeIntervalSince(started)))
                    return true
                } catch { last = ProseReader.failureText(error) }
            }
            steps.append(.init(kind: .recovery, name: "waiting after a refusal", ok: false,
                               detail: "still refused after \(waited) s of waiting in all (\(last))",
                               seconds: Date().timeIntervalSince(started)))
            return false
        }

        // 1. The front-matter shape, first, while nothing has spent any of the budget.
        progress?("one 5000-character prompt")
        let bigStarted = Date()
        let filler = String(repeating: Self.grammarExamples + "\n", count: 12).prefix(5000)
        var detail = ""
        var bigOK = true
        // A prompt too big for the window is not a refusal and must not be counted as one: it is
        // the prompt's own size, it will happen every time, and no amount of waiting or pacing
        // touches it. #176 found exactly that -- 4124 tokens against a 4096 limit.
        var bigTooLarge = false
        do {
            _ = try await makeSession(instructions: Self.frontProbeInstructions)
                .respond(to: "Read this page:\n" + filler, generating: FrontOut.self).content
            detail = "the large prompt answered, "
        } catch {
            bigTooLarge = ProseReader.isContextFull(error)
            detail = bigTooLarge
                ? "the large prompt does not fit the window at all (\(String(describing: error).prefix(120))), "
                : "the large prompt was refused (\(ProseReader.failureText(error))), "
            bigOK = false
        }
        var smallAfterBigAnswered = false
        do {
            session = nil
            try await small()
            detail += "the small one after it answered"
            smallAfterBigAnswered = true
        } catch {
            detail += "the small one after it was refused (\(ProseReader.failureText(error)))"
            bigOK = false
        }
        steps.append(.init(kind: .bigPrompt, name: "a 5000-character prompt, then a small one", ok: bigOK,
                           detail: detail, seconds: Date().timeIntervalSince(bigStarted)))

        // 2. Back to a state worth counting from, and how long that took. A prompt that did not
        //    fit is nothing to recover from, so the burst follows it straight away.
        var ready = bigOK || (bigTooLarge && smallAfterBigAnswered)
        if !ready, !Task.isCancelled { ready = await recover() }

        // 3. The burst, only from there. A count taken while the model is still refusing would
        //    measure the refusal, not the limit.
        guard ready, !Task.isCancelled else { return LimitReport(steps: steps, context: context) }
        if bigOK {
            // Two requests have just gone out; let the budget settle so the count is the limit's
            // and not theirs.
            progress?("settling for \(Self.settleSeconds) s before counting")
            try? await Task.sleep(for: .seconds(Self.settleSeconds))
        }
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
        if answered > 0 { context.append(String(format: "about %.1f s a request", burstSeconds / Double(answered))) }

        // The recovery time, if the burst is the first thing that has been refused.
        if refusal != nil, !steps.contains(where: { $0.kind == .recovery }), !Task.isCancelled {
            _ = await recover()
        }
        return LimitReport(steps: steps, context: context)
    }
}

import Foundation
import FoundationModels
import Testing

@testable import ProseReaderKit

/// The retry and the session turnover the phone needs (#176), with a counter standing in for the
/// model: the loop is exactly the one `ProseReader` runs, and no model is involved.
@Suite struct ReaderSessionTests {
    struct Busy: Error {}
    struct ContextFull: Error {}
    struct Refused: Error {}

    /// The waits a run would have slept, recorded instead.
    final class Waits: @unchecked Sendable {
        var slept: [Duration] = []
    }

    func holder(reuse: Bool = true, waits: Waits) -> ReaderSession<Int> {
        var next = 0
        return ReaderSession<Int>(
            reuse: reuse,
            isBusy: { $0 is Busy },
            isContextFull: { $0 is ContextFull },
            sleep: { waits.slept.append($0) },
            make: {
                next += 1
                return next
            })
    }

    @Test func oneSessionAnswersManyRequestsAndIsTurnedOverBeforeItFills() async throws {
        var session = holder(waits: Waits())
        var sessions: [Int] = []
        for _ in 0..<(ReaderSession<Int>.requestBudget * 2) { sessions.append(try await session.answer { $0 }) }
        // One session for the budget, then the next: not one a request, which is the change #176 asks for.
        #expect(sessions.prefix(ReaderSession<Int>.requestBudget).allSatisfy { $0 == 1 })
        #expect(sessions.dropFirst(ReaderSession<Int>.requestBudget).allSatisfy { $0 == 2 })
        #expect(session.sessionsMade == 2)
    }

    @Test func withoutReuseEveryRequestGetsItsOwnSession() async throws {
        var session = holder(reuse: false, waits: Waits())
        var sessions: [Int] = []
        for _ in 0..<3 { sessions.append(try await session.answer { $0 }) }
        #expect(sessions == [1, 2, 3])
    }

    @Test func aBusyRefusalIsWaitedOutAndAskedAgain() async throws {
        let waits = Waits()
        var session = holder(waits: waits)
        var tries = 0
        let got: String = try await session.answer { _ in
            tries += 1
            if tries == 1 { throw Busy() }
            return "read"
        }
        #expect(got == "read")
        #expect(tries == 2)
        #expect(waits.slept == [ReaderSession<Int>.waits[0]])
        #expect(session.busyRun == 0)
    }

    @Test func threeAttemptsInAllBeforeABusyRequestGivesUp() async throws {
        let waits = Waits()
        var session = holder(waits: waits)
        var tries = 0
        await #expect(throws: Busy.self) {
            try await session.answer { _ -> String in
                tries += 1
                throw Busy()
            }
        }
        #expect(tries == 3)
        #expect(waits.slept == ReaderSession<Int>.waits)
        #expect(session.busyRun == 1)
    }

    @Test func onceTheModelHasRefusedSeveralRequestsRunningTheWaitingStops() async throws {
        let waits = Waits()
        var session = holder(waits: waits)
        for _ in 0..<ReaderSession<Int>.patience {
            await #expect(throws: Busy.self) { try await session.answer { _ -> String in throw Busy() } }
        }
        let paid = waits.slept.count
        #expect(paid == ReaderSession<Int>.patience * ReaderSession<Int>.waits.count)
        // A phone whose model will not answer must not cost a 310-row check an hour of waiting.
        var tries = 0
        await #expect(throws: Busy.self) {
            try await session.answer { _ -> String in
                tries += 1
                throw Busy()
            }
        }
        #expect(tries == 1)
        #expect(waits.slept.count == paid)
    }

    @Test func aRequestThatAnswersClearsTheRunOfRefusals() async throws {
        let waits = Waits()
        var session = holder(waits: waits)
        for _ in 0..<ReaderSession<Int>.patience {
            await #expect(throws: Busy.self) { try await session.answer { _ -> String in throw Busy() } }
        }
        _ = try await session.answer { _ in "read" }
        #expect(session.busyRun == 0)
        var tries = 0
        await #expect(throws: Busy.self) {
            try await session.answer { _ -> String in
                tries += 1
                throw Busy()
            }
        }
        #expect(tries == 3)  // the patience is spent again, not spent for good
    }

    @Test func aFullWindowIsCuredByAFreshSessionRatherThanAWait() async throws {
        let waits = Waits()
        var session = holder(waits: waits)
        var seen: [Int] = []
        let got: String = try await session.answer { s in
            seen.append(s)
            if seen.count == 1 { throw ContextFull() }
            return "read"
        }
        #expect(got == "read")
        #expect(seen == [1, 2])
        #expect(waits.slept.isEmpty)
    }

    @Test func aFullWindowIsRetriedOnlyOnce() async throws {
        var session = holder(waits: Waits())
        var tries = 0
        await #expect(throws: ContextFull.self) {
            try await session.answer { _ -> String in
                tries += 1
                throw ContextFull()
            }
        }
        #expect(tries == 2)
    }

    @Test func anyOtherRefusalIsHandedStraightBack() async throws {
        let waits = Waits()
        var session = holder(waits: waits)
        var tries = 0
        await #expect(throws: Refused.self) {
            try await session.answer { _ -> String in
                tries += 1
                throw Refused()
            }
        }
        #expect(tries == 1)
        #expect(waits.slept.isEmpty)
        #expect(session.busyRun == 0)
    }

    @Test func aSessionThatThrewIsNeverAskedTwice() async throws {
        var session = holder(waits: Waits())
        var seen: [Int] = []
        await #expect(throws: Refused.self) { try await session.answer { _ -> String in throw Refused() } }
        _ = try await session.answer { s -> String in
            seen.append(s)
            return "read"
        }
        #expect(seen == [2])
    }
}

/// What the reader counts as "the model is busy" and what it does not (#176). The typed case is
/// how it is decided on the devices the app ships to; the text is a fallback for an iOS 27
/// device, whose `LanguageModelError` CI's iOS 26 SDK cannot name.
@Suite struct ModelErrorTests {
    struct Spelled: Error, CustomStringConvertible {
        let description: String
    }

    @Test func theRateLimitCaseIsBusyAndItsNeighboursAreNot() {
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "Request has been rate limited.")
        #expect(ProseReader.isBusy(LanguageModelSession.GenerationError.rateLimited(context)))
        // The context text says "rate limited" on both of these on purpose: a type this SDK
        // names is decided by its case, never by its prose.
        #expect(!ProseReader.isBusy(LanguageModelSession.GenerationError.guardrailViolation(context)))
        #expect(!ProseReader.isBusy(LanguageModelSession.GenerationError.decodingFailure(context)))
        #expect(ProseReader.isContextFull(LanguageModelSession.GenerationError.exceededContextWindowSize(context)))
        #expect(!ProseReader.isContextFull(LanguageModelSession.GenerationError.rateLimited(context)))
    }

    /// Both spellings the framework uses -- the Swift case and the bridged sentence -- are the
    /// one word once the spaces are gone, which is what the fallback looks for.
    @Test func eitherSpellingOfARateLimitIsRecognised() {
        #expect(ProseReader.isBusy(Spelled(description: "rateLimited(Context(debugDescription: \"…\"))")))
        #expect(ProseReader.isBusy(Spelled(description: "Error Domain=… Request has been rate limited. Please try again later.")))
        #expect(ProseReader.isContextFull(Spelled(description: "exceededContextWindowSize(…)")))
        #expect(ProseReader.isContextFull(Spelled(description: "the context window is full")))
        #expect(!ProseReader.isBusy(Spelled(description: "the network rate is limited")))
        #expect(!ProseReader.isBusy(Spelled(description: "guardrailViolation(…)")))
        // Anchored, so a neighbouring word that merely contains the spelling is not swept in.
        #expect(!ProseReader.isBusy(Spelled(description: "notRateLimited(…)")))
        #expect(!ProseReader.isBusy(Spelled(description: "the request was not rate limitedly handled")))
        #expect(!ProseReader.isContextFull(Spelled(description: "notExceededContextWindowSize(…)")))
    }

    @Test func aBusyRowCarriesTheWordsTheAppMatchesAndAnyOtherKeepsItsOwn() {
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "Request has been rate limited.")
        #expect(ProseReader.failureText(LanguageModelSession.GenerationError.rateLimited(context)) == ReaderFailure.modelBusy)
        #expect(ProseReader.failureText(Spelled(description: "no colour named")) == "no colour named")
    }
}

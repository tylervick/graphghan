// The session a reading loop talks to: made once, reused, turned over before it fills, and asked
// again when the model says it is busy (#176).

import Foundation

/// One model session and the rules for keeping it usable. Generic in the session so the whole
/// loop can be exercised without a model: `ProseReader` binds `Session` to `LanguageModelSession`,
/// and `ReaderSessionTests` binds it to a counter.
///
/// Three things happen here, all of them #176's:
/// - a request the model refuses as busy is waited out and asked again, up to three attempts;
/// - one session answers many requests, instead of one session per row, which is what a phone
///   counts when it decides an app is asking too often;
/// - that session is turned over before the transcript fills the window, and at once if it ever
///   reports it has.
struct ReaderSession<Session> {
    /// Requests one session answers before a fresh one is made. The on-device window holds about
    /// 4k tokens and every answer stays in the transcript, so a reused session has to be turned
    /// over or a pattern of any length runs out of room part way down the page.
    static var requestBudget: Int { 16 }
    /// What a refused request waits before each further attempt: two waits, so three attempts.
    static var waits: [Duration] { [.seconds(2), .seconds(8)] }
    /// Requests refused one after another before the reader stops waiting at all. A phone whose
    /// model will not answer today then costs a 310-row check seconds rather than an hour.
    static var patience: Int { 3 }

    private let make: () -> Session
    private let reuse: Bool
    private let isBusy: (any Error) -> Bool
    private let isContextFull: (any Error) -> Bool
    private let sleep: (Duration) async throws -> Void

    private var session: Session?
    /// Requests the current session has answered.
    private(set) var used = 0
    /// Requests given up on for a busy model since the last one that answered.
    private(set) var busyRun = 0
    /// Sessions made so far, for the measurements and the tests.
    private(set) var sessionsMade = 0

    init(reuse: Bool,
         isBusy: @escaping (any Error) -> Bool,
         isContextFull: @escaping (any Error) -> Bool = { _ in false },
         sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         make: @escaping () -> Session) {
        self.reuse = reuse
        self.isBusy = isBusy
        self.isContextFull = isContextFull
        self.sleep = sleep
        self.make = make
    }

    /// Drops the session, so the next request starts a new one. What the reading loop does when a
    /// request failed for a reason this type does not handle.
    mutating func discard() {
        session = nil
        used = 0
    }

    /// Asks `respond` on a session, with the retries and the turnover above. The error of the last
    /// attempt is thrown when they are all used up.
    mutating func answer<T: Sendable>(_ respond: (Session) async throws -> T) async throws -> T {
        var attempt = 0
        var remade = false
        while true {
            if session == nil || !reuse || used >= Self.requestBudget {
                session = make()
                used = 0
                sessionsMade += 1
            }
            do {
                let got = try await respond(session!)
                used += 1
                busyRun = 0
                return got
            } catch {
                discard()  // a session that threw is never asked twice
                // A full window is not a refusal: the same request on a fresh session is the fix,
                // and it is worth exactly one more go.
                if isContextFull(error), !remade {
                    remade = true
                    continue
                }
                guard isBusy(error) else { throw error }
                guard busyRun < Self.patience, attempt < Self.waits.count else {
                    busyRun += 1
                    throw error
                }
                try? await sleep(Self.waits[attempt])
                if Task.isCancelled {  // Cancel during a wait ends the request, not the whole read
                    busyRun += 1
                    throw error
                }
                attempt += 1
            }
        }
    }
}

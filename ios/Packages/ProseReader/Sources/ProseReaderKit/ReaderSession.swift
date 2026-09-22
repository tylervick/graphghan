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
    /// Requests one session answers before a fresh one is made. Measured on the phone, not
    /// guessed: a burst of the reader's own row requests on one session overflowed the window at
    /// the tenth, "4127 tokens ... exceeds the maximum allowed context size of 4096" (#176).
    /// What made it grow that fast was the `@Generable` schema going in with every request;
    /// `includeSchemaInPrompt` now sends it once a session, as Apple's guidance says to when the
    /// model has already seen it, so the same window holds several times as many requests.
    /// Twelve is deliberately below what that allows: the next burst measures the new ceiling,
    /// and overflowing is handled anyway, so this is an optimisation and not a correctness rule.
    static var requestBudget: Int { 12 }
    /// What a refused request waits before each further attempt: two waits, so three attempts.
    static var waits: [Duration] { [.seconds(2), .seconds(8)] }
    /// Requests refused one after another before the reader stops waiting at all. A phone whose
    /// model will not answer today then costs a 310-row check seconds rather than an hour.
    static var patience: Int { 3 }

    private let make: () -> Session
    /// Run once on each new session, before it is asked anything: `ProseReader` prewarms.
    private let prepare: (Session) -> Void
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
         prepare: @escaping (Session) -> Void = { _ in },
         make: @escaping () -> Session) {
        self.prepare = prepare
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
    /// `respond` is handed the session and whether it has answered nothing yet, which is what
    /// decides `includeSchemaInPrompt`: Apple's guidance is to send the schema once and leave it
    /// out of later requests the same session has already seen it in.
    mutating func answer<T: Sendable>(_ respond: (Session, _ isFirstOnSession: Bool) async throws -> T) async throws -> T {
        var attempt = 0
        var remade = false
        while true {
            if session == nil || !reuse || used >= Self.requestBudget {
                session = make()
                prepare(session!)
                used = 0
                sessionsMade += 1
            }
            do {
                let got = try await respond(session!, used == 0)
                used += 1
                busyRun = 0
                return got
            } catch {
                let hadTranscript = used > 0
                discard()  // a session that threw is never asked twice
                // A full window on a session that had already answered is the transcript's
                // doing, and a fresh session is the fix. On a session that had answered nothing
                // it is the prompt's own size, and asking again changes nothing: the caller has
                // to send less, which is what the front-matter read now does (#176).
                if isContextFull(error), hadTranscript, !remade {
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

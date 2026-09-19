import AppIntents
import GraphghanCore

/// What Siri says back (App Intents spec §3.4): where the cursor landed, because a maker who cannot
/// see the screen has no other confirmation that the count moved. Pure, so every sentence is a
/// value test.
///
/// Runs are numbered from one in words, as the Work screen numbers them. The stitch component of
/// the cursor is why two of the sentences differ: with a count step of ten inside a twenty-stitch
/// fill, one Done leaves the maker mid-run, and a reply that said "run 3" twice running would read
/// as a Done that did not register.
enum WorkIntentDialog {
    struct Text: Equatable {
        /// The spoken form, a sentence.
        let full: String
        /// The glanceable form; the same as `full` where the spec draws no distinction.
        let supporting: String
        init(_ full: String, supporting: String? = nil) { self.full = full; self.supporting = supporting ?? full }
    }

    static func text(for outcome: WorkIntentOutcome) -> Text {
        switch outcome {
        case .noProject:
            return Text("You don't have a project going.")
        case .chartUnavailable(let title):
            return Text("Couldn't open the chart for \(title).")
        case .nowhereToGo(.back):
            return Text("You're at the beginning.")
        case .nowhereToGo:
            return Text("You've already finished this one.")
        case .ambiguous(let candidates):
            return Text(questionText(candidates))
        case .moved(let landing):
            return text(for: landing.step, in: landing.sequence)
        }
    }

    static func dialog(for outcome: WorkIntentOutcome) -> IntentDialog {
        let t = text(for: outcome)
        return t.supporting == t.full ? IntentDialog("\(t.full)") : IntentDialog(full: "\(t.full)", supporting: "\(t.supporting)")
    }

    /// Spec §4.3: the question the intent asks when the working project is ambiguous, naming the
    /// blankets so the maker can answer with one of them.
    static func question(_ candidates: [ProjectSnapshot]) -> IntentDialog {
        IntentDialog("\(questionText(candidates))")
    }

    static func questionText(_ candidates: [ProjectSnapshot]) -> String {
        let titles = candidates.map(\.title)
        let list: String
        switch titles.count {
        case 0: list = "which one"
        case 1: list = titles[0]
        case 2: list = "\(titles[0]) or \(titles[1])"
        default: list = titles.dropLast().joined(separator: ", ") + ", or " + titles[titles.count - 1]
        }
        return "Which blanket — \(list)?"
    }

    static func text(for step: WorkStep, in sequence: WorkSequence) -> Text {
        if step.finished { return Text("That's the last one. The blanket is done.") }
        let c = step.cursor
        guard let pass = sequence.pass(at: c.row), c.run < pass.runs.count else {
            // The boundary position: the row is worked and the turn is the next step. This is where
            // the turn is said, not on the row that follows it -- by then the maker has turned.
            return Text("End of row \(c.row). Turn.", supporting: "Row \(c.row), turn")
        }
        let place = "Row \(c.row), run \(c.run + 1)"
        if c.stitch > 0 {
            return Text("\(place), \(spelled(pass.runs[c.run].count - c.stitch)) left in it.", supporting: place)
        }
        return Text("\(place) of \(pass.runs.count).")
    }

    /// Small counts read better spoken as words ("eight left in it"); larger ones stay digits.
    static func spelled(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                     "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"]
        return words.indices.contains(n) ? words[n] : "\(n)"
    }
}

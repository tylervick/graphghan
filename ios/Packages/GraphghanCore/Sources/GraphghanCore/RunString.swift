/// The run-string encoding: a row is `(\d+[A-Za-z]{1,3})+`, e.g. `12C3K5C`. A run always starts
/// with digits, so `7YB` is one run of code `YB`.
public enum RunString {
    public static let codeMaxLength = 3

    /// The runs in order, or nil when the string is not a run string.
    public static func parse(_ s: String) -> [(code: String, count: Int)]? {
        var runs: [(code: String, count: Int)] = []
        var count = 0
        var digits = 0
        var code = ""
        for ch in s.unicodeScalars {
            if ch.value >= 0x30 && ch.value <= 0x39 {
                if !code.isEmpty {  // a new run begins: flush the previous one
                    runs.append((code, count))
                    count = 0; digits = 0; code = ""
                }
                let (scaled, mulOverflow) = count.multipliedReportingOverflow(by: 10)
                let (next, addOverflow) = scaled.addingReportingOverflow(Int(ch.value - 0x30))
                guard !mulOverflow, !addOverflow else { return nil }
                count = next
                digits += 1
            } else if (ch.value >= 0x41 && ch.value <= 0x5A) || (ch.value >= 0x61 && ch.value <= 0x7A) {
                guard digits > 0, code.count < codeMaxLength else { return nil }
                code.unicodeScalars.append(ch)
            } else {
                return nil
            }
        }
        guard digits > 0, !code.isEmpty else { return nil }
        runs.append((code, count))
        return runs
    }

    public static func isValidCode(_ code: String) -> Bool {
        (1...codeMaxLength).contains(code.count) && code.unicodeScalars.allSatisfy {
            ($0.value >= 0x41 && $0.value <= 0x5A) || ($0.value >= 0x61 && $0.value <= 0x7A)
        }
    }
}

import Foundation

/// Tiny argv parser used by every subcommand. Not a full ArgumentParser replacement —
/// just enough for `--flag value` and `--bool` patterns plus positional args.
struct Args {
    private var flags: [String: String] = [:]
    private var bools: Set<String> = []
    private var positional: [String] = []

    init(_ argv: [String]) {
        var i = 0
        while i < argv.count {
            let token = argv[i]
            if token.hasPrefix("--") {
                let key = String(token.dropFirst(2))
                if i + 1 < argv.count, !argv[i + 1].hasPrefix("--") {
                    flags[key] = argv[i + 1]
                    i += 2
                } else {
                    bools.insert(key)
                    i += 1
                }
            } else if token == "-h" {
                bools.insert("help"); i += 1
            } else {
                positional.append(token)
                i += 1
            }
        }
    }

    func has(_ key: String) -> Bool { bools.contains(key) || flags[key] != nil }

    func string(_ key: String) -> String? { flags[key] }
    func string(_ key: String, default fallback: String) -> String { flags[key] ?? fallback }
    func required(_ key: String) throws -> String {
        if let v = flags[key] { return v }
        throw CLIError.usage("missing --\(key)")
    }
    func int(_ key: String) throws -> Int? {
        guard let s = flags[key] else { return nil }
        guard let v = Int(s) else { throw CLIError.usage("--\(key) expects integer, got '\(s)'") }
        return v
    }
    func double(_ key: String) throws -> Double? {
        guard let s = flags[key] else { return nil }
        guard let v = Double(s) else { throw CLIError.usage("--\(key) expects number, got '\(s)'") }
        return v
    }
    func bool(_ key: String) -> Bool { bools.contains(key) || (flags[key]?.lowercased() == "true") }
    func boolValue(_ key: String) throws -> Bool? {
        if bools.contains(key) { return true }
        guard let s = flags[key]?.lowercased() else { return nil }
        switch s {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: throw CLIError.usage("--\(key) expects true/false, got '\(s)'")
        }
    }
    var positionals: [String] { positional }
    var helpRequested: Bool { bools.contains("help") }
}

enum CLIError: Error, LocalizedError {
    case usage(String)
    var errorDescription: String? {
        if case .usage(let s) = self { return s }
        return nil
    }
}

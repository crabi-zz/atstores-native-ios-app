import Foundation

/// The backend is loose about key names and types (numbers as strings, alternate keys,
/// arrays wrapped in `data`/`content`/...). The Android app relied on Gson's leniency;
/// here we read raw JSON dictionaries with tolerant accessors instead of strict Codable.
typealias JSONDict = [String: Any]

nonisolated enum JSON {
    static func parse(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// Returns the list of objects from either a top-level array or a wrapper object.
    static func objects(from any: Any?, preferredKeys: [String] = ["data", "content", "list"]) -> [JSONDict] {
        if let arr = any as? [Any] { return arr.compactMap { $0 as? JSONDict } }
        if let obj = any as? JSONDict {
            for key in preferredKeys {
                if let arr = obj[key] as? [Any] { return arr.compactMap { $0 as? JSONDict } }
            }
            for (_, value) in obj {
                if let arr = value as? [Any] { return arr.compactMap { $0 as? JSONDict } }
            }
        }
        return []
    }

    static func data(_ object: Any) -> Data? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object)
    }
}

nonisolated extension Dictionary where Key == String, Value == Any {
    private func first(_ keys: [String]) -> Any? {
        for key in keys {
            if let value = self[key], !(value is NSNull) { return value }
        }
        return nil
    }

    func str(_ keys: String...) -> String? {
        for key in keys {
            guard let value = self[key], !(value is NSNull) else { continue }
            if let s = value as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty, t.lowercased() != "null" { return s }
            } else if let n = value as? NSNumber {
                return n.stringValue
            }
        }
        return nil
    }

    func double(_ keys: String...) -> Double {
        for key in keys {
            guard let value = self[key], !(value is NSNull) else { continue }
            if let n = value as? NSNumber { return n.doubleValue }
            if let s = value as? String, let d = Double(s.trimmingCharacters(in: .whitespaces)) { return d }
        }
        return 0
    }

    func int(_ keys: String...) -> Int {
        for key in keys {
            guard let value = self[key], !(value is NSNull) else { continue }
            if let n = value as? NSNumber { return n.intValue }
            if let s = value as? String, let d = Double(s.trimmingCharacters(in: .whitespaces)) { return Int(d) }
        }
        return 0
    }

    func bool(_ keys: String...) -> Bool? {
        for key in keys {
            guard let value = self[key], !(value is NSNull) else { continue }
            if let n = value as? NSNumber { return n.boolValue }
            if let s = value as? String {
                switch s.lowercased() {
                case "true", "1", "yes": return true
                case "false", "0", "no": return false
                default: continue
                }
            }
        }
        return nil
    }

    func dict(_ keys: String...) -> JSONDict? {
        first(keys) as? JSONDict
    }

    func dicts(_ keys: String...) -> [JSONDict] {
        (first(keys) as? [Any])?.compactMap { $0 as? JSONDict } ?? []
    }

    /// Accepts a JSON array, or a string like `["a","b"]` / `a, b`.
    func strings(_ keys: String...) -> [String] {
        guard let value = first(keys) else { return [] }
        return JSON.stringList(value)
    }
}

nonisolated extension JSON {
    static func stringList(_ value: Any?) -> [String] {
        func clean(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        if let arr = value as? [Any] {
            return arr.compactMap { item -> String? in
                if let s = item as? String { return clean(s) }
                if let n = item as? NSNumber { return n.stringValue }
                if let d = item as? JSONDict { return d.str("name", "serviceName") }
                return nil
            }.filter { !$0.isEmpty && $0.lowercased() != "null" }
        }
        if var s = value as? String {
            s = s.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("["), s.hasSuffix("]") { s = String(s.dropFirst().dropLast()) }
            return s.split(separator: ",").map { clean(String($0)) }.filter { !$0.isEmpty && $0.lowercased() != "null" }
        }
        return []
    }
}

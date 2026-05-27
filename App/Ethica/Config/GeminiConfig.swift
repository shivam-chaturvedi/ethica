//
//  GeminiConfig.swift
//  Ethica
//
//  Loads Gemini API credentials from bundled env files only.
//

import Foundation

enum GeminiConfig {
    /// API key from GEMINI_API_KEY — required for on-device Plate Check and Take Photo.
    static var apiKey: String? {
        EnvConfig.value("GEMINI_API_KEY")
    }

    static var model: String {
        if let m = EnvConfig.value("GEMINI_MODEL"), !m.isEmpty { return m }
        return "gemini-2.5-flash-lite"
    }

    static var isConfigured: Bool { apiKey != nil }

    static var missingKeyMessage: String {
        """
        Gemini API key not configured.

        1. Create a repo root `.env` file and set `GEMINI_API_KEY`
        2. Add the repo root `.env` file to the Ethica target (Copy Bundle Resources)

        Get a key: https://aistudio.google.com/apikey
        """
    }
}

// MARK: - Bundled .env loader (single source of truth)

enum EnvConfig {
    /// Ordered list of env resources to load and merge (later overrides earlier).
    ///
    /// Supported resource formats:
    /// - `Name.env`
    /// - `Name` (no extension)
    private static let resourceNamesInOrder: [String] = [".env"]

    private static let cached: [String: String] = {
        var merged: [String: String] = [:]
        for name in resourceNamesInOrder {
            for url in urlsForResource(named: name) {
                for (k, v) in parseEnvFile(at: url) {
                    merged[k] = v
                }
            }
        }
        return merged
    }()

    static func value(_ key: String) -> String? {
        let raw = cached[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    #if DEBUG
    static func debugReport() -> String {
        let keys = ["SUPABASE_URL", "SUPABASE_ANON_KEY", "GEMINI_API_KEY", "GEMINI_MODEL"]
        let foundFiles = resourceNamesInOrder.flatMap { urlsForResource(named: $0) }.map { $0.lastPathComponent }
        let loadedKeys = keys.map { "\($0)=\((value($0) ?? "").isEmpty ? "<missing>" : "<set>")" }.joined(separator: ", ")
        return "EnvConfig: files=\(foundFiles.isEmpty ? "<none>" : foundFiles.joined(separator: "|")), \(loadedKeys)"
    }
    #endif

    // MARK: - Private

    private static func urlsForResource(named name: String) -> [URL] {
        // Xcode can be inconsistent with dotfiles like ".env" when copying bundle resources.
        // We support multiple lookup strategies to ensure the single env file is found.
        var urls: [URL] = []

        // 1) Direct lookup by name + extension.
        if let url = Bundle.main.url(forResource: name, withExtension: "env") {
            urls.append(url)
        }

        // 2) Direct lookup by name with no extension.
        if let url = Bundle.main.url(forResource: name, withExtension: nil) {
            urls.append(url)
        }

        // 3) Dotfile fallback: if the resource is copied as "env" (without the leading dot),
        // try common variants when requested ".env".
        if name == ".env" {
            if let url = Bundle.main.url(forResource: "env", withExtension: nil) {
                urls.append(url)
            }
            if let url = Bundle.main.url(forResource: "env", withExtension: "env") {
                urls.append(url)
            }
        }

        // 4) As a last resort, scan bundle resource URLs for an exact filename match.
        // This is cached (static) so it only happens once.
        if urls.isEmpty,
           let all = Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: nil) {
            let matches = all.filter { $0.lastPathComponent == name || (name == ".env" && $0.lastPathComponent == "env") }
            urls.append(contentsOf: matches)
        }

        // De-dupe while preserving order.
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    private static func parseEnvFile(at url: URL) -> [String: String] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let k = String(trimmed[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            var v = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
                v = String(v.dropFirst().dropLast())
            }
            result[k] = v
        }
        return result
    }
}

enum SupabaseConfig {
    static var url: URL? {
        guard let raw = EnvConfig.value("SUPABASE_URL") else { return nil }
        return URL(string: raw)
    }

    static var anonKey: String? {
        EnvConfig.value("SUPABASE_ANON_KEY")
    }

    static var isConfigured: Bool {
        #if DEBUG
        if url == nil || (anonKey?.isEmpty != false) {
            AppLogger.debug(EnvConfig.debugReport())
        }
        #endif
        return url != nil && (anonKey?.isEmpty == false)
    }

    static var missingConfigMessage: String {
        """
        Supabase is not configured.

        1) Create a repo root `.env` file and set:
           - SUPABASE_URL
           - SUPABASE_ANON_KEY

        2) Add the repo root `.env` file to the Ethica target (Copy Bundle Resources).
        """
    }
}

//
//  AuthenticationService.swift
//  Ethica
//
//  Supabase Authentication Service
//

import Foundation
import Combine

@MainActor
class AuthenticationService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: AuthUser?
    @Published var authToken: String?

    var currentUserId: String? { currentUser?.id }
    var currentDisplayName: String? { currentUser?.displayName }

    static let shared = AuthenticationService()

    private var session: SupabaseSession? {
        didSet {
            persistSession()
            authToken = session?.accessToken
            currentUser = session.flatMap(Self.userFromSession)
            isAuthenticated = session?.accessToken?.isEmpty == false
        }
    }

    private init() {
        // Restore persisted session (if present)
        session = loadPersistedSession()
    }

    // MARK: - Sign In Methods

    func signInWithEmail(email: String, password: String) async throws {
        guard SupabaseConfig.isConfigured else { throw SupabaseAPIError.notConfigured }
        let newSession = try await SupabaseAPI.shared.signIn(email: email, password: password)
        self.session = newSession
    }

    func signUpWithEmail(email: String, password: String) async throws {
        guard SupabaseConfig.isConfigured else { throw SupabaseAPIError.notConfigured }
        let newSession = try await SupabaseAPI.shared.signUp(email: email, password: password)

        // If Supabase returns a session, we're done.
        if newSession.accessToken?.isEmpty == false {
            self.session = newSession
            return
        }

        // If no session was returned (often when email confirmation is required), attempt a sign-in.
        do {
            let signedInSession = try await SupabaseAPI.shared.signIn(email: email, password: password)
            self.session = signedInSession
        } catch {
            // Preserve the underlying Supabase error in logs, but show a friendly message.
            AppLogger.warning("Signup succeeded but auto sign-in failed: \(error.localizedDescription)")
            throw NSError(
                domain: "AuthError",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Account created. Please verify your email (if required), then sign in."]
            )
        }
    }

    func signInAnonymously() async throws {
        throw NSError(domain: "AuthError", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Anonymous sign-in is not enabled. Please sign in with email."])
    }

    func signInWithGoogle() async throws {
        throw NSError(domain: "AuthError", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Google sign-in is not configured yet for Supabase in this build."])
    }

    // MARK: - Sign Out

    func signOut() throws {
        if let token = session?.accessToken, !token.isEmpty {
            Task { try? await SupabaseAPI.shared.signOut(accessToken: token) }
        }
        session = nil

        // Clear all user-specific caches to prevent data leaking between accounts
        Task {
            await AIResultsCacheService.shared.clearAll()
        }
        HistoryService.shared.clearAllHistory()
        AppLogger.debug("Cleared all caches on sign-out")
    }

    // MARK: - Auth Token Injection

    /// Injects the current Supabase Bearer token into the given request.
    func addAuthToken(to request: inout URLRequest) async {
        if let token = authToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    // MARK: - Account Deletion (Apple Guideline 5.1.1)

    func deleteAccount() async throws {
        guard let userId = currentUserId else {
            throw NSError(domain: "AuthError", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No user signed in"])
        }

        // 1. Delete backend user data
        do {
            try await NetworkService.shared.deleteUserData(userId: userId)
        } catch {
            AppLogger.warning("Backend data deletion failed (continuing): \(error.localizedDescription)")
        }

        // 2. Clear all local data
        HistoryService.shared.clearAllHistory()
        await AIResultsCacheService.shared.clearAll()
        AppLogger.debug("Cleared all local caches for account deletion")

        // 3. Best-effort remote sign out (Supabase user deletion requires server-side admin privileges)
        if let token = authToken, !token.isEmpty {
            try? await SupabaseAPI.shared.signOut(accessToken: token)
        }

        // 4. Clear local session
        session = nil
    }

    // MARK: - Password Reset

    func resetPassword(email: String) async throws {
        guard SupabaseConfig.isConfigured else { throw SupabaseAPIError.notConfigured }
        try await SupabaseAPI.shared.resetPassword(email: email)
    }
}

// MARK: - App-facing User

struct AuthUser: Equatable {
    let id: String
    let email: String?
    let displayName: String?
}

// MARK: - Persistence

private extension AuthenticationService {
    static let sessionDefaultsKey = "supabase.session.v1"

    func persistSession() {
        guard let session else {
            UserDefaults.standard.removeObject(forKey: Self.sessionDefaultsKey)
            return
        }
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: Self.sessionDefaultsKey)
        }
    }

    func loadPersistedSession() -> SupabaseSession? {
        guard let data = UserDefaults.standard.data(forKey: Self.sessionDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(SupabaseSession.self, from: data)
    }

    static func userFromSession(_ session: SupabaseSession) -> AuthUser? {
        guard let user = session.user else { return nil }
        let displayName: String?
        if let v = user.userMetadata?["full_name"], case let .string(name) = v {
            displayName = name
        } else {
            displayName = nil
        }
        return AuthUser(id: user.id, email: user.email, displayName: displayName)
    }
}

// MARK: - Supabase HTTP client (no Firebase dependencies)

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Double.self) { self = .number(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? container.decode([JSONValue].self) { self = .array(v); return }
        throw DecodingError.typeMismatch(
            JSONValue.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(v): try container.encode(v)
        case let .number(v): try container.encode(v)
        case let .bool(v): try container.encode(v)
        case let .object(v): try container.encode(v)
        case let .array(v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}

struct SupabaseUser: Codable {
    let id: String
    let email: String?
    let userMetadata: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case userMetadata = "user_metadata"
    }
}

struct SupabaseSession: Codable {
    let accessToken: String?
    let refreshToken: String?
    let tokenType: String?
    let expiresIn: Int?
    let expiresAt: Int?
    let user: SupabaseUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case user
    }
}

struct SupabaseSignUpResponse: Codable {
    let user: SupabaseUser?
    let session: SupabaseSession?
}

enum SupabaseAPIError: LocalizedError {
    case notConfigured
    case invalidURL
    case httpError(status: Int, message: String?)
    case decodingFailed(details: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return SupabaseConfig.missingConfigMessage
        case .invalidURL:
            return "Supabase URL is invalid."
        case let .httpError(status, message):
            if let message, !message.isEmpty { return message }
            return "Request failed (\(status))."
        case let .decodingFailed(details):
            return "Supabase response decoding failed. \(details)"
        }
    }
}

final class SupabaseAPI {
    static let shared = SupabaseAPI()

    private init() {}

    private var baseURL: URL? { SupabaseConfig.url }
    private var anonKey: String? { SupabaseConfig.anonKey }

    func signIn(email: String, password: String) async throws -> SupabaseSession {
        let url = try authURL(path: "token", queryItems: [URLQueryItem(name: "grant_type", value: "password")])
        let payload = ["email": email, "password": password]
        return try await requestJSON(url: url, method: "POST", authBearer: nil, body: payload)
    }

    func signUp(email: String, password: String) async throws -> SupabaseSession {
        let url = try authURL(path: "signup")
        let payload = ["email": email, "password": password]
        let data = try await requestData(url: url, method: "POST", authBearer: nil, body: payload)
        do {
            // Supabase returns `{ user, session }` and `session` may be null depending on auth settings.
            let response = try JSONDecoder().decode(SupabaseSignUpResponse.self, from: data)
            if let session = response.session {
                return session
            }
            // Signup succeeded but no session was created (commonly email confirmation required).
            return SupabaseSession(
                accessToken: nil,
                refreshToken: nil,
                tokenType: nil,
                expiresIn: nil,
                expiresAt: nil,
                user: response.user
            )
        } catch {
            throw SupabaseAPIError.decodingFailed(details: decodeFailureDetails(data: data, error: error))
        }
    }

    func resetPassword(email: String) async throws {
        let url = try authURL(path: "recover")
        let payload = ["email": email]
        _ = try await requestData(url: url, method: "POST", authBearer: nil, body: payload)
    }

    func signOut(accessToken: String) async throws {
        let url = try authURL(path: "logout")
        _ = try await requestData(url: url, method: "POST", authBearer: accessToken, body: Optional<[String: String]>.none)
    }

    func insertProductSubmission(accessToken: String, payload: [String: Any]) async throws {
        try await insertRow(accessToken: accessToken, table: "product_submissions", payload: payload)
    }

    func insertRow(accessToken: String, table: String, payload: [String: Any]) async throws {
        guard let baseURL else { throw SupabaseAPIError.notConfigured }
        guard let anonKey else { throw SupabaseAPIError.notConfigured }

        let url = baseURL
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent(table)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAPIError.decodingFailed(details: "No HTTPURLResponse.")
        }
        if !(200...299).contains(http.statusCode) {
            throw SupabaseAPIError.httpError(status: http.statusCode, message: extractSupabaseMessage(from: data))
        }
    }

    func upsertRow(accessToken: String, table: String, payload: [String: Any], onConflict: String) async throws {
        guard let baseURL else { throw SupabaseAPIError.notConfigured }
        guard let anonKey else { throw SupabaseAPIError.notConfigured }

        var components = URLComponents(url: baseURL
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent(table), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "on_conflict", value: onConflict)
        ]
        guard let url = components?.url else { throw SupabaseAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.addValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAPIError.decodingFailed(details: "No HTTPURLResponse.")
        }
        if !(200...299).contains(http.statusCode) {
            throw SupabaseAPIError.httpError(status: http.statusCode, message: extractSupabaseMessage(from: data))
        }
    }

    func fetchRows(accessToken: String?, table: String, queryItems: [URLQueryItem]) async throws -> [[String: Any]] {
        guard let baseURL else { throw SupabaseAPIError.notConfigured }
        guard let anonKey else { throw SupabaseAPIError.notConfigured }

        var components = URLComponents(url: baseURL
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent(table), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let url = components?.url else { throw SupabaseAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        if let accessToken, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAPIError.decodingFailed(details: "No HTTPURLResponse.")
        }
        if !(200...299).contains(http.statusCode) {
            throw SupabaseAPIError.httpError(status: http.statusCode, message: extractSupabaseMessage(from: data))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SupabaseAPIError.decodingFailed(details: "Expected JSON array response. Body: \(String(data: data, encoding: .utf8) ?? "<non-utf8 body>")")
        }
        return json
    }

    // MARK: - Private

    private func authURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard let baseURL else { throw SupabaseAPIError.notConfigured }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/auth/v1/\(path)"
        if !queryItems.isEmpty { components?.queryItems = queryItems }
        guard let url = components?.url else { throw SupabaseAPIError.invalidURL }
        return url
    }

    private func requestJSON<T: Decodable, Body: Encodable>(
        url: URL,
        method: String,
        authBearer: String?,
        body: Body?
    ) async throws -> T {
        let data = try await requestData(url: url, method: method, authBearer: authBearer, body: body)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SupabaseAPIError.decodingFailed(details: decodeFailureDetails(data: data, error: error))
        }
    }

    private func requestData<Body: Encodable>(
        url: URL,
        method: String,
        authBearer: String?,
        body: Body?
    ) async throws -> Data {
        guard let anonKey else { throw SupabaseAPIError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        if let authBearer, !authBearer.isEmpty {
            request.setValue("Bearer \(authBearer)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAPIError.decodingFailed(details: "No HTTPURLResponse.")
        }
        if !(200...299).contains(http.statusCode) {
            throw SupabaseAPIError.httpError(status: http.statusCode, message: extractSupabaseMessage(from: data))
        }
        return data
    }

    private func decodeFailureDetails(data: Data, error: Error) -> String {
        let body = (String(data: data, encoding: .utf8) ?? "<non-utf8 body>")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safeBody = redactSensitiveJSON(in: body)
        let clippedBody = safeBody.count > 600 ? String(safeBody.prefix(600)) + "…" : safeBody
        return "(\(type(of: error))) \(error.localizedDescription). Body: \(clippedBody)"
    }

    private func redactSensitiveJSON(in body: String) -> String {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return body
        }

        func redact(_ value: Any) -> Any {
            if var dict = value as? [String: Any] {
                for key in ["access_token", "refresh_token", "id_token", "provider_token", "provider_refresh_token"] {
                    if dict[key] != nil { dict[key] = "<redacted>" }
                }
                for (k, v) in dict { dict[k] = redact(v) }
                return dict
            }
            if let arr = value as? [Any] {
                return arr.map { redact($0) }
            }
            return value
        }

        let redacted = redact(obj)
        guard let out = try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys]),
              let str = String(data: out, encoding: .utf8) else {
            return body
        }
        return str
    }

    private func extractSupabaseMessage(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        if let msg = obj["msg"] as? String { return msg }
        if let msg = obj["message"] as? String { return msg }
        if let err = obj["error_description"] as? String { return err }
        if let err = obj["error"] as? String { return err }
        return nil
    }
}

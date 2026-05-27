import Foundation

enum UserFacingError {
    /// Returns a user-presentable message, or `nil` if the error should be suppressed.
    static func message(from error: Error) -> String? {
        if isSupabaseNotConfigured(error) {
            #if DEBUG
            AppLogger.warning("Suppressed user alert: Supabase not configured. \(EnvConfig.debugReport())")
            #else
            AppLogger.warning("Suppressed user alert: Supabase not configured.")
            #endif
            return nil
        }
        return error.localizedDescription
    }

    static func isSupabaseNotConfigured(_ error: Error) -> Bool {
        if let supabaseError = error as? SupabaseAPIError, case .notConfigured = supabaseError {
            return true
        }

        // Defensive fallback for bridged NSError / wrapped errors.
        let message = (error as NSError).localizedDescription
        return message == SupabaseConfig.missingConfigMessage || message.contains("Supabase is not configured")
    }
}


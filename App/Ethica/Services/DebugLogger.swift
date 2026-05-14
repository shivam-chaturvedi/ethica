import Foundation
import os.log

/// Centralized logger that gates output behind #if DEBUG
/// Use instead of print() for all new logging
enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.ethica.app"
    
    static let network = Logger(subsystem: subsystem, category: "Network")
    static let scan = Logger(subsystem: subsystem, category: "Scan")
    static let database = Logger(subsystem: subsystem, category: "Database")
    static let impact = Logger(subsystem: subsystem, category: "Impact")
    static let auth = Logger(subsystem: subsystem, category: "Auth")
    static let general = Logger(subsystem: subsystem, category: "General")
    
    /// Debug-only print wrapper - stripped from release builds
    static func debug(_ message: String, category: Logger? = nil) {
        #if DEBUG
        (category ?? general).debug("\(message, privacy: .public)")
        #endif
    }
    
    /// Info level - always logged
    static func info(_ message: String, category: Logger? = nil) {
        (category ?? general).info("\(message, privacy: .public)")
    }
    
    /// Error level - always logged
    static func error(_ message: String, category: Logger? = nil) {
        (category ?? general).error("\(message, privacy: .public)")
    }
    
    /// Warning level - always logged
    static func warning(_ message: String, category: Logger? = nil) {
        (category ?? general).warning("\(message, privacy: .public)")
    }
}

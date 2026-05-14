//
//  ProductCacheService.swift
//  Ethica
//
//  SQLite-based local cache for product data (offline mode)

import Foundation
import SQLite3
import OSLog

struct CachedProduct {
    let barcode: String
    let productName: String
    let ingredients: [String]
    let allergens: String?
    let ethicalScore: Double?
    let ethicalSummary: String?
    let cachedAt: Date
    let expiresAt: Date
    
    var isExpired: Bool {
        return Date() > expiresAt
    }
}

/// 🚀 Converted to actor for automatic thread-safe SQLite access
actor ProductCacheService {
    private var db: OpaquePointer?
    private let cacheDuration: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    private let logger = Logger(subsystem: "com.ethica.app", category: "ProductCache")

    /// SQLITE_TRANSIENT equivalent — tells SQLite to copy the string immediately
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    // 🚨 CACHE VERSION: Increment to clear entire SQLite cache
    // Version 2: Fixed isSafe calculation to check warnings
    private let CACHE_VERSION = 2

    init() {
        setupDatabase()
        checkCacheVersion()
    }

    deinit {
        sqlite3_close(db)
    }
    
    // MARK: - Database Setup
    
    private func setupDatabase() {
        guard let fileURL = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ethica_cache.sqlite") else {
            AppLogger.error("❌ Failed to get database file URL")
            return
        }

        if sqlite3_open(fileURL.path, &db) != SQLITE_OK {
            logger.error("❌ Failed to open database")
            return
        }
        
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS products (
            barcode TEXT PRIMARY KEY,
            product_name TEXT NOT NULL,
            ingredients TEXT NOT NULL,
            allergens TEXT,
            ethical_score REAL,
            ethical_summary TEXT,
            cached_at INTEGER NOT NULL,
            expires_at INTEGER NOT NULL
        );
        
        CREATE INDEX IF NOT EXISTS idx_expires_at ON products(expires_at);
        """
        
        if sqlite3_exec(db, createTableSQL, nil, nil, nil) != SQLITE_OK {
            logger.error("❌ Failed to create products table")
        } else {
            logger.debug("✅ Product cache database ready")
        }
    }

    /// Check cache version and clear if outdated
    private func checkCacheVersion() {
        let storedVersion = UserDefaults.standard.integer(forKey: "ProductCacheVersion")

        if storedVersion != CACHE_VERSION {
            logger.debug("🔄 Cache version mismatch (stored: \(storedVersion), current: \(self.CACHE_VERSION)) - clearing SQLite cache")
            clearAll()
            UserDefaults.standard.set(self.CACHE_VERSION, forKey: "ProductCacheVersion")
            logger.debug("✅ SQLite cache cleared and version updated to \(self.CACHE_VERSION)")
        }
    }

    // MARK: - Cache Operations
    
    /// Save product to cache (thread-safe via actor)
    func save(
        barcode: String,
        productName: String,
        ingredients: [String],
        allergens: String?,
        ethicalScore: Double?,
        ethicalSummary: String?
    ) {
        let now = Date()
        let expiresAt = now.addingTimeInterval(cacheDuration)

        let insertSQL = """
        INSERT OR REPLACE INTO products
        (barcode, product_name, ingredients, allergens, ethical_score, ethical_summary, cached_at, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            logger.error("❌ Failed to prepare insert statement")
            return
        }

        defer { sqlite3_finalize(statement) }

        let ingredientsJSON = (try? JSONEncoder().encode(ingredients)) ?? Data()
        let ingredientsString = String(data: ingredientsJSON, encoding: .utf8) ?? "[]"

        sqlite3_bind_text(statement, 1, barcode, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, productName, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, ingredientsString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 4, allergens, -1, SQLITE_TRANSIENT)

        if let score = ethicalScore {
            sqlite3_bind_double(statement, 5, score)
        } else {
            sqlite3_bind_null(statement, 5)
        }

        sqlite3_bind_text(statement, 6, ethicalSummary, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 7, Int64(now.timeIntervalSince1970))
        sqlite3_bind_int64(statement, 8, Int64(expiresAt.timeIntervalSince1970))

        if sqlite3_step(statement) == SQLITE_DONE {
            logger.debug("✅ Cached product: \(productName) (\(barcode))")
        } else {
            logger.error("❌ Failed to cache product")
        }
    }
    
    /// Fetch product from cache (thread-safe via actor)
    func fetch(barcode: String) -> CachedProduct? {
        let querySQL = "SELECT * FROM products WHERE barcode = ? AND expires_at > ?;"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK else {
            logger.error("❌ Failed to prepare fetch statement")
            return nil
        }

        defer { sqlite3_finalize(statement) }

        let now = Int64(Date().timeIntervalSince1970)
        sqlite3_bind_text(statement, 1, barcode, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 2, now)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            logger.warning("⚠️ Product not found in cache: \(barcode)")
            return nil
        }

        let productName = String(cString: sqlite3_column_text(statement, 1))
        let ingredientsString = String(cString: sqlite3_column_text(statement, 2))

        let allergens: String? = {
            if let text = sqlite3_column_text(statement, 3) {
                return String(cString: text)
            }
            return nil
        }()

        let ethicalScore: Double? = {
            let type = sqlite3_column_type(statement, 4)
            return type == SQLITE_NULL ? nil : sqlite3_column_double(statement, 4)
        }()

        let ethicalSummary: String? = {
            if let text = sqlite3_column_text(statement, 5) {
                return String(cString: text)
            }
            return nil
        }()

        let cachedAt = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 6)))
        let expiresAt = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 7)))

        let ingredients = (try? JSONDecoder().decode([String].self, from: ingredientsString.data(using: .utf8) ?? Data())) ?? []

        logger.debug("✅ Retrieved product from cache: \(productName)")
        logger.debug("   - Ingredients count: \(ingredients.count)")

        // Validate cached data - reject if product name or ingredients are empty
        if productName.isEmpty || ingredients.isEmpty {
            logger.warning("⚠️ Invalid cached data (empty name or ingredients), invalidating cache entry")
            let deleteSQL = "DELETE FROM products WHERE barcode = ?;"
            var deleteStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(deleteStmt, 1, barcode, -1, SQLITE_TRANSIENT)
                sqlite3_step(deleteStmt)
                sqlite3_finalize(deleteStmt)
            }
            return nil
        }

        return CachedProduct(
            barcode: barcode,
            productName: productName,
            ingredients: ingredients,
            allergens: allergens,
            ethicalScore: ethicalScore,
            ethicalSummary: ethicalSummary,
            cachedAt: cachedAt,
            expiresAt: expiresAt
        )
    }
    
    /// Clear expired cache entries (thread-safe via actor)
    func clearExpired() {
        let deleteSQL = "DELETE FROM products WHERE expires_at < ?;"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK else {
            logger.error("❌ Failed to prepare delete statement")
            return
        }

        defer { sqlite3_finalize(statement) }

        let now = Int64(Date().timeIntervalSince1970)
        sqlite3_bind_int64(statement, 1, now)

        if sqlite3_step(statement) == SQLITE_DONE {
            let deletedCount = sqlite3_changes(db)
            logger.debug("✅ Cleared \(deletedCount) expired cache entries")
        }
    }

    /// Clear ALL cache entries (use when cache is corrupted or for testing)
    func clearAll() {
        // Note: called from init, so already on actor's executor
        let deleteSQL = "DELETE FROM products;"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK else {
            logger.error("❌ Failed to prepare delete all statement")
            return
        }

        defer { sqlite3_finalize(statement) }

        if sqlite3_step(statement) == SQLITE_DONE {
            let deletedCount = sqlite3_changes(db)
            logger.debug("✅ Cleared ALL \(deletedCount) cache entries")
        }
    }

    /// Get cache statistics (thread-safe via actor)
    func getCacheStats() -> (total: Int, expired: Int) {
        let countSQL = "SELECT COUNT(*) FROM products;"
        let expiredSQL = "SELECT COUNT(*) FROM products WHERE expires_at < ?;"

        var total = 0
        var expired = 0

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, countSQL, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                total = Int(sqlite3_column_int(statement, 0))
            }
            sqlite3_finalize(statement)
        }

        if sqlite3_prepare_v2(db, expiredSQL, -1, &statement, nil) == SQLITE_OK {
            let now = Int64(Date().timeIntervalSince1970)
            sqlite3_bind_int64(statement, 1, now)
            if sqlite3_step(statement) == SQLITE_ROW {
                expired = Int(sqlite3_column_int(statement, 0))
            }
            sqlite3_finalize(statement)
        }

        return (total, expired)
    }
}

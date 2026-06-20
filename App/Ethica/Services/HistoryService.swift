//
//  HistoryService.swift
//  Ethica
//
//  SQLite-based scan history tracking service

import Foundation
import SQLite3
import UIKit

class HistoryService {
    static let shared = HistoryService()

    private var db: OpaquePointer?
    private let dbPath: String

    /// Serial queue to synchronize all SQLite operations (thread safety)
    private let dbQueue = DispatchQueue(label: "com.ethica.historyservice.db", qos: .userInitiated)

    /// SQLITE_TRANSIENT equivalent — tells SQLite to copy the string immediately,
    /// preventing use-after-free when Swift's temporary UTF8 pointer is released.
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Public accessor for the database file path (used by SQLite.swift-based services)
    var databasePath: String { dbPath }
    
    private init() {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dbPath = documentsURL.appendingPathComponent("ethica_history.sqlite").path
        
        AppLogger.debug("📂 History database path: \(dbPath)")
        
        openDatabase()
        createTables()
        
        // Register for app termination notification to properly close database
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(closeDatabase),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
        // Also close on background
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(syncDatabase),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        closeDatabase()
    }
    
    @objc private func syncDatabase() {
        // Force write to disk when app goes to background — route through dbQueue for thread safety
        dbQueue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", nil, nil, nil)
            AppLogger.debug("💾 Database synced to disk (app backgrounded)")
        }
    }
    
    @objc private func closeDatabase() {
        if db != nil {
            sqlite3_close(db)
            db = nil
            AppLogger.debug("🔒 History database closed")
        }
    }

    /// Safe wrapper around sqlite3_errmsg that handles nil db gracefully
    private func dbErrorMessage() -> String {
        guard let db = db else { return "Database not initialized" }
        return String(cString: sqlite3_errmsg(db))
    }
    
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            AppLogger.error("❌ Error opening history database")
        } else {
            AppLogger.debug("✅ History database opened successfully")
        }
    }
    
    private func createTables() {
        let createTableQuery = """
        CREATE TABLE IF NOT EXISTS scan_history (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            product_name TEXT NOT NULL,
            barcode TEXT,
            source_type TEXT NOT NULL,
            is_safe INTEGER NOT NULL,
            violations_count INTEGER NOT NULL,
            violations TEXT NOT NULL,
            co2_emissions REAL NOT NULL,
            water_usage REAL NOT NULL,
            animal_impact TEXT NOT NULL,
            health_score REAL NOT NULL,
            concerns_count INTEGER NOT NULL,
            purchase_decision TEXT NOT NULL,
            alternative_name TEXT,
            alternative_co2 REAL,
            alternative_water REAL,
            selected_alternative_index INTEGER,
            price_comparison TEXT,
            decision_timestamp REAL,
            needs_review INTEGER DEFAULT 1
        );

        CREATE INDEX IF NOT EXISTS idx_timestamp ON scan_history(timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_barcode ON scan_history(barcode);
        CREATE INDEX IF NOT EXISTS idx_is_safe ON scan_history(is_safe);
        CREATE INDEX IF NOT EXISTS idx_purchase_decision ON scan_history(purchase_decision);
        CREATE INDEX IF NOT EXISTS idx_needs_review ON scan_history(needs_review);
        """

        let createAlternativeInteractionsQuery = """
        CREATE TABLE IF NOT EXISTS alternative_interactions (
            id TEXT PRIMARY KEY,
            alternative_name TEXT NOT NULL,
            alternative_brand TEXT,
            original_product TEXT NOT NULL,
            action TEXT NOT NULL,
            timestamp REAL NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_alt_action ON alternative_interactions(action);
        CREATE INDEX IF NOT EXISTS idx_alt_brand ON alternative_interactions(alternative_brand);
        """

        // Use sqlite3_exec for multi-statement SQL (sqlite3_prepare_v2 only handles first statement)
        if sqlite3_exec(db, createTableQuery, nil, nil, nil) == SQLITE_OK {
            AppLogger.debug("✅ History tables created successfully")
        }

        if sqlite3_exec(db, createAlternativeInteractionsQuery, nil, nil, nil) == SQLITE_OK {
            AppLogger.debug("✅ Alternative interactions table created successfully")
        }

        // Migrate existing databases to add new columns
        migrateDatabase()
    }
    
    private func migrateDatabase() {
        // Check if new columns exist, add them if missing
        let migrations = [
            "ALTER TABLE scan_history ADD COLUMN purchase_decision TEXT DEFAULT 'pending';",
            "ALTER TABLE scan_history ADD COLUMN alternative_name TEXT DEFAULT NULL;",
            "ALTER TABLE scan_history ADD COLUMN alternative_co2 REAL DEFAULT NULL;",
            "ALTER TABLE scan_history ADD COLUMN alternative_water REAL DEFAULT NULL;",
            "ALTER TABLE scan_history ADD COLUMN selected_alternative_index INTEGER DEFAULT NULL;",
            "ALTER TABLE scan_history ADD COLUMN price_comparison TEXT DEFAULT NULL;",
            "ALTER TABLE scan_history ADD COLUMN decision_timestamp REAL DEFAULT NULL;",
            "ALTER TABLE scan_history ADD COLUMN needs_review INTEGER DEFAULT 0;",
            "CREATE INDEX IF NOT EXISTS idx_purchase_decision ON scan_history(purchase_decision);",
            "CREATE INDEX IF NOT EXISTS idx_needs_review ON scan_history(needs_review);"
        ]
        
        for migration in migrations {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, migration, -1, &statement, nil) == SQLITE_OK {
                sqlite3_step(statement)
                // Ignore errors (column already exists)
            }
            sqlite3_finalize(statement)
        }
        
        AppLogger.debug("✅ Database migration complete")
    }
    
    // MARK: - Save Scan

    func saveScan(_ scan: ScanHistory) {
        dbQueue.async { [weak self] in
            self?._saveScanUnsafe(scan)
        }
    }

    private func _saveScanUnsafe(_ scan: ScanHistory) {
        let insertQuery = """
        INSERT INTO scan_history (
            id, timestamp, product_name, barcode, source_type,
            is_safe, violations_count, violations,
            co2_emissions, water_usage, animal_impact,
            health_score, concerns_count,
            purchase_decision, alternative_name,
            alternative_co2, alternative_water,
            selected_alternative_index, price_comparison,
            decision_timestamp, needs_review
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        var statement: OpaquePointer?
        
        AppLogger.debug("🔍 SAVE DEBUG: About to save scan")
        AppLogger.debug("   ✅ ID: \(scan.id.uuidString) <- USE THIS ID FOR UPDATE")
        AppLogger.debug("   productName: \(scan.productName)")
        AppLogger.debug("   purchaseDecision: \(scan.purchaseDecision.rawValue)")
        AppLogger.debug("   📊 healthScore: \(scan.healthScore)")
        AppLogger.debug("   📊 co2Emissions: \(scan.co2Emissions)")
        AppLogger.debug("   📊 waterUsage: \(scan.waterUsage)")
        
        if sqlite3_prepare_v2(db, insertQuery, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (scan.id.uuidString as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 2, scan.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(statement, 3, (scan.productName as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, (scan.barcode as NSString?)?.utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 5, (scan.sourceType as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 6, scan.isSafe ? 1 : 0)
            sqlite3_bind_int(statement, 7, Int32(scan.violationsCount))

            let violationsJSON = (try? JSONEncoder().encode(scan.violations)) ?? Data()
            let violationsString = String(data: violationsJSON, encoding: .utf8) ?? "[]"
            sqlite3_bind_text(statement, 8, (violationsString as NSString).utf8String, -1, SQLITE_TRANSIENT)

            sqlite3_bind_double(statement, 9, scan.co2Emissions)
            sqlite3_bind_double(statement, 10, scan.waterUsage)
            sqlite3_bind_text(statement, 11, (scan.animalImpact as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 12, scan.healthScore)
            sqlite3_bind_int(statement, 13, Int32(scan.concernsCount))
            sqlite3_bind_text(statement, 14, (scan.purchaseDecision.rawValue as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 15, (scan.alternativeName as NSString?)?.utf8String, -1, SQLITE_TRANSIENT)
            
            // Bind alternative environmental data with null handling
            if let co2 = scan.alternativeCO2 {
                sqlite3_bind_double(statement, 16, co2)
            } else {
                sqlite3_bind_null(statement, 16)
            }
            
            if let water = scan.alternativeWater {
                sqlite3_bind_double(statement, 17, water)
            } else {
                sqlite3_bind_null(statement, 17)
            }
            
            // Bind new fields
            if let index = scan.selectedAlternativeIndex {
                sqlite3_bind_int(statement, 18, Int32(index))
            } else {
                sqlite3_bind_null(statement, 18)
            }
            
            sqlite3_bind_text(statement, 19, (scan.priceComparison as NSString?)?.utf8String, -1, SQLITE_TRANSIENT)
            
            if let decisionTime = scan.decisionTimestamp {
                sqlite3_bind_double(statement, 20, decisionTime.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 20)
            }
            
            sqlite3_bind_int(statement, 21, scan.needsReview ? 1 : 0)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                AppLogger.debug("✅ Scan saved to history: \(scan.productName) [decision: \(scan.purchaseDecision.rawValue)]")
                
                // Force database to write to disk immediately
                sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", nil, nil, nil)
                
                // VERIFY: Check if data is actually in database
                var verifyStatement: OpaquePointer?
                let verifyQuery = "SELECT id, product_name, purchase_decision, co2_emissions, water_usage, health_score FROM scan_history WHERE id = ?;"
                if sqlite3_prepare_v2(db, verifyQuery, -1, &verifyStatement, nil) == SQLITE_OK {
                    sqlite3_bind_text(verifyStatement, 1, (scan.id.uuidString as NSString).utf8String, -1, SQLITE_TRANSIENT)
                    if sqlite3_step(verifyStatement) == SQLITE_ROW {
                        let savedId = sqlite3_column_text(verifyStatement, 0).map { String(cString: $0) } ?? "?"
                        let savedName = sqlite3_column_text(verifyStatement, 1).map { String(cString: $0) } ?? "?"
                        let savedDecision = sqlite3_column_text(verifyStatement, 2).map { String(cString: $0) } ?? "?"
                        AppLogger.debug("✅ VERIFY: Data persisted - id=\(savedId), name=\(savedName), decision=\(savedDecision)")
                    } else {
                        AppLogger.error("❌ VERIFY: Data NOT found in database after save!")
                    }
                }
                sqlite3_finalize(verifyStatement)

                // Best-effort cloud backup to Supabase (no backend server)
                Task {
                    await NetworkService.shared.syncScanToSupabase(scan)
                }
            } else {
                let errorCode = sqlite3_errcode(db)
                let errorMsg = dbErrorMessage()
                AppLogger.error("❌ Failed to save scan - Error \(errorCode): \(errorMsg)")
            }
        } else {
            let errorCode = sqlite3_errcode(db)
            let errorMsg = dbErrorMessage()
            AppLogger.error("❌ Failed to prepare save statement - Error \(errorCode): \(errorMsg)")
        }
        
        sqlite3_finalize(statement)
    }
    
    // MARK: - Fetch Scans
    
    func fetchRecentScans(limit: Int = 20) -> [ScanHistory] {
        return dbQueue.sync { _fetchRecentScansUnsafe(limit: limit) }
    }

    private func _fetchRecentScansUnsafe(limit: Int) -> [ScanHistory] {
        var scans: [ScanHistory] = []

        let query = "SELECT * FROM scan_history ORDER BY timestamp DESC LIMIT ?;"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(limit))

            while sqlite3_step(statement) == SQLITE_ROW {
                if let scan = parseScan(from: statement) {
                    scans.append(scan)
                }
            }
        }

        sqlite3_finalize(statement)
        return scans
    }
    
    func fetchScans(from startDate: Date, to endDate: Date) -> [ScanHistory] {
        return dbQueue.sync { _fetchScansUnsafe(from: startDate, to: endDate) }
    }

    private func _fetchScansUnsafe(from startDate: Date, to endDate: Date) -> [ScanHistory] {
        var scans: [ScanHistory] = []

        let query = "SELECT * FROM scan_history WHERE timestamp BETWEEN ? AND ? ORDER BY timestamp DESC;"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_double(statement, 1, startDate.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, endDate.timeIntervalSince1970)

            while sqlite3_step(statement) == SQLITE_ROW {
                if let scan = parseScan(from: statement) {
                    scans.append(scan)
                }
            }
        }

        sqlite3_finalize(statement)
        return scans
    }
    
    func fetchAllScans() -> [ScanHistory] {
        return dbQueue.sync { _fetchAllScansUnsafe() }
    }

    /// Paginated fetch for large histories
    func fetchScans(limit: Int, offset: Int = 0) -> [ScanHistory] {
        return dbQueue.sync {
            var scans: [ScanHistory] = []
            let query = "SELECT * FROM scan_history ORDER BY timestamp DESC LIMIT ? OFFSET ?;"
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(limit))
                sqlite3_bind_int(statement, 2, Int32(offset))
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let scan = parseScan(from: statement) {
                        let productName = scan.productName.lowercased()
                        let shouldExclude = productName.contains("unknown") ||
                                           productName.contains("i am sorry") ||
                                           productName.contains("i cannot") ||
                                           productName.contains("i am unable") ||
                                           productName.contains("there is no ingredient") ||
                                           productName.contains("unidentifiable")
                        if !shouldExclude {
                            scans.append(scan)
                        }
                    }
                }
            }
            sqlite3_finalize(statement)
            return scans
        }
    }

    private func _fetchAllScansUnsafe() -> [ScanHistory] {
        var scans: [ScanHistory] = []

        let query = "SELECT * FROM scan_history ORDER BY timestamp DESC;"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            var rowCount = 0
            while sqlite3_step(statement) == SQLITE_ROW {
                rowCount += 1
                if let scan = parseScan(from: statement) {
                    // Filter out Unknown Products and apology messages
                    let productName = scan.productName.lowercased()
                    let shouldExclude = productName.contains("unknown") ||
                                       productName.contains("i am sorry") ||
                                       productName.contains("i cannot") ||
                                       productName.contains("i am unable") ||
                                       productName.contains("there is no ingredient") ||
                                       productName.contains("unidentifiable")
                    
                    if !shouldExclude {
                        scans.append(scan)
                    } else {
                        AppLogger.error("🚫 Filtered out: \(scan.productName)")
                    }
                } else {
                    AppLogger.warning("⚠️ Failed to parse scan row \(rowCount)")
                }
            }
            AppLogger.debug("📊 Found \(rowCount) rows in database, successfully parsed \(scans.count) scans (after filtering)")
        } else {
            let errorMsg = dbErrorMessage()
            AppLogger.error("❌ Failed to prepare fetch query: \(errorMsg)")
        }
        
        sqlite3_finalize(statement)
        AppLogger.debug("📊 Fetched \(scans.count) scans from history")
        return scans
    }
    
    private func parseScan(from statement: OpaquePointer?) -> ScanHistory? {
        guard let statement = statement else {
            AppLogger.error("❌ parseScan: statement is nil")
            return nil
        }
        
        guard let idPtr = sqlite3_column_text(statement, 0) else {
            AppLogger.error("❌ parseScan: NULL id column")
            return nil
        }
        let idString = String(cString: idPtr)
        guard let id = UUID(uuidString: idString) else {
            AppLogger.error("❌ parseScan: Invalid UUID string: \(idString)")
            return nil
        }

        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
        let productName = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? "Unknown Product"
        let barcode = sqlite3_column_text(statement, 3).map { String(cString: $0) }
        let sourceType = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? "unknown"
        let isSafe = sqlite3_column_int(statement, 5) == 1
        let violationsCount = Int(sqlite3_column_int(statement, 6))

        let violationsString = sqlite3_column_text(statement, 7).map { String(cString: $0) } ?? "[]"
        let violations = (try? JSONDecoder().decode([String].self, from: violationsString.data(using: .utf8) ?? Data())) ?? []

        let co2Emissions = sqlite3_column_double(statement, 8)
        let waterUsage = sqlite3_column_double(statement, 9)
        let animalImpact = sqlite3_column_text(statement, 10).map { String(cString: $0) } ?? "Unknown"
        let healthScore = sqlite3_column_double(statement, 11)
        let concernsCount = Int(sqlite3_column_int(statement, 12))
        let purchaseDecisionString = sqlite3_column_text(statement, 13).map { String(cString: $0) } ?? "scanned"
        let purchaseDecision = PurchaseDecision(rawValue: purchaseDecisionString) ?? .scanned
        
        let alternativeName = sqlite3_column_text(statement, 14).map { String(cString: $0) }
        let alternativeCO2: Double? = sqlite3_column_type(statement, 15) != SQLITE_NULL 
            ? sqlite3_column_double(statement, 15) : nil
        let alternativeWater: Double? = sqlite3_column_type(statement, 16) != SQLITE_NULL
            ? sqlite3_column_double(statement, 16) : nil
        let selectedAlternativeIndex: Int? = sqlite3_column_type(statement, 17) != SQLITE_NULL
            ? Int(sqlite3_column_int(statement, 17)) : nil
        let priceComparison = sqlite3_column_text(statement, 18).map { String(cString: $0) }
        let decisionTimestamp: Date? = sqlite3_column_type(statement, 19) != SQLITE_NULL
            ? Date(timeIntervalSince1970: sqlite3_column_double(statement, 19)) : nil
        let needsReview = sqlite3_column_type(statement, 20) != SQLITE_NULL
            ? sqlite3_column_int(statement, 20) == 1 : false
        
        let scanHistory = ScanHistory(
            id: id,
            timestamp: timestamp,
            productName: productName,
            barcode: barcode,
            sourceType: sourceType,
            isSafe: isSafe,
            violationsCount: violationsCount,
            violations: violations,
            co2Emissions: co2Emissions,
            waterUsage: waterUsage,
            animalImpact: animalImpact,
            healthScore: healthScore,
            concernsCount: concernsCount,
            purchaseDecision: purchaseDecision,
            alternativeName: alternativeName,
            alternativeCO2: alternativeCO2,
            alternativeWater: alternativeWater,
            selectedAlternativeIndex: selectedAlternativeIndex,
            priceComparison: priceComparison,
            decisionTimestamp: decisionTimestamp,
            needsReview: needsReview
        )
        
        AppLogger.debug("   ✅ ScanHistory object created successfully for: \(productName)")
        return scanHistory
    }
    
    // MARK: - Statistics
    
    func getTotalScansCount() -> Int {
        return dbQueue.sync { _getTotalScansCountUnsafe() }
    }

    private func _getTotalScansCountUnsafe() -> Int {
        let query = "SELECT COUNT(*) FROM scan_history;"
        var statement: OpaquePointer?
        var count = 0

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }

        sqlite3_finalize(statement)
        return count
    }
    
    func getFirstScanDate() -> Date? {
        return dbQueue.sync { _getFirstScanDateUnsafe() }
    }

    private func _getFirstScanDateUnsafe() -> Date? {
        let query = "SELECT MIN(timestamp) FROM scan_history;"
        var statement: OpaquePointer?
        var date: Date?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                let timestamp = sqlite3_column_double(statement, 0)
                if timestamp > 0 {
                    date = Date(timeIntervalSince1970: timestamp)
                }
            }
        }

        sqlite3_finalize(statement)
        return date
    }
    
    // MARK: - Update Purchase Decision
    
    func updatePurchaseDecision(
        for scanId: UUID,
        decision: PurchaseDecision,
        alternativeName: String? = nil,
        alternativeCO2: Double? = nil,
        alternativeWater: Double? = nil,
        selectedAlternativeIndex: Int? = nil,
        decisionTimestamp: Date? = nil
    ) {
        dbQueue.async { [weak self] in
            self?._updatePurchaseDecisionUnsafe(
                for: scanId, decision: decision,
                alternativeName: alternativeName, alternativeCO2: alternativeCO2,
                alternativeWater: alternativeWater, selectedAlternativeIndex: selectedAlternativeIndex,
                decisionTimestamp: decisionTimestamp
            )
        }
    }

    func updatePurchaseDecision(
        for scanId: UUID,
        decision: PurchaseDecision,
        alternativeName: String? = nil,
        alternativeCO2: Double? = nil,
        alternativeWater: Double? = nil,
        selectedAlternativeIndex: Int? = nil,
        decisionTimestamp: Date? = Date()
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dbQueue.async { [weak self] in
                self?._updatePurchaseDecisionUnsafe(
                    for: scanId, decision: decision,
                    alternativeName: alternativeName, alternativeCO2: alternativeCO2,
                    alternativeWater: alternativeWater, selectedAlternativeIndex: selectedAlternativeIndex,
                    decisionTimestamp: decisionTimestamp
                )
                continuation.resume()
            }
        }
    }

    private func _updatePurchaseDecisionUnsafe(
        for scanId: UUID,
        decision: PurchaseDecision,
        alternativeName: String?,
        alternativeCO2: Double?,
        alternativeWater: Double?,
        selectedAlternativeIndex: Int?,
        decisionTimestamp: Date?
    ) {
        let updateQuery = "UPDATE scan_history SET purchase_decision = ?, alternative_name = ?, alternative_co2 = ?, alternative_water = ?, selected_alternative_index = ?, decision_timestamp = ?, needs_review = 0 WHERE id = ?;"
        var statement: OpaquePointer?

        AppLogger.debug("🔍 UPDATE DEBUG: Updating purchase decision")
        AppLogger.debug("   ✅ scanId: \(scanId.uuidString) <- MUST MATCH SAVE ID")
        AppLogger.debug("   decision: \(decision.rawValue)")
        if let altName = alternativeName {
            AppLogger.debug("   alternativeName: \(altName)")
        }
        if let altCO2 = alternativeCO2 {
            AppLogger.debug("   alternativeCO2: \(altCO2)kg")
        }
        
        // FIRST: Check if this ID actually exists in the database
        var checkStatement: OpaquePointer?
        let checkQuery = "SELECT id, product_name, source_type FROM scan_history WHERE id = ?;"
        if sqlite3_prepare_v2(db, checkQuery, -1, &checkStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(checkStatement, 1, (scanId.uuidString as NSString).utf8String, -1, SQLITE_TRANSIENT)
            if sqlite3_step(checkStatement) == SQLITE_ROW {
                let foundId = sqlite3_column_text(checkStatement, 0).map { String(cString: $0) } ?? "?"
                let foundName = sqlite3_column_text(checkStatement, 1).map { String(cString: $0) } ?? "?"
                let foundSource = sqlite3_column_text(checkStatement, 2).map { String(cString: $0) } ?? "?"
                AppLogger.debug("   ✅ FOUND existing record: id=\(foundId), name=\(foundName), source=\(foundSource)")
            } else {
                AppLogger.error("   ❌ ERROR: No record found with this ID in database!")
                AppLogger.error("   ❌ This means the scan was never saved, or the ID doesn't match")
                sqlite3_finalize(checkStatement)
                return
            }
        }
        sqlite3_finalize(checkStatement)
        
        if sqlite3_prepare_v2(db, updateQuery, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (decision.rawValue as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, (alternativeName as NSString?)?.utf8String, -1, SQLITE_TRANSIENT)
            
            if let altCO2 = alternativeCO2 {
                sqlite3_bind_double(statement, 3, altCO2)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            
            if let altWater = alternativeWater {
                sqlite3_bind_double(statement, 4, altWater)
            } else {
                sqlite3_bind_null(statement, 4)
            }
            
            if let index = selectedAlternativeIndex {
                sqlite3_bind_int(statement, 5, Int32(index))
            } else {
                sqlite3_bind_null(statement, 5)
            }
            
            if let timestamp = decisionTimestamp {
                sqlite3_bind_double(statement, 6, timestamp.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 6)
            }
            
            sqlite3_bind_text(statement, 7, (scanId.uuidString as NSString).utf8String, -1, SQLITE_TRANSIENT)

            if sqlite3_step(statement) == SQLITE_DONE {
                AppLogger.debug("✅ Purchase decision updated: \(decision.rawValue)")

                // Force database to write to disk immediately
                sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", nil, nil, nil)

                // VERIFY: Check if data was actually updated
                var verifyStatement: OpaquePointer?
                let verifyQuery = "SELECT purchase_decision FROM scan_history WHERE id = ?;"
                if sqlite3_prepare_v2(db, verifyQuery, -1, &verifyStatement, nil) == SQLITE_OK {
                    sqlite3_bind_text(verifyStatement, 1, (scanId.uuidString as NSString).utf8String, -1, SQLITE_TRANSIENT)
                    if sqlite3_step(verifyStatement) == SQLITE_ROW {
                        let updatedDecision = sqlite3_column_text(verifyStatement, 0).map { String(cString: $0) } ?? "?"
                        AppLogger.debug("✅ VERIFY UPDATE: Data persisted - purchase_decision is now '\(updatedDecision)'")
                    } else {
                        AppLogger.error("❌ VERIFY UPDATE: Row not found after update!")
                    }
                }
                sqlite3_finalize(verifyStatement)

                if let scan = _fetchScanUnsafe(id: scanId) {
                    Task {
                        await NetworkService.shared.syncScanToSupabase(scan)
                    }
                }
            } else {
                let errorMsg = dbErrorMessage()
                AppLogger.error("❌ Failed to update purchase decision: \(errorMsg)")
            }
        } else {
            let errorMsg = dbErrorMessage()
            AppLogger.error("❌ Failed to prepare UPDATE statement: \(errorMsg)")
        }
        
        sqlite3_finalize(statement)
    }

    func scan(withId id: UUID) -> ScanHistory? {
        return dbQueue.sync { _fetchScanUnsafe(id: id) }
    }

    private func _fetchScanUnsafe(id: UUID) -> ScanHistory? {
        let query = "SELECT * FROM scan_history WHERE id = ? LIMIT 1;"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            AppLogger.error("❌ Failed to prepare fetch-by-id query: \(dbErrorMessage())")
            return nil
        }

        sqlite3_bind_text(statement, 1, (id.uuidString as NSString).utf8String, -1, SQLITE_TRANSIENT)
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return parseScan(from: statement)
    }
    
    // Legacy method for backward compatibility
    func markAlternativeChosen(for scanId: UUID, alternativeName: String) {
        updatePurchaseDecision(for: scanId, decision: .alternative, alternativeName: alternativeName)
    }
    
    // MARK: - Delete Single Scan

    func deleteScan(id: UUID) {
        dbQueue.async { [weak self] in
            self?._deleteScanUnsafe(id: id)
        }
    }

    private func _deleteScanUnsafe(id: UUID) {
        let deleteQuery = "DELETE FROM scan_history WHERE id = ?;"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, deleteQuery, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (id.uuidString as NSString).utf8String, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) == SQLITE_DONE {
                AppLogger.debug("✅ Scan deleted: \(id.uuidString)")
            } else {
                let errorMsg = dbErrorMessage()
                AppLogger.error("❌ Failed to delete scan: \(errorMsg)")
            }
        }

        sqlite3_finalize(statement)
    }

    // MARK: - Clear History

    func clearAllHistory() {
        dbQueue.async { [weak self] in
            guard let self = self else { return }
            let deleteQuery = "DELETE FROM scan_history;"
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(self.db, deleteQuery, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_DONE {
                    AppLogger.debug("✅ History cleared")
                }
            }

            sqlite3_finalize(statement)
        }
    }

    // MARK: - Alternative Interaction Tracking

    func logAlternativeInteraction(
        alternativeName: String,
        alternativeBrand: String?,
        originalProduct: String,
        action: String
    ) {
        dbQueue.async { [weak self] in
            self?._logAlternativeInteractionUnsafe(
                alternativeName: alternativeName,
                alternativeBrand: alternativeBrand,
                originalProduct: originalProduct,
                action: action
            )
        }
    }

    private func _logAlternativeInteractionUnsafe(
        alternativeName: String,
        alternativeBrand: String?,
        originalProduct: String,
        action: String
    ) {
        let insertQuery = """
        INSERT INTO alternative_interactions (
            id, alternative_name, alternative_brand, original_product, action, timestamp
        ) VALUES (?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        if sqlite3_prepare_v2(db, insertQuery, -1, &statement, nil) == SQLITE_OK {
            let id = UUID().uuidString
            sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, transient)
            sqlite3_bind_text(statement, 2, (alternativeName as NSString).utf8String, -1, transient)
            if let brand = alternativeBrand {
                sqlite3_bind_text(statement, 3, (brand as NSString).utf8String, -1, transient)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            sqlite3_bind_text(statement, 4, (originalProduct as NSString).utf8String, -1, transient)
            sqlite3_bind_text(statement, 5, (action as NSString).utf8String, -1, transient)
            sqlite3_bind_double(statement, 6, Date().timeIntervalSince1970)

            if sqlite3_step(statement) == SQLITE_DONE {
                AppLogger.debug("✅ Logged alternative interaction: \(action) - \(alternativeBrand ?? "") \(alternativeName)")
                Task {
                    await NetworkService.shared.logAlternativeInteraction(
                        alternativeName: alternativeName,
                        alternativeBrand: alternativeBrand,
                        originalProduct: originalProduct,
                        action: action
                    )
                }
            } else {
                let errorMsg = dbErrorMessage()
                AppLogger.error("❌ Failed to log interaction: \(errorMsg)")
            }
        } else {
            let errorMsg = dbErrorMessage()
            AppLogger.error("❌ Failed to prepare interaction insert: \(errorMsg)")
        }

        sqlite3_finalize(statement)
    }

    func getUserBrandPreferences() -> UserBrandPreferences {
        return dbQueue.sync { _getUserBrandPreferencesUnsafe() }
    }

    private func _getUserBrandPreferencesUnsafe() -> UserBrandPreferences {
        var preferredBrands: [String: Int] = [:]
        var dismissedBrands: [String: Int] = [:]

        // Query for clicked and purchased alternatives (positive interactions)
        let positiveQuery = """
        SELECT alternative_brand, COUNT(*) as count
        FROM alternative_interactions
        WHERE (action = 'clicked' OR action = 'purchased')
        AND alternative_brand IS NOT NULL
        GROUP BY alternative_brand
        ORDER BY count DESC;
        """

        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, positiveQuery, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let brandPtr = sqlite3_column_text(statement, 0) {
                    let brandName = String(cString: brandPtr)
                    let count = Int(sqlite3_column_int(statement, 1))
                    preferredBrands[brandName] = count
                }
            }
        } else {
            let errorMsg = dbErrorMessage()
            AppLogger.error("❌ Failed to query preferred brands: \(errorMsg)")
        }
        sqlite3_finalize(statement)

        // Query for dismissed alternatives (negative interactions)
        let dismissedQuery = """
        SELECT alternative_brand, COUNT(*) as count
        FROM alternative_interactions
        WHERE action = 'dismissed'
        AND alternative_brand IS NOT NULL
        GROUP BY alternative_brand
        ORDER BY count DESC;
        """

        if sqlite3_prepare_v2(db, dismissedQuery, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let brandPtr = sqlite3_column_text(statement, 0) {
                    let brandName = String(cString: brandPtr)
                    let count = Int(sqlite3_column_int(statement, 1))
                    dismissedBrands[brandName] = count
                }
            }
        } else {
            let errorMsg = dbErrorMessage()
            AppLogger.error("❌ Failed to query dismissed brands: \(errorMsg)")
        }
        sqlite3_finalize(statement)

        return UserBrandPreferences(
            preferredBrands: preferredBrands,
            dismissedBrands: dismissedBrands,
            preferredProductTypes: [:]
        )
    }

    // MARK: - Cloud Sync (Reinstall Recovery)

    private var hasPulledFromCloud = false

    /// Pull scan history from backend if local database is empty (reinstall recovery).
    /// Only runs once per session. Does not overwrite existing local data.
    func pullFromBackendIfNeeded() {
        guard !hasPulledFromCloud else { return }
        hasPulledFromCloud = true

        let localCount = getTotalScansCount()
        guard localCount == 0 else {
            AppLogger.debug("☁️ Local history has \(localCount) scans, skipping cloud pull")
            return
        }

        Task {
            guard let history = await NetworkService.shared.pullHistoryFromBackend(limit: 200) else { return }
            guard !history.isEmpty else { return }

            AppLogger.debug("☁️ Restoring \(history.count) scans from cloud backup")

            for entry in history {
                let id = (entry["id"] as? String) ?? UUID().uuidString
                let productName = (entry["product_name"] as? String) ?? "Unknown Product"
                let barcode = (entry["barcode"] as? String) ?? ""
                let timestamp = (entry["scanned_at"] as? Double) ?? Date().timeIntervalSince1970
                let healthScore = (entry["health_score"] as? Double) ?? 0
                let co2 = (entry["co2_emissions"] as? Double) ?? 0
                let water = (entry["water_usage"] as? Double) ?? 0
                let animalImpact = (entry["animal_impact"] as? String) ?? "Unknown"
                let violations = (entry["violations"] as? [String]) ?? []
                let isSafe = violations.isEmpty

                let scan = ScanHistory(
                    id: UUID(uuidString: id) ?? UUID(),
                    timestamp: Date(timeIntervalSince1970: timestamp),
                    productName: productName,
                    barcode: barcode,
                    sourceType: "cloud_restore",
                    isSafe: isSafe,
                    violationsCount: violations.count,
                    violations: violations,
                    co2Emissions: co2,
                    waterUsage: water,
                    animalImpact: animalImpact,
                    healthScore: healthScore,
                    concernsCount: 0,
                    purchaseDecision: .scanned
                )
                saveScan(scan)
            }

            AppLogger.debug("☁️ Restored \(history.count) scans from cloud")
        }
    }
}

//
//  DatabaseManager.swift
//  Ethica
//
//  Provides a SQLite.swift Connection for advanced services
//  (TasteProfileService, ReviewService, ImpactService)
//

import Foundation

#if canImport(SQLite)
import SQLite
#endif

#if canImport(SQLite)
class DatabaseManager {
    static let shared = DatabaseManager()

    let db: Connection?

    /// Read-only connection to the main history database for ImpactService queries.
    /// Lazily reconnects if nil — handles the case where HistoryService creates the
    /// sqlite file AFTER DatabaseManager was first initialized.
    private var _historyDb: Connection?
    private let historyDbPath: String

    var historyDb: Connection? {
        if _historyDb == nil {
            do {
                _historyDb = try Connection(historyDbPath, readonly: true)
            } catch {
                // File still doesn't exist — HistoryService hasn't saved anything yet
            }
        }
        return _historyDb
    }

    /// Whether the database is available for use
    var isAvailable: Bool { db != nil }

    private init() {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let advancedDbPath = documentsURL.appendingPathComponent("ethica_advanced.sqlite").path
        historyDbPath = documentsURL.appendingPathComponent("ethica_history.sqlite").path

        do {
            let connection = try Connection(advancedDbPath)
            connection.busyTimeout = 5
            db = connection
        } catch {
            AppLogger.debug("DatabaseManager: Failed to connect to advanced database: \(error.localizedDescription)")
            db = nil
        }

        do {
            _historyDb = try Connection(historyDbPath, readonly: true)
        } catch {
            _historyDb = nil
        }

        if let db = db {
            do {
                try AlternativeInteraction.createTable(db: db)
            } catch {
                AppLogger.debug("DatabaseManager: Error creating tables: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - HistoryItem (read-only wrapper for scan_history)

struct HistoryItem {
    let id: String
    let productName: String
    let barcode: String?
    let timestamp: Date
    let healthScore: Double
    let co2Emissions: Double
    let waterUsage: Double
    let purchaseDecision: String?
    let alternativeName: String?
    let alternativeCO2: Double?
    let alternativeWater: Double?
    
    static let table = Table("scan_history")
    static let idCol = Expression<String>("id")
    static let productNameCol = Expression<String>("product_name")
    static let barcodeCol = Expression<String?>("barcode")
    static let timestampCol = Expression<Double>("timestamp")
    static let healthScoreCol = Expression<Double>("health_score")
    static let co2EmissionsCol = Expression<Double>("co2_emissions")
    static let waterUsageCol = Expression<Double>("water_usage")
    static let purchaseDecisionCol = Expression<String?>("purchase_decision")
    static let alternativeNameCol = Expression<String?>("alternative_name")
    static let alternativeCO2Col = Expression<Double?>("alternative_co2")
    static let alternativeWaterCol = Expression<Double?>("alternative_water")
    
    /// CO2 saved: for "alternative" = original - alternative; for "avoided" = full emissions saved
    var co2Saved: Double? {
        if purchaseDecision == "alternative", let altCO2 = alternativeCO2 {
            let savings = co2Emissions - altCO2
            return savings > 0 ? savings : nil
        } else if purchaseDecision == "avoided" {
            // Avoiding a product saves its full CO2 emissions
            return co2Emissions > 0 ? co2Emissions : nil
        }
        return nil
    }
    
    /// Water saved: for "alternative" = original - alternative; for "avoided" = full usage saved
    var waterSaved: Double? {
        if purchaseDecision == "alternative", let altWater = alternativeWater {
            let savings = waterUsage - altWater
            return savings > 0 ? savings : nil
        } else if purchaseDecision == "avoided" {
            // Avoiding a product saves its full water usage
            return waterUsage > 0 ? waterUsage : nil
        }
        return nil
    }
}

// MARK: - AlternativeInteraction (SQLite.swift table)

struct AlternativeInteraction: Identifiable, Codable {
    let id: UUID
    let alternativeName: String
    let alternativeBrand: String?
    let originalProduct: String
    let action: String
    let timestamp: Date
    
    static let table = Table("alternative_interactions")
    static let idCol = Expression<String>("id")
    static let alternativeNameCol = Expression<String>("alternative_name")
    static let alternativeBrandCol = Expression<String?>("alternative_brand")
    static let originalProductCol = Expression<String>("original_product")
    static let actionCol = Expression<String>("action")
    static let timestampCol = Expression<Date>("timestamp")
    
    static func createTable(db: Connection) throws {
        try db.run(table.create(ifNotExists: true) { t in
            t.column(idCol, primaryKey: true)
            t.column(alternativeNameCol)
            t.column(alternativeBrandCol)
            t.column(originalProductCol)
            t.column(actionCol)
            t.column(timestampCol)
        })
        try db.run(table.createIndex(timestampCol, ifNotExists: true))
        try db.run(table.createIndex(actionCol, ifNotExists: true))
    }
}
#else
final class DatabaseManager {
    static let shared = DatabaseManager()

    let db: Any? = nil
    var historyDb: Any? { nil }
    var isAvailable: Bool { false }

    private init() {
        AppLogger.warning("DatabaseManager: SQLite unavailable, database-backed services disabled")
    }
}

struct HistoryItem {
    let id: String
    let productName: String
    let barcode: String?
    let timestamp: Date
    let healthScore: Double
    let co2Emissions: Double
    let waterUsage: Double
    let purchaseDecision: String?
    let alternativeName: String?
    let alternativeCO2: Double?
    let alternativeWater: Double?

    var co2Saved: Double? {
        if purchaseDecision == "alternative", let altCO2 = alternativeCO2 {
            let savings = co2Emissions - altCO2
            return savings > 0 ? savings : nil
        } else if purchaseDecision == "avoided" {
            return co2Emissions > 0 ? co2Emissions : nil
        }
        return nil
    }

    var waterSaved: Double? {
        if purchaseDecision == "alternative", let altWater = alternativeWater {
            let savings = waterUsage - altWater
            return savings > 0 ? savings : nil
        } else if purchaseDecision == "avoided" {
            return waterUsage > 0 ? waterUsage : nil
        }
        return nil
    }
}

struct AlternativeInteraction: Identifiable, Codable {
    let id: UUID
    let alternativeName: String
    let alternativeBrand: String?
    let originalProduct: String
    let action: String
    let timestamp: Date
}
#endif

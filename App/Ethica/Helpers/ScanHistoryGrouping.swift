//
//  ScanHistoryGrouping.swift
//  Ethica
//
//  Helper for grouping scan history by time periods
//

import Foundation

struct ScanHistoryGroup: Identifiable {
    let id = UUID()
    let title: String
    let date: Date
    let scans: [ScanHistory]

    var safeCount: Int {
        scans.filter { $0.isSafe }.count
    }

    var violationCount: Int {
        scans.filter { !$0.isSafe }.count
    }

    var totalCO2: Double {
        scans.reduce(0) { $0 + $1.co2Emissions }
    }

    var avgHealthScore: Double {
        guard !scans.isEmpty else { return 0 }
        return scans.map { $0.healthScore }.reduce(0, +) / Double(scans.count)
    }
}

extension Array where Element == ScanHistory {
    /// Group scans by date sections (Today, Yesterday, This Week, Older)
    func groupedByTimeframe() -> [ScanHistoryGroup] {
        let calendar = Calendar.current
        let now = Date()

        // Define time boundaries
        let todayStart = calendar.startOfDay(for: now)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let weekAgoStart = calendar.date(byAdding: .day, value: -7, to: todayStart) ?? todayStart

        // Group scans
        var groups: [ScanHistoryGroup] = []

        // Today
        let todayScans = self.filter { $0.timestamp >= todayStart }
        if !todayScans.isEmpty {
            groups.append(ScanHistoryGroup(
                title: "Today",
                date: todayStart,
                scans: todayScans
            ))
        }

        // Yesterday
        let yesterdayScans = self.filter {
            $0.timestamp >= yesterdayStart && $0.timestamp < todayStart
        }
        if !yesterdayScans.isEmpty {
            groups.append(ScanHistoryGroup(
                title: "Yesterday",
                date: yesterdayStart,
                scans: yesterdayScans
            ))
        }

        // This Week (excluding today and yesterday)
        let thisWeekScans = self.filter {
            $0.timestamp >= weekAgoStart && $0.timestamp < yesterdayStart
        }
        if !thisWeekScans.isEmpty {
            groups.append(ScanHistoryGroup(
                title: "This Week",
                date: weekAgoStart,
                scans: thisWeekScans
            ))
        }

        // Older (grouped by week)
        let olderScans = self.filter { $0.timestamp < weekAgoStart }
        let olderGrouped = Dictionary(grouping: olderScans) { scan -> Date in
            // Get start of week for each scan
            let weekOfYear = calendar.component(.weekOfYear, from: scan.timestamp)
            let year = calendar.component(.year, from: scan.timestamp)
            var components = DateComponents()
            components.yearForWeekOfYear = year
            components.weekOfYear = weekOfYear
            return calendar.date(from: components) ?? scan.timestamp
        }

        for (weekStart, scans) in olderGrouped.sorted(by: { $0.key > $1.key }) {
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"

            let title = "\(formatter.string(from: weekStart)) - \(formatter.string(from: weekEnd))"

            groups.append(ScanHistoryGroup(
                title: title,
                date: weekStart,
                scans: scans
            ))
        }

        return groups
    }

    /// Group scans by individual days
    func groupedByDay() -> [ScanHistoryGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: self) { scan -> Date in
            calendar.startOfDay(for: scan.timestamp)
        }

        return grouped.map { (date, scans) in
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"

            return ScanHistoryGroup(
                title: formatter.string(from: date),
                date: date,
                scans: scans.sorted { $0.timestamp > $1.timestamp }
            )
        }.sorted { $0.date > $1.date }
    }
}

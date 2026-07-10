import Foundation

// MARK: - Scanner (incremental, per-file cached)

/// The read side the app depends on: a snapshot of Claude Code usage costs.
/// A protocol so `AppCoordinator` could be tested against a fake without
/// touching the filesystem.
protocol UsageScanning {
    func scan() -> Snapshot
}

final class UsageScanner: UsageScanning {
    private let projectsDirectory: URL
    private var fileCache: [String: (modified: Date, size: Int, entries: [UsageEntry])] = [:]

    init() {
        projectsDirectory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    /// Re-scan changed files and produce a fresh aggregated snapshot.
    func scan() -> Snapshot {
        refreshCache()
        let entries = fileCache.values.flatMap(\.entries)
        return Self.aggregate(entries: entries, now: Date(),
                               billingCycleResetDay: Config.billingCycleResetDay,
                               monthlyBudgetDollars: Config.monthlyBudgetDollars)
    }

    private func refreshCache() {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projectsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var seenPaths = Set<String>()
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let path = url.path
            seenPaths.insert(path)
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modified = values?.contentModificationDate ?? .distantPast
            let size = values?.fileSize ?? 0
            if let cached = fileCache[path], cached.modified == modified, cached.size == size {
                continue
            }
            fileCache[path] = (modified, size, Self.parseFile(at: url))
        }
        // Drop deleted files.
        for path in fileCache.keys where !seenPaths.contains(path) {
            fileCache.removeValue(forKey: path)
        }
    }

    private static func parseFile(at url: URL) -> [UsageEntry] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let fallbackProjectName = url.deletingLastPathComponent().lastPathComponent
        return content.split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { parseLine(String($0), fallbackProjectName: fallbackProjectName) }
    }

    // MARK: Pure parsing (unit-tested directly, no filesystem)

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoParserNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parses one `~/.claude/projects/**/*.jsonl` line into a `UsageEntry`, or
    /// nil for lines with no usage, no billable model, or malformed JSON.
    static func parseLine(_ line: String, fallbackProjectName: String) -> UsageEntry? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any]
        else { return nil }

        let model = (message["model"] as? String) ?? "unknown"
        guard Pricing.rates(forModel: model) != nil else { return nil }

        guard let date = parseDate(object["timestamp"]) else { return nil }

        let messageId = (message["id"] as? String) ?? (object["uuid"] as? String) ?? ""
        let requestId = (object["requestId"] as? String) ?? ""
        let dedupeKey = messageId + "|" + requestId

        let cacheCreation = usage["cache_creation"] as? [String: Any]
        let write5m = (cacheCreation?["ephemeral_5m_input_tokens"] as? Int)
            ?? (usage["cache_creation_input_tokens"] as? Int) ?? 0
        let write1h = (cacheCreation?["ephemeral_1h_input_tokens"] as? Int) ?? 0

        return UsageEntry(
            dedupeKey: dedupeKey,
            timestamp: date,
            projectName: projectName(fromCwd: object["cwd"] as? String, fallback: fallbackProjectName),
            model: model,
            inputTokens: (usage["input_tokens"] as? Int) ?? 0,
            outputTokens: (usage["output_tokens"] as? Int) ?? 0,
            cacheReadTokens: (usage["cache_read_input_tokens"] as? Int) ?? 0,
            cacheWrite5mTokens: write5m,
            cacheWrite1hTokens: write1h
        )
    }

    private static func parseDate(_ raw: Any?) -> Date? {
        guard let string = raw as? String else { return nil }
        return isoParser.date(from: string) ?? isoParserNoFraction.date(from: string)
    }

    /// The session's working-directory basename, or `fallback` (the project
    /// directory under `~/.claude/projects`) when `cwd` is missing or empty.
    static func projectName(fromCwd cwd: String?, fallback: String) -> String {
        if let cwd, !cwd.isEmpty {
            let name = (cwd as NSString).lastPathComponent
            if !name.isEmpty { return name }
        }
        return fallback
    }

    // MARK: Pure aggregation (unit-tested directly)

    /// Buckets `entries` into the numbers the popover renders: today's spend,
    /// month-to-date (from `billingCycleResetDay`), projection, busiest day,
    /// per-model and per-project breakdowns, hourly-today, and the 14-day
    /// sparkline. Dedupes by `UsageEntry.dedupeKey` across all entries.
    static func aggregate(entries: [UsageEntry], now: Date, billingCycleResetDay: Int,
                           monthlyBudgetDollars: Double, calendar: Calendar = .current) -> Snapshot {
        let todayStart = calendar.startOfDay(for: now)
        let monthStart = cycleStart(for: now, resetDay: billingCycleResetDay, calendar: calendar)

        var seen = Set<String>()
        var costByDay: [Date: Double] = [:]
        var costByModelMonth: [String: Double] = [:]
        var costByProjectToday: [String: Double] = [:]
        var hourlyToday = [Double](repeating: 0, count: 24)
        var inputTokensToday = 0
        var outputTokensToday = 0

        for entry in entries {
            if !entry.dedupeKey.isEmpty {
                if seen.contains(entry.dedupeKey) { continue }
                seen.insert(entry.dedupeKey)
            }
            let cost = entry.cost
            let dayStart = calendar.startOfDay(for: entry.timestamp)
            costByDay[dayStart, default: 0] += cost

            if entry.timestamp >= monthStart {
                costByModelMonth[friendlyModel(entry.model), default: 0] += cost
            }
            if entry.timestamp >= todayStart {
                costByProjectToday[entry.projectName, default: 0] += cost
                let hour = calendar.component(.hour, from: entry.timestamp)
                hourlyToday[min(max(hour, 0), 23)] += cost
                inputTokensToday += entry.inputTokens + entry.cacheReadTokens
                    + entry.cacheWrite5mTokens + entry.cacheWrite1hTokens
                outputTokensToday += entry.outputTokens
            }
        }

        var snapshot = Snapshot()
        snapshot.todayCost = costByDay[todayStart] ?? 0
        snapshot.monthCost = costByDay.filter { $0.key >= monthStart }.values.reduce(0, +)
        snapshot.hourlyToday = hourlyToday
        snapshot.inputTokensToday = inputTokensToday
        snapshot.outputTokensToday = outputTokensToday
        snapshot.lastRefresh = now
        snapshot.monthlyBudgetDollars = monthlyBudgetDollars

        // Month projection from average spend per elapsed day of the cycle.
        let nextCycleStart = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let daysElapsed = (calendar.dateComponents([.day], from: monthStart, to: todayStart).day ?? 0) + 1
        let daysInCycle = calendar.dateComponents([.day], from: monthStart, to: nextCycleStart).day ?? 30
        if daysElapsed > 0 {
            snapshot.projectedMonthCost = snapshot.monthCost / Double(daysElapsed) * Double(daysInCycle)
        }

        // Average over active days this month + busiest day this month.
        let monthDays = costByDay.filter { $0.key >= monthStart && $0.value > 0 }
        if !monthDays.isEmpty {
            snapshot.averagePerActiveDay = monthDays.values.reduce(0, +) / Double(monthDays.count)
            if let busiest = monthDays.max(by: { $0.value < $1.value }) {
                snapshot.busiestDayLabel = shortDayFormatter.string(from: busiest.key)
                snapshot.busiestDayCost = busiest.value
            }
        }

        snapshot.costByModelThisMonth = costByModelMonth
            .map { (name: $0.key, cost: $0.value) }
            .sorted { $0.cost > $1.cost }
        snapshot.topProjectsToday = costByProjectToday
            .map { (name: $0.key, cost: $0.value) }
            .sorted { $0.cost > $1.cost }
            .prefix(5)
            .map { $0 }

        // Last 14 days, oldest first.
        snapshot.last14Days = (0..<14).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { return nil }
            return DailyTotal(dayStart: day, cost: costByDay[day] ?? 0)
        }

        return snapshot
    }

    private static func friendlyModel(_ model: String) -> String {
        let m = model.lowercased()
        if m.contains("opus-4-8") { return "Opus 4.8" }
        if m.contains("opus") { return "Opus" }
        if m.contains("sonnet") { return "Sonnet" }
        if m.contains("haiku") { return "Haiku" }
        if m.contains("fable") { return "Fable" }
        return model
    }

    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// Start of the current billing cycle: `resetDay` of this month if `date`
    /// is on or after it, otherwise `resetDay` of the previous month.
    /// `resetDay` 1 reproduces plain calendar-month boundaries.
    static func cycleStart(for date: Date, resetDay: Int, calendar: Calendar) -> Date {
        let dayOfMonth = calendar.component(.day, from: date)
        let anchorMonth = dayOfMonth >= resetDay ? date : (calendar.date(byAdding: .month, value: -1, to: date) ?? date)
        var components = calendar.dateComponents([.year, .month], from: anchorMonth)
        components.day = resetDay
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }
}

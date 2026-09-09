import Foundation

// MARK: - Decoding and validating the pricing feed

/// Why a pricing document was refused. Every rejection keeps the previously
/// loaded catalog in use, so a bad publish can never zero out a user's costs.
enum PricingCatalogError: Error, Equatable, CustomStringConvertible {
    case malformedJSON
    /// The feed declares a schema this build predates.
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case noModels
    case invalidModel(id: String, reason: String)
    case unknownFallbackModelId(String)

    var description: String {
        switch self {
        case .malformedJSON:
            return "pricing feed is not valid JSON in the expected shape"
        case let .unsupportedSchemaVersion(found, supported):
            return "pricing feed schemaVersion \(found) is newer than this app supports (\(supported))"
        case .noModels:
            return "pricing feed lists no models"
        case let .invalidModel(id, reason):
            return "pricing feed model '\(id)' is invalid: \(reason)"
        case let .unknownFallbackModelId(id):
            return "pricing feed fallbackModelId '\(id)' matches no model"
        }
    }
}

/// Turns published feed bytes into a validated `PricingCatalog`, or throws.
enum PricingCatalogDecoder {
    /// Rates above this are assumed to be a typo (a misplaced decimal point or
    /// a per-token figure published as per-million) rather than a real price.
    static let maximumPlausibleRatePerMillion: Double = 1_000

    static func decode(_ data: Data, origin: PricingCatalogOrigin) throws -> PricingCatalog {
        guard let document = try? JSONDecoder().decode(FeedDocument.self, from: data) else {
            throw PricingCatalogError.malformedJSON
        }
        return try catalog(from: document, origin: origin)
    }

    // MARK: Wire format

    /// The on-the-wire shape of `docs/pricing.json`. Kept separate from
    /// `PricingCatalog` so the domain type never carries optional wire fields.
    private struct FeedDocument: Decodable {
        let schemaVersion: Int
        let updatedAt: String
        let source: String?
        let fallbackModelId: String?
        let defaultCacheMultipliers: WireCacheMultipliers?
        let models: [WireModel]
    }

    private struct WireCacheMultipliers: Decodable {
        let read: Double
        let write5m: Double
        let write1h: Double
    }

    private struct WireModel: Decodable {
        let id: String
        let displayName: String
        let family: String
        let legacy: Bool?
        let match: [String]
        let periods: [WirePeriod]
    }

    private struct WirePeriod: Decodable {
        let from: String?
        let until: String?
        let inputPerMillion: Double
        let outputPerMillion: Double
        let cacheReadPerMillion: Double?
        let cacheWrite5mPerMillion: Double?
        let cacheWrite1hPerMillion: Double?
    }

    // MARK: Validation

    private static func catalog(from document: FeedDocument, origin: PricingCatalogOrigin) throws -> PricingCatalog {
        guard document.schemaVersion >= 1 else {
            throw PricingCatalogError.malformedJSON
        }
        guard document.schemaVersion <= PricingCatalog.supportedSchemaVersion else {
            throw PricingCatalogError.unsupportedSchemaVersion(
                found: document.schemaVersion, supported: PricingCatalog.supportedSchemaVersion)
        }
        guard !document.models.isEmpty else { throw PricingCatalogError.noModels }

        let models = try document.models.map(validatedModel)

        if let fallbackModelId = document.fallbackModelId,
           !models.contains(where: { $0.id == fallbackModelId }) {
            throw PricingCatalogError.unknownFallbackModelId(fallbackModelId)
        }

        let multipliers = document.defaultCacheMultipliers.map {
            CacheMultipliers(read: $0.read, write5m: $0.write5m, write1h: $0.write1h)
        } ?? .anthropicDefaults

        return PricingCatalog(
            schemaVersion: document.schemaVersion,
            updatedAt: document.updatedAt,
            source: document.source,
            origin: origin,
            models: models,
            fallbackModelId: document.fallbackModelId,
            cacheMultipliers: multipliers)
    }

    private static func validatedModel(_ model: WireModel) throws -> ModelPricing {
        func reject(_ reason: String) -> PricingCatalogError {
            .invalidModel(id: model.id, reason: reason)
        }

        guard !model.id.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PricingCatalogError.invalidModel(id: "(empty)", reason: "empty id")
        }
        let patterns = model.match
            .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !patterns.isEmpty else { throw reject("no match patterns") }
        guard !model.periods.isEmpty else { throw reject("no price periods") }

        var periods: [PricePeriod] = []
        for period in model.periods {
            periods.append(try validatedPeriod(period, reject: reject))
        }
        try assertPeriodsDoNotOverlap(periods, reject: reject)

        return ModelPricing(
            id: model.id,
            displayName: model.displayName,
            family: model.family,
            legacy: model.legacy ?? false,
            match: patterns,
            periods: periods)
    }

    private static func validatedPeriod(
        _ period: WirePeriod,
        reject: (String) -> PricingCatalogError
    ) throws -> PricePeriod {
        for (name, value) in [("inputPerMillion", period.inputPerMillion),
                              ("outputPerMillion", period.outputPerMillion)] {
            guard value > 0 else { throw reject("\(name) must be greater than 0") }
            guard value <= maximumPlausibleRatePerMillion else {
                throw reject("\(name) \(value) exceeds the plausible maximum")
            }
        }
        let optionalRates = [("cacheReadPerMillion", period.cacheReadPerMillion),
                             ("cacheWrite5mPerMillion", period.cacheWrite5mPerMillion),
                             ("cacheWrite1hPerMillion", period.cacheWrite1hPerMillion)]
        for (name, value) in optionalRates {
            guard let value else { continue }
            guard value >= 0 else { throw reject("\(name) must not be negative") }
            guard value <= maximumPlausibleRatePerMillion else {
                throw reject("\(name) \(value) exceeds the plausible maximum")
            }
        }

        let from = try parsedBoundary(period.from, name: "from", reject: reject)
        let until = try parsedBoundary(period.until, name: "until", reject: reject)
        if let from, let until, from >= until {
            throw reject("period 'from' must precede 'until'")
        }

        return PricePeriod(
            from: from,
            until: until,
            inputPerMillion: period.inputPerMillion,
            outputPerMillion: period.outputPerMillion,
            cacheReadPerMillion: period.cacheReadPerMillion,
            cacheWrite5mPerMillion: period.cacheWrite5mPerMillion,
            cacheWrite1hPerMillion: period.cacheWrite1hPerMillion)
    }

    private static func parsedBoundary(
        _ raw: String?,
        name: String,
        reject: (String) -> PricingCatalogError
    ) throws -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let date = parseFeedDate(raw) else {
            throw reject("\(name) '\(raw)' is not a YYYY-MM-DD or ISO 8601 date")
        }
        return date
    }

    /// Periods must describe one unambiguous price at every instant, else the
    /// cost of a given day would depend on array order.
    private static func assertPeriodsDoNotOverlap(
        _ periods: [PricePeriod],
        reject: (String) -> PricingCatalogError
    ) throws {
        let sorted = periods.sorted { ($0.from ?? .distantPast) < ($1.from ?? .distantPast) }
        for (earlier, later) in zip(sorted, sorted.dropFirst()) {
            let earlierEnd = earlier.until ?? .distantFuture
            let laterStart = later.from ?? .distantPast
            guard laterStart >= earlierEnd else { throw reject("price periods overlap") }
        }
    }
}

/// Parses a feed date: either a plain `YYYY-MM-DD` calendar day (interpreted as
/// UTC midnight) or a full ISO 8601 timestamp.
func parseFeedDate(_ raw: String) -> Date? {
    let dayOnly = DateFormatter()
    dayOnly.calendar = Calendar(identifier: .gregorian)
    dayOnly.locale = Locale(identifier: "en_US_POSIX")
    dayOnly.timeZone = TimeZone(identifier: "UTC")
    dayOnly.dateFormat = "yyyy-MM-dd"
    if let date = dayOnly.date(from: raw) { return date }

    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    if let date = iso.date(from: raw) { return date }
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return iso.date(from: raw)
}

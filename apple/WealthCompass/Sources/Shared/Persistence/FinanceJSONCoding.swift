import Foundation

enum FinanceJSONCoding {
    static func makeEncoder(prettyPrinted: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(format(date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self), let date = parse(string) {
                return date
            }
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: timestamp)
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 date string or Unix timestamp."
            )
        }
        return decoder
    }

    // WC-M4: reuse configured coders instead of building a fresh one per call. `JSONEncoder` /
    // `JSONDecoder` are safe to share across concurrent encode/decode once configured, and the
    // custom date strategies close over the cached, thread-safe ISO-8601 formatters below — so a
    // dataset encode no longer allocates O(entities) coders (which compounded with sync send batches).
    // Two encoders are cached because `makeEncoder` is parameterized by `prettyPrinted`.
    private static let compactEncoder = makeEncoder(prettyPrinted: false)
    private static let prettyEncoder = makeEncoder(prettyPrinted: true)
    private static let sharedDecoder = makeDecoder()

    static func encode<T: Encodable>(_ value: T, prettyPrinted: Bool = false) throws -> Data {
        try (prettyPrinted ? prettyEncoder : compactEncoder).encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try sharedDecoder.decode(type, from: data)
    }

    static func decodeFinancialData(
        from sourceData: Data
    ) throws -> (data: FinancialData, wasMigrated: Bool, skippedRecordKeys: [CloudSyncRecordKey]) {
        let migratedData = try migrateLegacyFinancialDataJSON(sourceData)
        let wasMigrated = migratedData != sourceData
        do {
            // Fast path: strict whole-file decode — unchanged for the overwhelmingly common case.
            let data = try decode(FinancialData.self, from: migratedData)
            return (data, wasMigrated, [])
        } catch {
            // Deep-audit H08: a single undecodable record (e.g. an unknown enum value written by a
            // newer app version and synced back via iCloud) used to fail the *whole-file* decode,
            // making the entire local dataset appear empty. Fall back to a per-collection lossy
            // decode that keeps every good record and reports the keys it had to skip, so the sync
            // layer can preserve them instead of tombstoning them.
            return try decodeFinancialDataLossily(from: migratedData, wasMigrated: wasMigrated)
        }
    }

    /// Per-collection, element-by-element decode used only when the strict decode fails (H08). Each
    /// undecodable record is dropped from the in-memory data, and — when its `id` can be salvaged —
    /// its record key is returned so the caller keeps it out of the delete/tombstone path.
    private static func decodeFinancialDataLossily(
        from data: Data,
        wasMigrated: Bool
    ) throws -> (data: FinancialData, wasMigrated: Bool, skippedRecordKeys: [CloudSyncRecordKey]) {
        guard case .object(let root)? = try? jsonValueDecoder.decode(JSONValue.self, from: data) else {
            // Not even a JSON object: nothing to salvage — surface the original strict-decode error.
            return (try decode(FinancialData.self, from: data), wasMigrated, [])
        }
        let decoder = sharedDecoder  // WC-M4: reuse the cached decoder
        var skipped: [CloudSyncRecordKey] = []

        func decodeCollection<T: Decodable>(
            _ key: String,
            as type: T.Type,
            recordType: CloudSyncRecordType
        ) -> [T] {
            guard case .array(let rawElements)? = root[key] else { return [] }
            var out: [T] = []
            out.reserveCapacity(rawElements.count)
            for element in rawElements {
                if let elementData = try? jsonValueEncoder.encode(element),
                   let decoded = try? decoder.decode(T.self, from: elementData) {
                    out.append(decoded)
                } else {
                    salvageSkippedKey(from: element, recordType: recordType, into: &skipped)
                }
            }
            return out
        }

        let financialData = FinancialData(
            transactions: decodeCollection("transactions", as: Transaction.self, recordType: .transaction),
            recurringTransactions: decodeCollection("recurringTransactions", as: RecurringTransaction.self, recordType: .recurringTransaction),
            investments: decodeCollection("investments", as: Investment.self, recordType: .investment),
            crypto: decodeCollection("crypto", as: CryptoHolding.self, recordType: .crypto),
            liabilities: decodeCollection("liabilities", as: Liability.self, recordType: .liability),
            snapshots: decodeCollection("snapshots", as: NetWorthSnapshot.self, recordType: .snapshot)
        )
        return (financialData, wasMigrated, skipped)
    }

    private static func salvageSkippedKey(
        from element: JSONValue,
        recordType: CloudSyncRecordType,
        into skipped: inout [CloudSyncRecordKey]
    ) {
        guard
            case .object(let object) = element,
            case .string(let idString)? = object["id"],
            let id = UUID(uuidString: idString)
        else {
            return
        }
        skipped.append(CloudSyncRecordKey(type: recordType, id: id))
    }

    // WC-M4: cache the ISO-8601 formatters instead of allocating one per date value.
    // `ISO8601DateFormatter` is thread-safe for format/parse, so static reuse is safe even with
    // concurrent encode/decode, and avoids the notoriously expensive per-date construction
    // that previously dominated save/sync CPU.
    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func format(_ date: Date) -> String {
        iso8601WithFractionalSeconds.string(from: date)
    }

    private static func parse(_ value: String) -> Date? {
        iso8601WithFractionalSeconds.date(from: value) ?? iso8601.date(from: value)
    }

    private static func migrateLegacyFinancialDataJSON(_ data: Data) throws -> Data {
        // Detect first, with `JSONSerialization`. Building the `Decimal`-backed tree is roughly an
        // order of magnitude more expensive (its `try?` trial decoding constructs and discards a
        // `DecodingError` per candidate type), and this runs on the main actor during
        // `FinanceStore.init` on *every* launch — while almost no file needs healing at all.
        // Detection only asks whether two date keys are present, so the Double-mangled numbers
        // `JSONSerialization` produces are irrelevant here; nothing it parses is ever written back.
        guard needsDateHealing(data) else { return data }
        guard case .object(var root)? = try? jsonValueDecoder.decode(JSONValue.self, from: data) else {
            return data
        }

        var changed = false
        // Heal the two non-optional `Date` fields (`updatedAt`, `createdAt`) when they are **absent
        // or explicitly `null`** (deep-audit H10). A JSON `null` decodes to `NSNull` — which is not
        // `nil` in Swift — so the old `== nil` check silently skipped it, and the null then failed the
        // whole-file decode (a non-optional `Date` can't decode from null). `updatedAt` is healed
        // first from `createdAt`/`date`, then `createdAt` from the (now-present) `updatedAt`/`date`.
        let dateHealing: [(collection: String, extraFallbacks: [String])] = [
            ("transactions", ["date"]),
            ("recurringTransactions", ["startDate"]),
            ("investments", []),
            ("crypto", []),
            ("liabilities", []),
            ("snapshots", ["date"])
        ]
        for (collectionKey, extraFallbacks) in dateHealing {
            changed = healDate("updatedAt", to: collectionKey, fallbacks: ["createdAt"] + extraFallbacks, in: &root) || changed
            changed = healDate("createdAt", to: collectionKey, fallbacks: ["updatedAt"] + extraFallbacks, in: &root) || changed
        }

        guard changed else { return data }
        return try jsonValueEncoder.encode(JSONValue.object(root))
    }

    /// Fills `field` on every record in `collectionKey` that is missing or explicitly `null`, taking
    /// the first `fallbacks` value that is itself present and non-null. Returns whether anything changed.
    private static func healDate(
        _ field: String,
        to collectionKey: String,
        fallbacks: [String],
        in root: inout [String: JSONValue]
    ) -> Bool {
        guard case .array(let rawRecords)? = root[collectionKey] else { return false }
        var records = rawRecords
        var changed = false

        for index in records.indices {
            guard case .object(var record) = records[index], isMissingOrNull(record[field]) else { continue }
            guard let fallbackValue = fallbacks.lazy
                .compactMap({ key -> JSONValue? in
                    let value = record[key]
                    return isMissingOrNull(value) ? nil : value
                })
                .first
            else {
                continue
            }
            record[field] = fallbackValue
            records[index] = .object(record)
            changed = true
        }

        if changed {
            root[collectionKey] = .array(records)
        }
        return changed
    }

    /// Cheap pre-check: does any record lack a usable `createdAt`/`updatedAt`?
    private static func needsDateHealing(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Unparseable here means the strict decode will fail too and the salvage path takes
            // over; healing could not have helped either way.
            return false
        }
        for collectionKey in healedCollections {
            guard let records = root[collectionKey] as? [[String: Any]] else { continue }
            let missing = records.contains { record in
                ["createdAt", "updatedAt"].contains { record[$0] == nil || record[$0] is NSNull }
            }
            if missing { return true }
        }
        return false
    }

    private static let healedCollections = [
        "transactions", "recurringTransactions", "investments", "crypto", "liabilities", "snapshots",
    ]

    /// A JSON key that is absent, or present with an explicit `null`.
    private static func isMissingOrNull(_ value: JSONValue?) -> Bool {
        guard let value else { return true }
        if case .null = value { return true }
        return false
    }

    // MARK: - Precision-preserving generic JSON

    /// A generic JSON value whose numbers are `Decimal`.
    ///
    /// Both the date-healing migration and the H08 lossy-salvage decode used to go through
    /// `JSONSerialization`, which parses every fractional number as a binary `Double`. That is
    /// lossy for ordinary money: `1234.56` came back as `1234.5599999999999`, `0.1` as
    /// `0.10000000000000001`, `99999999.99` as `99999999.989999995`. The migration then *persisted*
    /// those values, so healing one missing `createdAt` silently rewrote every amount in the file,
    /// changed every record's sync hash, and re-uploaded the whole dataset to CloudKit.
    ///
    /// `JSONDecoder`/`JSONEncoder` read and write `Decimal` from the raw token, so routing both
    /// paths through this type keeps WC-A1's invariant — money never passes through binary
    /// floating point outside charts and FX — true inside persistence itself.
    indirect enum JSONValue: Codable {
        case null
        case bool(Bool)
        case number(Decimal)
        /// Only for numbers outside `Decimal`'s range — see `init(from:)`.
        case double(Double)
        case string(String)
        case array([JSONValue])
        case object([String: JSONValue])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .null; return }
            // Bool before Decimal: `true`/`false` would otherwise decode as 1/0 on some platforms.
            if let value = try? container.decode(Bool.self) { self = .bool(value); return }
            if let value = try? container.decode(Decimal.self) { self = .number(value); return }
            // `Decimal` cannot decode every JSON number: it throws for |x| >= 1e128 and for a
            // nonzero |x| below ~1e-129, where `JSONSerialization` simply parsed. Falling through
            // to an error would fail the *entire* document — and this type is the entry point for
            // the H08 lossy-salvage decode, whose whole job is to rescue a file that already
            // contains something unreadable. One runaway value would take every healthy record
            // with it, leaving the user on the recovery screen whose only action is to erase.
            // Keep it as a `Double`: imprecise, but no money the app could ever have stored is in
            // that range, and the alternative is losing the file.
            if let value = try? container.decode(Double.self) { self = .double(value); return }
            if let value = try? container.decode(String.self) { self = .string(value); return }
            if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
            self = .object(try container.decode([String: JSONValue].self))
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .null: try container.encodeNil()
            case .bool(let value): try container.encode(value)
            case .number(let value): try container.encode(value)
            case .double(let value): try container.encode(value)
            case .string(let value): try container.encode(value)
            case .array(let value): try container.encode(value)
            case .object(let value): try container.encode(value)
            }
        }
    }

    /// Deliberately plain: no date strategy, because `JSONValue` keeps dates as the strings they
    /// already are in the file and must not reinterpret them.
    private static let jsonValueDecoder = JSONDecoder()

    private static let jsonValueEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}

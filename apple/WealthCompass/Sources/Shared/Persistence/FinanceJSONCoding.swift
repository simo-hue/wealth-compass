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

    static func encode<T: Encodable>(_ value: T, prettyPrinted: Bool = false) throws -> Data {
        try makeEncoder(prettyPrinted: prettyPrinted).encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try makeDecoder().decode(type, from: data)
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
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Not even a JSON object: nothing to salvage — surface the original strict-decode error.
            return (try decode(FinancialData.self, from: data), wasMigrated, [])
        }
        let decoder = makeDecoder()
        var skipped: [CloudSyncRecordKey] = []

        func decodeCollection<T: Decodable>(
            _ key: String,
            as type: T.Type,
            recordType: CloudSyncRecordType
        ) -> [T] {
            guard let rawElements = root[key] as? [Any] else { return [] }
            var out: [T] = []
            out.reserveCapacity(rawElements.count)
            for element in rawElements {
                if let elementData = try? JSONSerialization.data(withJSONObject: element),
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
        from element: Any,
        recordType: CloudSyncRecordType,
        into skipped: inout [CloudSyncRecordKey]
    ) {
        guard
            let object = element as? [String: Any],
            let idString = object["id"] as? String,
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
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
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
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    /// Fills `field` on every record in `collectionKey` that is missing or explicitly `null`, taking
    /// the first `fallbacks` value that is itself present and non-null. Returns whether anything changed.
    private static func healDate(
        _ field: String,
        to collectionKey: String,
        fallbacks: [String],
        in root: inout [String: Any]
    ) -> Bool {
        guard var records = root[collectionKey] as? [[String: Any]] else { return false }
        var changed = false

        for index in records.indices where isMissingOrNull(records[index][field]) {
            guard let fallbackValue = fallbacks.lazy
                .compactMap({ key -> Any? in
                    let value = records[index][key]
                    return isMissingOrNull(value) ? nil : value
                })
                .first
            else {
                continue
            }
            records[index][field] = fallbackValue
            changed = true
        }

        if changed {
            root[collectionKey] = records
        }
        return changed
    }

    /// A JSON key that is absent, or present with an explicit `null` (`NSNull`) value.
    private static func isMissingOrNull(_ value: Any?) -> Bool {
        value == nil || value is NSNull
    }
}

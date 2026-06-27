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

    static func decodeFinancialData(from sourceData: Data) throws -> (data: FinancialData, wasMigrated: Bool) {
        let migratedData = try migrateLegacyFinancialDataJSON(sourceData)
        return (
            try decode(FinancialData.self, from: migratedData),
            migratedData != sourceData
        )
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
        changed = addUpdatedAt(to: "transactions", fallbacks: ["createdAt", "date"], in: &root) || changed
        changed = addUpdatedAt(to: "recurringTransactions", fallbacks: ["createdAt", "startDate"], in: &root) || changed
        changed = addUpdatedAt(to: "investments", fallbacks: ["createdAt"], in: &root) || changed
        changed = addUpdatedAt(to: "crypto", fallbacks: ["createdAt"], in: &root) || changed
        changed = addUpdatedAt(to: "liabilities", fallbacks: ["createdAt"], in: &root) || changed
        changed = addUpdatedAt(to: "snapshots", fallbacks: ["createdAt", "date"], in: &root) || changed

        guard changed else { return data }
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private static func addUpdatedAt(
        to collectionKey: String,
        fallbacks: [String],
        in root: inout [String: Any]
    ) -> Bool {
        guard var records = root[collectionKey] as? [[String: Any]] else { return false }
        var changed = false

        for index in records.indices where records[index]["updatedAt"] == nil {
            guard let fallbackValue = fallbacks.lazy.compactMap({ records[index][$0] }).first else {
                continue
            }
            records[index]["updatedAt"] = fallbackValue
            changed = true
        }

        if changed {
            root[collectionKey] = records
        }
        return changed
    }
}

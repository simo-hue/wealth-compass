import Foundation

// #region agent log
enum I18nDebugLog {
    private static let sessionId = "ed8fd0"
    private static let endpoint = "http://127.0.0.1:7504/ingest/61db8831-ab92-46de-81de-fd622a59ac18"
    private static let logPath = "/Users/simo/Downloads/DEV/wealth-compass/apple/WealthCompass/.cursor/debug-ed8fd0.log"

    static func log(
        location: String,
        message: String,
        hypothesisId: String,
        data: [String: Any] = [:],
        runId: String = "pre-fix"
    ) {
        var payload: [String: Any] = [
            "sessionId": sessionId,
            "runId": runId,
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "data": data
        ]
        guard
            let json = try? JSONSerialization.data(withJSONObject: payload),
            let line = String(data: json, encoding: .utf8)
        else { return }

        let output = line + "\n"
        if FileManager.default.fileExists(atPath: logPath),
           let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(output.data(using: .utf8)!)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: output.data(using: .utf8))
        }

        guard
            let body = try? JSONSerialization.data(withJSONObject: payload),
            let url = URL(string: endpoint)
        else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sessionId, forHTTPHeaderField: "X-Debug-Session-Id")
        request.httpBody = body
        URLSession.shared.dataTask(with: request).resume()
    }

    static func sampleResolutions(appLanguage: String?) {
        let appLocale = appLanguage.map { Locale(identifier: $0) }
        let key = "Settings"
        let systemResolved = String(localized: String.LocalizationValue(key))
        let appResolved = AppLocalization.string(String.LocalizationValue(key), appLanguage: appLanguage)
        let legacyLocaleResolved = appLocale.map { String(localized: String.LocalizationValue(key), locale: $0) } ?? systemResolved
        let sidebarCashFlow = AppLocalization.string("Cash Flow", appLanguage: appLanguage)

        log(
            location: "I18nDebugLog.swift:sampleResolutions",
            message: "localization resolution sample",
            hypothesisId: "A",
            data: [
                "appLanguage": appLanguage ?? "nil",
                "localeCurrent": Locale.current.identifier,
                "systemResolvedSettings": systemResolved,
                "appLocalizationSettings": appResolved,
                "legacyLocaleResolvedSettings": legacyLocaleResolved,
                "sidebarCashFlowLocalized": sidebarCashFlow,
                "defaultSalaryCategory": AppLocalization.string("Salary", appLanguage: appLanguage)
            ],
            runId: "post-fix"
        )
    }
}
// #endregion

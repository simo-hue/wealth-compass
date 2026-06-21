import Foundation
#if canImport(UIKit)
import UIKit
#endif

// #region agent log
enum I18nDebugLog {
    private static let sessionId = "2d3ba2"
    private static let endpoint = "http://127.0.0.1:7504/ingest/61db8831-ab92-46de-81de-fd622a59ac18"
    private static let logPath = "/Users/simo/Downloads/DEV/wealth-compass/apple/WealthCompass/.cursor/debug-2d3ba2.log"

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

#if canImport(UIKit)
    static func auditTabBarLabels(appLanguage: String?, runId: String = "pre-fix") {
        let fullKeys: [(TabBarLabelResolver.Tab, String)] = [
            (.dashboard, "Dashboard"),
            (.cashFlow, "Cash Flow"),
            (.investments, "Investments"),
            (.crypto, "Crypto"),
            (.settings, "Settings")
        ]

        let screenWidth = UIScreen.main.bounds.width
        let estimatedSlotWidth = (screenWidth - 32) / 5
        let font = UIFont.systemFont(ofSize: 10, weight: .medium)
        var labels: [[String: Any]] = []

        for (tab, fullKey) in fullKeys {
            let fullText = AppLocalization.string(String.LocalizationValue(fullKey), appLanguage: appLanguage)
            let compactText = TabBarLabelResolver.title(for: tab, appLanguage: appLanguage)
            let fullWidth = (fullText as NSString).size(withAttributes: [.font: font]).width
            let compactWidth = (compactText as NSString).size(withAttributes: [.font: font]).width
            labels.append([
                "tab": tab.rawValue,
                "fullText": fullText,
                "fullCharCount": fullText.count,
                "fullWidthPt": round(fullWidth * 10) / 10,
                "compactText": compactText,
                "compactCharCount": compactText.count,
                "compactWidthPt": round(compactWidth * 10) / 10,
                "fullExceedsSlot": fullWidth > estimatedSlotWidth,
                "compactExceedsSlot": compactWidth > estimatedSlotWidth,
                "compactUnresolvedKey": compactText.contains(", Tab Bar")
            ])
        }

        log(
            location: "I18nDebugLog.swift:auditTabBarLabels",
            message: "tab bar label width audit",
            hypothesisId: "A",
            data: [
                "appLanguage": appLanguage ?? "nil",
                "screenWidthPt": screenWidth,
                "estimatedSlotWidthPt": estimatedSlotWidth,
                "tabCount": 5,
                "labels": labels
            ],
            runId: runId
        )
    }
#endif
}
// #endregion

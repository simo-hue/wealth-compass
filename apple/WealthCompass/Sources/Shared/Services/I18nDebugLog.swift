import Foundation
import UIKit

// #region agent log
enum I18nDebugLog {
    private static let sessionId = "aa26e6"
    private static let endpoint = "http://127.0.0.1:7504/ingest/61db8831-ab92-46de-81de-fd622a59ac18"
    private static let logPath = "/Users/simo/Downloads/DEV/wealth-compass/apple/WealthCompass/.cursor/debug-aa26e6.log"

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

    static func auditPageHeaderTitle(
        titleText: String,
        containerWidth: CGFloat,
        trailingButtonWidth: CGFloat = 42,
        hStackSpacing: CGFloat = 16,
        runId: String = "pre-fix"
    ) {
        let baseFont = UIFont.systemFont(ofSize: 30, weight: .bold)
        let titleFont: UIFont = {
            guard let descriptor = baseFont.fontDescriptor.withDesign(.rounded) else { return baseFont }
            return UIFont(descriptor: descriptor, size: 30)
        }()
        let titleWidth = (titleText as NSString).size(withAttributes: [.font: titleFont]).width
        let availableTitleWidth = containerWidth - trailingButtonWidth - hStackSpacing
        let titleExceedsAvailable = titleWidth > availableTitleWidth
        let scaleFactorNeeded = titleExceedsAvailable ? (availableTitleWidth / titleWidth) : 1.0

        log(
            location: "I18nDebugLog.swift:auditPageHeaderTitle",
            message: "page header title width audit",
            hypothesisId: titleExceedsAvailable ? "H2" : "H2-ok",
            data: [
                "titleText": titleText,
                "titleCharCount": titleText.count,
                "titleWidthPt": round(titleWidth * 10) / 10,
                "containerWidthPt": round(containerWidth * 10) / 10,
                "availableTitleWidthPt": round(availableTitleWidth * 10) / 10,
                "trailingButtonWidthPt": trailingButtonWidth,
                "titleExceedsAvailable": titleExceedsAvailable,
                "scaleFactorNeeded": round(scaleFactorNeeded * 1000) / 1000,
                "titleHasLineLimit": false,
                "titleHasMinimumScaleFactor": false,
                "subtitleHasLineLimit": true,
                "subtitleHasMinimumScaleFactor": true
            ],
            runId: runId
        )

        if titleExceedsAvailable {
            log(
                location: "I18nDebugLog.swift:auditPageHeaderTitle",
                message: "title exceeds width without scaling — likely wraps to second line",
                hypothesisId: "H1-H3",
                data: [
                    "titleText": titleText,
                    "overflowPt": round((titleWidth - availableTitleWidth) * 10) / 10,
                    "wouldFitWithLineLimitAndScale": scaleFactorNeeded >= 0.55
                ],
                runId: runId
            )
        }
    }

    static func auditTabBarLabels(appLanguage: String?, runId: String = "pre-fix") {
        let tabKeys: [(name: String, compact: String, full: String)] = [
            ("dashboard", TabBarLabels.dashboard, "Dashboard"),
            ("cashFlow", TabBarLabels.cashFlow, "Cash Flow"),
            ("investments", TabBarLabels.investments, "Investments"),
            ("crypto", TabBarLabels.crypto, "Crypto"),
            ("settings", TabBarLabels.settings, "Settings")
        ]

        let screenWidth = UIScreen.main.bounds.width
        let estimatedSlotWidth = (screenWidth - 32) / 5
        let font = UIFont.systemFont(ofSize: 10, weight: .medium)
        var labels: [[String: Any]] = []

        for tab in tabKeys {
            let fullText = AppLocalization.string(String.LocalizationValue(tab.full), appLanguage: appLanguage)
            let compactText = AppLocalization.string(String.LocalizationValue(tab.compact), appLanguage: appLanguage)
            let fullWidth = (fullText as NSString).size(withAttributes: [.font: font]).width
            let compactWidth = (compactText as NSString).size(withAttributes: [.font: font]).width
            labels.append([
                "tab": tab.name,
                "fullText": fullText,
                "fullCharCount": fullText.count,
                "fullWidthPt": round(fullWidth * 10) / 10,
                "compactText": compactText,
                "compactCharCount": compactText.count,
                "compactWidthPt": round(compactWidth * 10) / 10,
                "fullExceedsSlot": fullWidth > estimatedSlotWidth,
                "compactExceedsSlot": compactWidth > estimatedSlotWidth
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
}
// #endregion

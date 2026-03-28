import Foundation

struct EstimatedValueRange: Equatable {
    let lowerBound: Double
    let upperBound: Double
    let currencyCode: String?

    var hasSingleValue: Bool {
        abs(upperBound - lowerBound) < 0.5
    }
}

enum EstimatedValueFormatter {
    static func displayText(from rawText: String?, locale: Locale = .autoupdatingCurrent) -> String? {
        guard let rawText = normalize(rawText), !rawText.isEmpty else {
            return nil
        }

        guard let range = parse(rawText) else {
            return rawText
        }

        return format(range, locale: locale) ?? rawText
    }

    static func parse(_ rawText: String?) -> EstimatedValueRange? {
        guard let normalized = normalize(rawText), !normalized.isEmpty else {
            return nil
        }

        let values = numericValues(in: normalized)
        guard let first = values.first else {
            return nil
        }

        let last = values.last ?? first
        return EstimatedValueRange(
            lowerBound: min(first, last),
            upperBound: max(first, last),
            currencyCode: detectedCurrencyCode(in: normalized)
        )
    }

    static func format(_ range: EstimatedValueRange, locale: Locale = .autoupdatingCurrent) -> String? {
        let lower = currencyText(for: range.lowerBound, currencyCode: range.currencyCode, locale: locale)
        guard let lower else { return nil }

        if range.hasSingleValue {
            return lower
        }

        guard let upper = currencyText(for: range.upperBound, currencyCode: range.currencyCode, locale: locale) else {
            return lower
        }

        return "\(lower) - \(upper)"
    }

    private static func normalize(_ text: String?) -> String? {
        text?
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func numericValues(in text: String) -> [Double] {
        let pattern = #"(\d{1,3}(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let captureRange = Range(match.range(at: 1), in: text) else {
                return nil
            }

            return Double(text[captureRange].replacingOccurrences(of: ",", with: ""))
        }
    }

    private static func detectedCurrencyCode(in text: String) -> String? {
        let knownCodes = ["USD", "EUR", "GBP", "NOK", "SEK", "DKK", "CHF", "JPY", "CAD", "AUD"]
        if let code = knownCodes.first(where: { text.range(of: "\\b\($0)\\b", options: [.regularExpression, .caseInsensitive]) != nil }) {
            return code
        }

        if text.contains("$") { return "USD" }
        if text.contains("\u{20AC}") { return "EUR" }
        if text.contains("\u{00A3}") { return "GBP" }
        if text.contains("\u{00A5}") { return "JPY" }

        return nil
    }

    private static func currencyText(for value: Double, currencyCode: String?, locale: Locale) -> String? {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        if let currencyCode {
            formatter.currencyCode = currencyCode
        }
        return formatter.string(from: NSNumber(value: value))
    }
}

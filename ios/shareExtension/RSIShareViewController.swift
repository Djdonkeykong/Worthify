//
//  RSIShareViewController.swift
//  Worthify Share Extension
//
//  Vendored from receive_sharing_intent (v1.8.1) with logging and
//  main-thread safety so we can debug shares without the full Flutter pod.
//

import UIKit
import Social
import MobileCoreServices
import Photos
import UniformTypeIdentifiers
import LinkPresentation
import AVFoundation
import WebKit
import TOCropViewController

let kSchemePrefix = "ShareMedia"
let kUserDefaultsKey = "ShareKey"
let kUserDefaultsMessageKey = "ShareMessageKey"
let kAppGroupIdKey = "AppGroupId"
let kProcessingStatusKey = "ShareProcessingStatus"
let kProcessingSessionKey = "ShareProcessingSession"
let kSerpApiKey = "SerpApiKey"
let kDetectorEndpoint = "DetectorEndpoint"
let kShareExtensionLogKey = "ShareExtensionLogEntries"
let kSupabaseUrlKey = "SupabaseUrl"
let kSupabaseAnonKeyKey = "SupabaseAnonKey"
let kSupabaseAccessTokenKey = "supabase_access_token"

@inline(__always)
private func shareLog(_ message: String) {
    NSLog("[ShareExtension] %@", message)
    ShareLogger.shared.append(message)
}

final class ShareLogger {
    static let shared = ShareLogger()

    private let queue = DispatchQueue(label: "com.worthify.shareExtension.logger")
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private var defaults: UserDefaults?
    private let maxEntries = 200

    func configure(appGroupId: String) {
        queue.sync {
            self.defaults = UserDefaults(suiteName: appGroupId)
            NSLog("[ShareLogger] Configured with app group: \(appGroupId)")
            NSLog("[ShareLogger] UserDefaults initialized: \(self.defaults != nil)")
        }
    }

    func append(_ message: String) {
        queue.async {
            guard let defaults = self.defaults else {
                NSLog("[ShareLogger] ERROR: defaults is nil, cannot append log")
                return
            }
            let timestamp = self.isoFormatter.string(from: Date())
            var entries = defaults.stringArray(forKey: kShareExtensionLogKey) ?? []
            entries.append("[\(timestamp)] \(message)")
            if entries.count > self.maxEntries {
                entries.removeFirst(entries.count - self.maxEntries)
            }
            defaults.set(entries, forKey: kShareExtensionLogKey)
            defaults.synchronize()
            let count = defaults.stringArray(forKey: kShareExtensionLogKey)?.count ?? 0
            NSLog("[ShareLogger] Appended log, total count: \(count)")
        }
    }

    func clear() {
        queue.async { [weak self] in
            guard let defaults = self?.defaults else { return }
            defaults.removeObject(forKey: kShareExtensionLogKey)
        }
    }
}

public class SharedMediaFile: Codable {
    var path: String
    var mimeType: String?
    var thumbnail: String?
    var duration: Double?
    var message: String?
    var type: SharedMediaType

    public init(
        path: String,
        mimeType: String? = nil,
        thumbnail: String? = nil,
        duration: Double? = nil,
        message: String? = nil,
        type: SharedMediaType
    ) {
        self.path = path
        self.mimeType = mimeType
        self.thumbnail = thumbnail
        self.duration = duration
        self.message = message
        self.type = type
    }
}

public enum SharedMediaType: String, Codable, CaseIterable {
    case image
    case video
    case text
    case file
    case url

    public var toUTTypeIdentifier: String {
        if #available(iOS 14.0, *) {
            switch self {
            case .image: return UTType.image.identifier
            case .video: return UTType.movie.identifier
            case .text:  return UTType.text.identifier
            case .file:  return UTType.fileURL.identifier
            case .url:   return UTType.url.identifier
            }
        }
        switch self {
        case .image: return "public.image"
        case .video: return "public.movie"
        case .text:  return "public.text"
        case .file:  return "public.data"
        case .url:   return "public.url"
        }
    }
}

// Detection result model
struct DetectionResultItem: Codable {
    let id: String
    let product_name: String
    let brand: String?
    private let priceNumeric: Double?
    private let priceText: String?
    let image_url: String
    let category: String
    let confidence: Double?
    let description: String?
    let purchase_url: String?

    enum CodingKeys: String, CodingKey {
        case id
        case product_name
        case brand
        case price
        case image_url
        case category
        case confidence
        case description
        case purchase_url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        let rawName = (try? container.decode(String.self, forKey: .product_name)) ?? ""
        product_name = rawName.isEmpty ? "Untitled" : rawName

        let rawBrand = try? container.decodeIfPresent(String.self, forKey: .brand)
        if let trimmedBrand = rawBrand?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedBrand.isEmpty {
            brand = trimmedBrand
        } else {
            brand = nil
        }

        var numeric: Double? = nil
        var textValue: String? = nil
        if let doubleValue = try? container.decode(Double.self, forKey: .price) {
            numeric = doubleValue
        } else if let intValue = try? container.decode(Int.self, forKey: .price) {
            numeric = Double(intValue)
        } else if let stringValue = try? container.decode(String.self, forKey: .price) {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                textValue = trimmed
            }
            let digits = trimmed.replacingOccurrences(of: "[^0-9.,]", with: "", options: .regularExpression)
                .replacingOccurrences(of: ",", with: "")
            if let parsed = Double(digits), parsed.isFinite {
                numeric = parsed
            }
        }
        priceNumeric = numeric
        priceText = textValue

        image_url = (try? container.decode(String.self, forKey: .image_url)) ?? ""
        let rawCategory = (try? container.decode(String.self, forKey: .category)) ?? ""
        category = rawCategory.isEmpty ? "Uncategorized" : rawCategory
        confidence = try? container.decodeIfPresent(Double.self, forKey: .confidence)
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        purchase_url = try? container.decodeIfPresent(String.self, forKey: .purchase_url)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(product_name, forKey: .product_name)
        if let brand = brand {
            try container.encode(brand, forKey: .brand)
        } else {
            try container.encodeNil(forKey: .brand)
        }
        if let text = priceText, !text.isEmpty {
            try container.encode(text, forKey: .price)
        } else if let numeric = priceNumeric {
            try container.encode(numeric, forKey: .price)
        } else {
            try container.encodeNil(forKey: .price)
        }
        try container.encode(image_url, forKey: .image_url)
        try container.encode(category, forKey: .category)
        if let confidence = confidence {
            try container.encode(confidence, forKey: .confidence)
        } else {
            try container.encodeNil(forKey: .confidence)
        }
        if let description = description {
            try container.encode(description, forKey: .description)
        } else {
            try container.encodeNil(forKey: .description)
        }
        if let purchase_url = purchase_url {
            try container.encode(purchase_url, forKey: .purchase_url)
        } else {
            try container.encodeNil(forKey: .purchase_url)
        }
    }

    var priceValue: Double? { priceNumeric }

    var priceDisplay: String? {
        // Only return priceText if available, no formatting
        if let text = priceText, !text.isEmpty {
            return text
        }
        return nil
    }

    var normalizedCategoryAssignment: NormalizedCategoryAssignment {
        CategoryNormalizer.shared.assignment(for: self)
    }

    var normalizedCategories: [NormalizedCategory] {
        normalizedCategoryAssignment.categories
    }

    var normalizedCategoryConfidence: Int {
        normalizedCategoryAssignment.confidence
    }

    var categoryGroup: CategoryGroup {
        CategoryGroup.from(
            normalized: normalizedCategories,
            productName: product_name
        )
    }
}

enum NormalizedCategory: String, CaseIterable, Hashable {
    case tops, bottoms, dresses, outerwear, shoes, bags, accessories, headwear, other

    var displayName: String {
        switch self {
        case .tops: return "Tops"
        case .bottoms: return "Bottoms"
        case .dresses: return "Dresses"
        case .outerwear: return "Outerwear"
        case .shoes: return "Shoes"
        case .bags: return "Bags"
        case .accessories: return "Accessories"
        case .headwear: return "Headwear"
        case .other: return "Other"
        }
    }

    static let preferredOrder: [NormalizedCategory] = [
        .tops, .bottoms, .dresses, .outerwear, .shoes, .bags, .accessories, .headwear, .other
    ]

    init?(displayName: String) {
        let lowered = displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lowered {
        case "tops": self = .tops
        case "bottoms": self = .bottoms
        case "dresses": self = .dresses
        case "outerwear": self = .outerwear
        case "shoes": self = .shoes
        case "bags": self = .bags
        case "accessories": self = .accessories
        case "headwear": self = .headwear
        case "other": self = .other
        default: return nil
        }
    }
}

private struct CategoryRuleSet {
    let positives: [String]
    let negatives: [String]
}

struct NormalizedCategoryAssignment {
    let categories: [NormalizedCategory]
    let confidence: Int
}

enum CategoryGroup: Hashable {
    case all
    case clothing
    case footwear
    case accessories

    var displayName: String {
        switch self {
        case .all: return "All"
        case .clothing: return "Clothing"
        case .footwear: return "Footwear"
        case .accessories: return "Accessories"
        }
    }

    init?(title: String) {
        switch title.lowercased() {
        case "all": self = .all
        case "clothing": self = .clothing
        case "footwear": self = .footwear
        case "accessories": self = .accessories
        default: return nil
        }
    }

    static let orderedGroups: [CategoryGroup] = [.clothing, .footwear, .accessories]

    static func from(normalized: [NormalizedCategory], productName: String) -> CategoryGroup {
        let normalizedSet = Set(normalized)

        if normalizedSet.contains(.shoes) {
            return .footwear
        }

        if !normalizedSet.intersection(clothingCategories).isEmpty {
            return .clothing
        }

        if !normalizedSet.intersection(accessoryCategories).isEmpty {
            return .accessories
        }

        let lowerTitle = productName.lowercased()
        if footwearKeywords.contains(where: lowerTitle.contains) {
            return .footwear
        }

        if clothingKeywords.contains(where: lowerTitle.contains) {
            return .clothing
        }

        return .accessories
    }

    private static let clothingCategories: Set<NormalizedCategory> = [
        .tops, .bottoms, .dresses, .outerwear
    ]

    private static let accessoryCategories: Set<NormalizedCategory> = [
        .bags, .accessories, .headwear, .other
    ]

    private static let footwearKeywords: [String] = [
        "shoe", "boot", "heel", "sandal", "pump", "loafer", "sneaker",
        "trainer", "stiletto", "mule", "platform", "slipper"
    ]

    private static let clothingKeywords: [String] = [
        "dress", "gown", "skirt", "top", "shirt", "blouse", "jacket",
        "coat", "hoodie", "sweater", "pant", "trouser", "jean", "short"
    ]
}

final class CategoryNormalizer {
    static let shared = CategoryNormalizer()

    private let baseMappings: [String: NormalizedCategory] = [
        "tops": .tops,
        "top": .tops,
        "shirts": .tops,
        "shirt": .tops,
        "blouse": .tops,
        "tees": .tops,
        "t-shirts": .tops,
        "bottoms": .bottoms,
        "pants": .bottoms,
        "trousers": .bottoms,
        "jeans": .bottoms,
        "shorts": .bottoms,
        "skirts": .bottoms,
        "dresses": .dresses,
        "dress": .dresses,
        "outerwear": .outerwear,
        "jackets": .outerwear,
        "coats": .outerwear,
        "shoes": .shoes,
        "footwear": .shoes,
        "bags": .bags,
        "bag": .bags,
        "accessories": .accessories,
        "headwear": .headwear,
        "hats": .headwear
    ]

    private let ruleSets: [NormalizedCategory: CategoryRuleSet] = [
        .tops: CategoryRuleSet(
            positives: ["top", "tee", "t-shirt", "shirt", "blouse", "sweater", "hoodie", "cardigan", "pullover", "tank", "camisole"],
            negatives: ["dress", "skirt", "pant", "shoe", "bag", "shorts", "trouser"]
        ),
        .bottoms: CategoryRuleSet(
            positives: ["pant", "jean", "trouser", "short", "skirt", "legging", "culotte", "jogger", "denim", "bottom"],
            negatives: ["dress", "bag", "shoe", "top", "shirt", "hoodie"]
        ),
        .dresses: CategoryRuleSet(
            positives: ["dress", "gown", "maxi", "mini dress", "midi dress", "strapless", "wrap dress", "bodycon"],
            negatives: ["shoe", "bag", "pant", "short", "skirt"]
        ),
        .outerwear: CategoryRuleSet(
            positives: ["coat", "jacket", "blazer", "trench", "parka", "puffer", "outerwear", "windbreaker", "shacket"],
            negatives: ["dress", "skirt", "shoe", "bag"]
        ),
        .shoes: CategoryRuleSet(
            positives: ["shoe", "boot", "sneaker", "heel", "sandal", "pump", "loafer", "mule", "trainer", "cleat"],
            negatives: ["bag", "dress", "skirt", "top"]
        ),
        .bags: CategoryRuleSet(
            positives: ["bag", "handbag", "tote", "crossbody", "satchel", "backpack", "clutch", "shoulder bag", "purse", "duffle"],
            negatives: ["shoe", "dress", "pant"]
        ),
        .accessories: CategoryRuleSet(
            positives: ["belt", "scarf", "sunglass", "bracelet", "necklace", "earring", "ring", "watch", "wallet", "glove", "accessory", "jewelry"],
            negatives: ["shoe", "dress", "pant", "hat", "cap", "beanie"]
        ),
        .headwear: CategoryRuleSet(
            positives: ["hat", "cap", "beanie", "headband", "visor", "beret"],
            negatives: ["bag", "shoe", "dress", "pant"]
        ),
        .other: CategoryRuleSet(
            positives: [],
            negatives: []
        )
    ]

    private let minimumScore = 3

    func assignment(for item: DetectionResultItem) -> NormalizedCategoryAssignment {
        let normalizedCategoryKey = item.category.lowercased()
        var scores: [NormalizedCategory: Int] = [:]

        if let mapped = baseMappings[normalizedCategoryKey] {
            scores[mapped, default: 0] += 3
        }

        let sourceText = [
            item.product_name,
            item.brand ?? "",
            item.description ?? "",
            item.category
        ]
            .joined(separator: " ")
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let tokens: Set<String> = Set(
            sourceText
                .split(separator: " ")
                .map { String($0) }
                .filter { !$0.isEmpty }
        )

        func containsKeyword(_ keyword: String) -> Bool {
            let key = keyword.lowercased()
            if key.contains(" ") {
                return sourceText.contains(key)
            }
            return tokens.contains(key)
        }

        for (category, ruleSet) in ruleSets {
            var score = scores[category, default: 0]
            for keyword in ruleSet.positives where containsKeyword(keyword) {
                score += 2
            }
            for keyword in ruleSet.negatives where containsKeyword(keyword) {
                score -= 3
            }
            scores[category] = score
        }

        // Determine best scores
        let sorted = scores.sorted { $0.value > $1.value }
        let bestScore = sorted.first?.value ?? 0

        var chosen = sorted
            .filter { $0.value >= max(minimumScore, bestScore - 1) && $0.value > 0 }
            .map { $0.key }

        if chosen.isEmpty, let mapped = baseMappings[normalizedCategoryKey] {
            chosen = [mapped]
        }

        if chosen.isEmpty {
            chosen = [.other]
        } else if chosen.count > 2 {
            chosen = Array(chosen.prefix(2))
        }

        if chosen.contains(.other) && chosen.count > 1 {
            chosen.removeAll { $0 == .other }
        }

        return NormalizedCategoryAssignment(
            categories: chosen,
            confidence: max(bestScore, 0)
        )
    }
}

struct DetectionResponse: Decodable {
    let success: Bool
    let detected_garment: DetectedGarment?
    let total_results: Int
    let results: [DetectionResultItem]
    let message: String?
    let search_id: String?
    let image_cache_id: String?
    let cached: Bool?
    let garments_searched: Int?

    enum CodingKeys: String, CodingKey {
        case success
        case detected_garment
        case detected_garments
        case total_results
        case results
        case search_results
        case message
        case search_id
        case image_cache_id
        case cached
        case garments_searched
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = (try? container.decode(Bool.self, forKey: .success)) ?? false

        // Handle both old (detected_garment) and new (detected_garments) formats
        if let garments = try? container.decodeIfPresent([DetectedGarment].self, forKey: .detected_garments),
           let firstGarment = garments.first {
            detected_garment = firstGarment
        } else {
            detected_garment = try? container.decodeIfPresent(DetectedGarment.self, forKey: .detected_garment)
        }

        if let total = try? container.decode(Int.self, forKey: .total_results) {
            total_results = total
        } else if let decodedResults = try? container.decode([DetectionResultItem].self, forKey: .results) {
            total_results = decodedResults.count
        } else if let decodedResults = try? container.decode([DetectionResultItem].self, forKey: .search_results) {
            total_results = decodedResults.count
        } else {
            total_results = 0
        }

        // Handle both old (results) and new (search_results) formats
        if let searchResults = try? container.decode([DetectionResultItem].self, forKey: .search_results) {
            results = searchResults
        } else {
            results = (try? container.decode([DetectionResultItem].self, forKey: .results)) ?? []
        }

        message = try? container.decodeIfPresent(String.self, forKey: .message)
        search_id = try? container.decodeIfPresent(String.self, forKey: .search_id)
        image_cache_id = try? container.decodeIfPresent(String.self, forKey: .image_cache_id)
        cached = try? container.decodeIfPresent(Bool.self, forKey: .cached)
        garments_searched = try? container.decodeIfPresent(Int.self, forKey: .garments_searched)
    }

    struct DetectedGarment: Decodable {
        let label: String
        let score: Double
        let bbox: [Int]
    }
}

@available(swift, introduced: 5.0)
open class RSIShareViewController: SLComposeServiceViewController {
    private enum DeferredShareAction {
        case analyzeNow
        case analyzeInApp
    }

    var hostAppBundleIdentifier = ""
    var appGroupId = ""
    var sharedMedia: [SharedMediaFile] = []
    private var loadingView: UIView?
    private var loadingShownAt: Date?
    private var isPhotosSourceApp = false
    private let photoImportStatusMessage = "Importing your photo..."
    private var loadingHideWorkItem: DispatchWorkItem?
    private var currentProcessingSession: String?
    private var didCompleteRequest = false
    private var activityIndicator: UIActivityIndicatorView?
    private var statusLabel: UILabel?
    private var statusPollTimer: Timer?
    private var pendingAttachmentCount = 0
    private var hasQueuedRedirect = false
    private var pendingPostMessage: String?
    private let maxInstagramScrapeAttempts = 2
    private var detectionResults: [DetectionResultItem] = []
    private var favoritedProductIds: Set<String> = []
    private var favoriteIdByProductId: [String: String] = [:]
    private var filteredResults: [DetectionResultItem] = []
    private var resultsTableView: UITableView?
    private var downloadedImageUrl: String?
    private var isShowingDetectionResults = false
    private var shouldAttemptDetection = false
    private var pendingSharedFile: SharedMediaFile?
    private var pendingImageData: Data?
    private var pendingImageUrl: String?
    private var pendingInstagramUrl: String?
    private var pendingInstagramCompletion: (() -> Void)?
    private var pendingPlatformType: String?
    private var sourceApplicationBundleId: String?
    private var inferredPlatformType: String?
    private var currentSearchId: String?
    private var currentImageCacheId: String?
    private var analyzedImageData: Data? // Store the analyzed image for sharing
    private var originalImageData: Data? // Preserve the original image so users can revert after cropping
    private var previewImageView: UIImageView? // Reference to preview image for updating after crop
    private var revertCropButton: UIButton? // Reset button shown on preview after a crop
    private var selectedGroup: CategoryGroup?
    private var categoryFilterView: UIView?
    private var hasProcessedAttachments = false
    private var deferredShareAction: DeferredShareAction?
    private var progressView: UIProgressView?
    private var progressTimer: Timer?
    private var currentProgress: Float = 0.0
    private var targetProgress: Float = 0.0
    private var progressRateMultiplier: Float = 1.0
    private var previewTargetCap: Float = 0.92
    private var detectTargetCap: Float = 0.96
    private var statusRotationTimer: Timer?
    private var currentStatusMessages: [String] = []
    private var currentStatusIndex: Int = 0
    private var backgroundActivity: NSObjectProtocol?
    private var detectionTask: URLSessionDataTask? // Store detection API task for cancellation
    private var hasPresentedDetectionFailureAlert = false
    private var hasPresentedUnsupportedAlert = false
    private var headerContainerView: UIView?
    private var headerLogoImageView: UIImageView?
    private var cancelButtonView: UIButton?
    private var backButtonView: UIButton?
    private var resultsHeaderContainerView: UIView?
    private var imageComparisonContainerView: UIView?
    private var imageComparisonThumbnailImageView: UIImageView?
    private var imageComparisonFullImageView: UIImageView?
    private var imageComparisonWidthConstraint: NSLayoutConstraint?
    private var isUpdatingResultsHeaderLayout = false
    private var isImageComparisonExpanded = false
    private var isShowingResults = false
    private var isShowingPreview = false
    private var shouldShowOutOfCreditsAfterAnalysis = false
    private var hasShownPostAnalysisOutOfCreditsModal = false
    private let bannedKeywordPatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: "\\bwig\\b", options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: "\\bwigs\\b", options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: "\\bwiglets?\\b", options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: "\\bwig[-\\s]?caps?\\b", options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: "\\blace[-\\s]?front\\b", options: [.caseInsensitive])
    ]

    private static let bannedContentDomainRoots: Set<String> = [
        "facebook.com","instagram.com","twitter.com","x.com","pinterest.com",
        "tiktok.com","linkedin.com","reddit.com","youtube.com","snapchat.com",
        "threads.net","discord.com","wechat.com","weibo.com","line.me","vk.com",
        "blogspot.com","wordpress.com","tumblr.com","medium.com","substack.com",
        "weebly.com","wixsite.com","squarespace.com","ghost.io","notion.site",
        "livejournal.com","typepad.com","quora.com","fandom.com","wikipedia.org",
        "wikihow.com","britannica.com","ask.com","answers.com","bbc.com","cnn.com",
        "nytimes.com","washingtonpost.com","forbes.com","bloomberg.com",
        "reuters.com","huffpost.com","usatoday.com","abcnews.go.com","cbsnews.com",
        "npr.org","time.com","theguardian.com","independent.co.uk","theatlantic.com",
        "vox.com","buzzfeed.com","vice.com","msn.com","dailymail.co.uk","mirror.co.uk",
        "nbcnews.com","latimes.com","insider.com","soundcloud.com","deviantart.com",
        "dribbble.com","artstation.com","behance.net","vimeo.com","bandcamp.com",
        "mixcloud.com","last.fm","spotify.com","goodreads.com","vogue.com","elle.com",
        "harpersbazaar.com","cosmopolitan.com","glamour.com","refinery29.com",
        "whowhatwear.com","instyle.com","graziamagazine.com","vanityfair.com",
        "marieclaire.com","teenvogue.com","stylecaster.com","popsugar.com","nylon.com",
        "lifestyleasia.com","thezoereport.com","allure.com","coveteur.com","thecut.com",
        "dazeddigital.com","highsnobiety.com","hypebeast.com","complex.com","gq.com",
        "esquire.com","menshealth.com","wmagazine.com","people.com","today.com",
        "observer.com","standard.co.uk","eveningstandard.co.uk","nssmag.com",
        "grazia.fr","grazia.it","techcrunch.com","wired.com","theverge.com",
        "engadget.com","gsmarena.com","cnet.com","zdnet.com","mashable.com",
        "makeuseof.com","arstechnica.com","androidauthority.com","macrumors.com",
        "9to5mac.com","digitaltrends.com","imore.com","tomsguide.com",
        "pocket-lint.com","tripadvisor.com","expedia.com","lonelyplanet.com",
        "booking.com","airbnb.com","travelandleisure.com","kayak.com","skyscanner.com"
    ]

    private static func isBannedPurchaseUrl(_ url: String) -> Bool {
        guard let host = URL(string: url)?.host?.lowercased() else { return false }
        for root in bannedContentDomainRoots {
            if host == root || host.hasSuffix(".\(root)") {
                return true
            }
        }
        return false
    }

    open func shouldAutoRedirect() -> Bool { true }

    open override func isContentValid() -> Bool { true }

    private static let browserBundlePlatformMap: [String: String] = [
        "com.apple.mobilesafari": "safari",
        "com.apple.safariviewservice": "safari",
        "com.google.chrome.ios": "chrome",
        "com.google.chrome": "chrome",
        "org.mozilla.ios.firefox": "firefox",
        "org.mozilla.firefox": "firefox",
        "com.brave.ios.browser": "brave",
    ]

    private func detectPlatformType(from bundleId: String) -> String? {
        let normalized = bundleId.lowercased()
        if let mapped = RSIShareViewController.browserBundlePlatformMap[normalized] {
            return mapped
        }
        if normalized.contains("safari") {
            return "safari"
        }
        if normalized.contains("chrome") {
            return "chrome"
        }
        if normalized.contains("firefox") {
            return "firefox"
        }
        if normalized.contains("brave") {
            return "brave"
        }
        return nil
    }

    /// Get device locale for localized search results
    /// Returns (countryCode, languageCode) tuple, e.g. ("US", "en") or ("NO", "nb")
    private func getDeviceLocale() -> (country: String, language: String) {
        let locale = Locale.current

        // Get country code (e.g., "US", "NO", "GB")
        let countryCode = locale.regionCode?.uppercased() ?? "US"

        // Get language code (e.g., "en", "nb", "fr")
        let languageCode = locale.languageCode?.lowercased() ?? "en"

        shareLog("Device locale detected: \(countryCode) (\(languageCode))")

        return (country: countryCode, language: languageCode)
    }

    private func hideDefaultUI() {
        // Hide and disable the default text view
        textView?.isHidden = true
        textView?.isEditable = false
        textView?.isSelectable = false
        textView?.alpha = 0
        textView?.text = ""
        placeholder = ""

        // Ensure content view is not visible
        if let contentView = textView?.superview {
            contentView.isHidden = true
            contentView.alpha = 0
        }

        // Hide any other default subviews
        view.subviews.forEach { subview in
            if subview !== loadingView && subview.tag != 9999 {
                subview.isHidden = true
                subview.alpha = 0
            }
        }
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        // Force light mode for the share extension UI (prevents dark appearance from host apps like YouTube)
        if #available(iOS 13.0, *) {
            overrideUserInterfaceStyle = .light
        }

        // Immediately hide and disable all default SLComposeServiceViewController UI
        hideDefaultUI()
        navigationController?.setNavigationBarHidden(true, animated: false)
        navigationItem.leftBarButtonItem = nil
        navigationItem.rightBarButtonItem = nil

        loadIds()
        ShareLogger.shared.configure(appGroupId: appGroupId)
        sharedMedia.removeAll()
        shareLog("View did load - cleared sharedMedia array")
        if let sourceBundle = readSourceApplicationBundleIdentifier() {
            shareLog("Source application bundle: \(sourceBundle)")
            sourceApplicationBundleId = sourceBundle
            let photosBundles: Set<String> = [
                "com.apple.mobileslideshow",
                "com.apple.Photos"
            ]
            if photosBundles.contains(sourceBundle) {
                isPhotosSourceApp = true
                shareLog("Detected Photos source app - enforcing minimum 2s redirect delay")
            }
            if let platform = detectPlatformType(from: sourceBundle) {
                inferredPlatformType = platform
                if pendingPlatformType == nil {
                    pendingPlatformType = platform
                }
                shareLog("Detected browser platform type: \(platform)")
            }
        } else {
            shareLog("Source application bundle: nil")
        }
        suppressKeyboard()
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
            shareLog("Resolved container URL: \(containerURL.path)")
        } else {
            shareLog("ERROR: Failed to resolve container URL for \(appGroupId)")
        }
        loadingHideWorkItem?.cancel()

        // Create a completely blank overlay to hide default UI immediately
        let blankOverlay = UIView(frame: view.bounds)
        blankOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blankOverlay.backgroundColor = UIColor.systemBackground
        blankOverlay.tag = 9999
        view.addSubview(blankOverlay)

        // Hide default share extension UI immediately
        hideDefaultUI()

        // Check authentication and credits, then build complete UI immediately to prevent white flash
        if !isUserAuthenticated() {
            shareLog("User not authenticated - building login modal in viewDidLoad")
            showLoginRequiredModal()
        } else {
            resolveCreditAccess { [weak self] hasCredits in
                guard let self = self else { return }
                if hasCredits {
                    shareLog("User authenticated with credits - building choice buttons in viewDidLoad")
                    self.addLogoAndCancel()
                    self.showChoiceButtons()
                } else {
                    shareLog("User authenticated but no credits - building out of credits modal in viewDidLoad")
                    self.showOutOfCreditsModal()
                }
            }
        }
    }

    private func addLogoAndCancel() {
        // Add logo and cancel button to existing blank overlay
        guard let overlay = view.subviews.first(where: { $0.tag == 9999 }) else {
            shareLog("[ERROR] Cannot find blank overlay to add logo/cancel")
            return
        }

        // Add logo and cancel button at top
        let headerContainer = UIView()
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.tag = 9996 // Tag to identify header

        let logo = UIImageView(image: UIImage(named: "logo"))
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        cancelButton.addTarget(self, action: #selector(cancelImportTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        headerContainer.addSubview(logo)
        headerContainer.addSubview(cancelButton)

        // Add header to overlay
        overlay.addSubview(headerContainer)

        // Set up constraints
        NSLayoutConstraint.activate([
            // Header container
            headerContainer.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: -5),
            headerContainer.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -16),
            headerContainer.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 14),
            headerContainer.heightAnchor.constraint(equalToConstant: 48),

            // Logo - centered with offset
            logo.centerXAnchor.constraint(equalTo: headerContainer.centerXAnchor, constant: 12),
            logo.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            logo.heightAnchor.constraint(equalToConstant: 28),
            logo.widthAnchor.constraint(equalToConstant: 132),

            // Cancel button
            cancelButton.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            cancelButton.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor)
        ])
    }

    private func showChoiceButtons() {
        // Block auto-redirect while choice UI is visible
        shouldAttemptDetection = true
        shareLog("Choice buttons shown - blocking auto-redirect")

        // Add choice buttons to the existing blank overlay
        guard let overlay = view.subviews.first(where: { $0.tag == 9999 }) else {
            shareLog("Cannot find overlay to add choice buttons")
            return
        }

        // Create vertical stack for buttons
        let buttonStack = UIStackView()
        buttonStack.axis = .vertical
        buttonStack.alignment = .fill
        buttonStack.spacing = 16
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.tag = 9998 // Tag to identify button stack

        // "Analyze in app" button
        let analyzeInAppButton = UIButton(type: .system)
        analyzeInAppButton.setTitle("Analyze in app", for: .normal)
        analyzeInAppButton.titleLabel?.font = UIFont(name: "PlusJakartaSans-Bold", size: 16)
            ?? .systemFont(ofSize: 16, weight: .bold)
        analyzeInAppButton.backgroundColor = UIColor(red: 242/255, green: 0, blue: 60/255, alpha: 1.0)
        analyzeInAppButton.setTitleColor(.white, for: .normal)
        analyzeInAppButton.layer.cornerRadius = 28
        analyzeInAppButton.translatesAutoresizingMaskIntoConstraints = false
        analyzeInAppButton.addTarget(self, action: #selector(analyzeInAppTapped), for: .touchUpInside)

        // "Analyze now" button
        let analyzeNowButton = UIButton(type: .system)
        analyzeNowButton.setTitle("Analyze now", for: .normal)
        analyzeNowButton.titleLabel?.font = UIFont(name: "PlusJakartaSans-Bold", size: 16)
            ?? .systemFont(ofSize: 16, weight: .bold)
        analyzeNowButton.backgroundColor = .clear
        analyzeNowButton.setTitleColor(.black, for: .normal)
        analyzeNowButton.layer.cornerRadius = 28
        analyzeNowButton.layer.borderWidth = 1.5
        analyzeNowButton.layer.borderColor = UIColor(red: 209/255, green: 213/255, blue: 219/255, alpha: 1.0).cgColor
        analyzeNowButton.translatesAutoresizingMaskIntoConstraints = false
        analyzeNowButton.addTarget(self, action: #selector(analyzeNowTapped), for: .touchUpInside)

        buttonStack.addArrangedSubview(analyzeInAppButton)
        buttonStack.addArrangedSubview(analyzeNowButton)

        // Time disclaimer with container
        let timeDisclaimerContainer = UIView()
        timeDisclaimerContainer.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.6)
        timeDisclaimerContainer.layer.cornerRadius = 12
        timeDisclaimerContainer.translatesAutoresizingMaskIntoConstraints = false

        let timeDisclaimerLabel = UILabel()
        timeDisclaimerLabel.text = "Analyses take 5-15 seconds on average. During peak hours, you may experience longer wait times."
        timeDisclaimerLabel.font = .systemFont(ofSize: 12, weight: .medium)
        timeDisclaimerLabel.textColor = UIColor.label
        timeDisclaimerLabel.textAlignment = .center
        timeDisclaimerLabel.numberOfLines = 0
        timeDisclaimerLabel.translatesAutoresizingMaskIntoConstraints = false

        timeDisclaimerContainer.addSubview(timeDisclaimerLabel)
        timeDisclaimerContainer.tag = 9996 // Tag for time disclaimer

        // Credits disclaimer label
        let creditsDisclaimerLabel = UILabel()
        creditsDisclaimerLabel.text = "Tip: Cropping can help you save credits because each garment scanned uses one."
        creditsDisclaimerLabel.font = .systemFont(ofSize: 12, weight: .regular)
        creditsDisclaimerLabel.textColor = UIColor.secondaryLabel
        creditsDisclaimerLabel.textAlignment = .center
        creditsDisclaimerLabel.numberOfLines = 0
        creditsDisclaimerLabel.translatesAutoresizingMaskIntoConstraints = false
        creditsDisclaimerLabel.tag = 9997 // Tag for credits disclaimer

        // Add button stack and disclaimers to overlay
        overlay.addSubview(buttonStack)
        overlay.addSubview(timeDisclaimerContainer)
        overlay.addSubview(creditsDisclaimerLabel)

        // Set up constraints
        NSLayoutConstraint.activate([
            // Button stack (centered)
            buttonStack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            buttonStack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            buttonStack.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 32),
            buttonStack.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -32),

            // Button heights
            analyzeInAppButton.heightAnchor.constraint(equalToConstant: 56),
            analyzeNowButton.heightAnchor.constraint(equalToConstant: 56),

            // Credits disclaimer at bottom
            creditsDisclaimerLabel.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 32),
            creditsDisclaimerLabel.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -32),
            creditsDisclaimerLabel.bottomAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.bottomAnchor, constant: -32),

            // Time disclaimer container above credits disclaimer
            timeDisclaimerContainer.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 32),
            timeDisclaimerContainer.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -32),
            timeDisclaimerContainer.bottomAnchor.constraint(equalTo: creditsDisclaimerLabel.topAnchor, constant: -12),

            // Time disclaimer label inside container
            timeDisclaimerLabel.topAnchor.constraint(equalTo: timeDisclaimerContainer.topAnchor, constant: 12),
            timeDisclaimerLabel.bottomAnchor.constraint(equalTo: timeDisclaimerContainer.bottomAnchor, constant: -12),
            timeDisclaimerLabel.leadingAnchor.constraint(equalTo: timeDisclaimerContainer.leadingAnchor, constant: 16),
            timeDisclaimerLabel.trailingAnchor.constraint(equalTo: timeDisclaimerContainer.trailingAnchor, constant: -16)
        ])

        loadingView = overlay
        hideDefaultUI()
        shareLog("[SUCCESS] Choice buttons displayed after auth check")
    }

    private func readSourceApplicationBundleIdentifier() -> String? {
        guard let context = extensionContext else { return nil }
        let selector = NSSelectorFromString("sourceApplicationBundleIdentifier")
        guard (context as AnyObject).responds(to: selector) else {
            shareLog("Source application bundle not available on this OS version")
            return nil
        }

        guard
            let unmanaged = (context as AnyObject).perform(selector),
            let bundleId = unmanaged.takeUnretainedValue() as? String
        else {
            shareLog("Source application bundle lookup returned nil")
            return nil
        }

        return bundleId
    }

    open override func didSelectPost() {
        shareLog("didSelectPost invoked")
        pendingPostMessage = contentText
        maybeFinalizeShare()
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
        hideDefaultUI()
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        suppressKeyboard()
        hideDefaultUI()
        applySheetCornerRadius(38)
        DispatchQueue.main.async { [weak self] in
            self?.applySheetCornerRadius(38)
        }

        // UI is already built in viewDidLoad - just check if we should process attachments
        if !isUserAuthenticated() {
            shareLog("User not authenticated - login modal already displayed")
            return
        }

        // Prevent re-processing attachments if already done (e.g., sheet bounce-back)
        if hasProcessedAttachments {
            shareLog("[SKIP] viewDidAppear called again - attachments already processed, skipping")
            return
        }

        guard let content = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = content.attachments else {
            shareLog("No attachments found on extension context")
            return
        }

        // Mark as processed to prevent re-runs
        hasProcessedAttachments = true

        pendingAttachmentCount = 0
        hasQueuedRedirect = false
        pendingPostMessage = nil

        if attachments.isEmpty {
            shareLog("No attachments to process")
            maybeFinalizeShare()
            return
        }

        for (index, attachment) in attachments.enumerated() {
            guard let type = SharedMediaType.allCases.first(where: {
                attachment.hasItemConformingToTypeIdentifier($0.toUTTypeIdentifier)
            }) else {
                shareLog("Attachment index \(index) has no supported type")
                continue
            }

            beginAttachmentProcessing()
            shareLog("Loading attachment index \(index) as \(type)")
            attachment.loadItem(
                forTypeIdentifier: type.toUTTypeIdentifier,
                options: nil
            ) { [weak self] data, error in
                guard let self = self else { return }
                if let error = error {
                    shareLog("ERROR: loadItem failed for index \(index) - \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.handleLoadFailure()
                    }
                    return
                }

                DispatchQueue.main.async {
                    self.processLoadedAttachment(
                        data: data,
                        type: type,
                        index: index,
                        content: content
                    )
                }
            }
        }

        maybeFinalizeShare()
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        shareLog("viewWillDisappear (didCompleteRequest=\(didCompleteRequest), hasQueuedRedirect=\(hasQueuedRedirect), pending=\(pendingAttachmentCount), showingPreview=\(isShowingPreview), showingResults=\(isShowingResults))")
        hideDefaultUI()
    }

    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        shareLog("viewDidDisappear (didCompleteRequest=\(didCompleteRequest), hasQueuedRedirect=\(hasQueuedRedirect), pending=\(pendingAttachmentCount), showingPreview=\(isShowingPreview), showingResults=\(isShowingResults))")
    }

    open override func configurationItems() -> [Any]! { [] }

    private func beginAttachmentProcessing() {
        pendingAttachmentCount += 1
    }

    private func completeAttachmentProcessing() {
        pendingAttachmentCount = max(pendingAttachmentCount - 1, 0)
        maybeFinalizeShare()
        maybeRunDeferredShareAction()
    }

    private func hasSharePayloadReady() -> Bool {
        return pendingInstagramUrl != nil || pendingImageData != nil || !sharedMedia.isEmpty
    }

    private func deferActionIfAttachmentsStillLoading(_ action: DeferredShareAction) -> Bool {
        guard pendingAttachmentCount > 0, !hasSharePayloadReady() else {
            return false
        }

        deferredShareAction = action
        let actionLabel = action == .analyzeNow ? "Analyze now" : "Analyze in app"
        shareLog("[WAITING] \(actionLabel) tapped before attachment parsing finished - deferring (pending=\(pendingAttachmentCount))")
        return true
    }

    private func maybeRunDeferredShareAction() {
        guard pendingAttachmentCount == 0, let action = deferredShareAction else {
            return
        }

        guard hasSharePayloadReady() else {
            shareLog("[WAITING] Deferred action pending but no share payload is ready yet")
            return
        }

        deferredShareAction = nil
        let actionLabel = action == .analyzeNow ? "Analyze now" : "Analyze in app"
        shareLog("[SUCCESS] Running deferred action: \(actionLabel)")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch action {
            case .analyzeNow:
                self.analyzeNowTapped()
            case .analyzeInApp:
                self.analyzeInAppTapped()
            }
        }
    }

    private func maybeFinalizeShare() {
        guard pendingAttachmentCount == 0, !hasQueuedRedirect else {
            shareLog("[WAITING] maybeFinalizeShare: waiting (pending=\(pendingAttachmentCount), hasQueued=\(hasQueuedRedirect))")
            return
        }

        // Don't auto-redirect if we're attempting or showing detection results
        if shouldAttemptDetection || isShowingDetectionResults {
            shareLog("[BLOCKED] maybeFinalizeShare: BLOCKED - detection in progress (attempt=\(shouldAttemptDetection), showing=\(isShowingDetectionResults))")
            return
        }

        shareLog("[SUCCESS] maybeFinalizeShare: proceeding with normal redirect")
        hasQueuedRedirect = true
        let message = pendingPostMessage
        saveAndRedirect(message: message)
    }

    private func handleLoadFailure() {
        shareLog("Handling load failure for attachment")
        completeAttachmentProcessing()
    }

    private func processLoadedAttachment(
        data: NSSecureCoding?,
        type: SharedMediaType,
        index: Int,
        content: NSExtensionItem
    ) {
        switch type {
        case .text:
            guard let text = data as? String else {
                shareLog("Attachment index \(index) text payload missing")
                completeAttachmentProcessing()
                return
            }

            // Check if text is actually a URL (YouTube shares often come as text)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let isUrl = trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://")

            if isUrl {
                shareLog("Attachment index \(index) is text but contains URL - promoting to URL type")
                handleMedia(
                    forLiteral: trimmed,
                    type: .url,
                    index: index,
                    content: content
                ) { [weak self] in
                    self?.completeAttachmentProcessing()
                }
            } else {
                shareLog("Attachment index \(index) is text")
                handleMedia(
                    forLiteral: text,
                    type: type,
                    index: index,
                    content: content
                ) { [weak self] in
                    self?.completeAttachmentProcessing()
                }
            }
        case .url:
            if let url = data as? URL {
                shareLog("Attachment index \(index) is URL: \(url)")
                handleMedia(
                    forLiteral: url.absoluteString,
                    type: type,
                    index: index,
                    content: content
                ) { [weak self] in
                    self?.completeAttachmentProcessing()
                }
            } else {
                shareLog("Attachment index \(index) URL payload missing")
                completeAttachmentProcessing()
            }
        default:
            if let url = data as? URL {
                shareLog("Attachment index \(index) is file URL: \(url)")
                handleMedia(
                    forFile: url,
                    type: type,
                    index: index,
                    content: content
                ) { [weak self] in
                    self?.completeAttachmentProcessing()
                }
            } else if let image = data as? UIImage {
                shareLog("Attachment index \(index) is UIImage")
                handleMedia(
                    forUIImage: image,
                    type: type,
                    index: index,
                    content: content
                ) { [weak self] in
                    self?.completeAttachmentProcessing()
                }
            } else if let imageData = data as? Data, let image = UIImage(data: imageData) {
                // Handle raw Data (e.g., from screenshot preview share sheet)
                shareLog("Attachment index \(index) is raw Data converted to UIImage")
                handleMedia(
                    forUIImage: image,
                    type: type,
                    index: index,
                    content: content
                ) { [weak self] in
                    self?.completeAttachmentProcessing()
                }
            } else {
                shareLog("Attachment index \(index) could not be handled for type \(type)")
                completeAttachmentProcessing()
            }
        }
    }

    private func performInstagramApifyFetch(
        instagramUrl: String,
        apiToken: String,
        completion: @escaping (Result<[SharedMediaFile], Error>) -> Void
    ) {
        // Use Apify actor nH2AHrwxeTRJoN5hX via run-sync-get-dataset-items
        // This endpoint waits for the run to complete and returns the dataset items directly
        guard let endpoint = URL(string: "https://api.apify.com/v2/acts/nH2AHrwxeTRJoN5hX/run-sync-get-dataset-items?token=\(apiToken)&timeout=60&memory=2048") else {
            completion(.failure(makeDownloadError("instagram", "Invalid Apify endpoint")))
            return
        }

        let payload: [String: Any] = [
            "resultsLimit": 1,
            "skipPinnedPosts": false,
            "username": [instagramUrl]
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(.failure(makeDownloadError("instagram", "Failed to encode Apify request")))
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 65.0  // 65s to give Apify's 60s timeout a buffer
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                completion(.failure(self.makeDownloadError("instagram", "Instagram scraping failed")))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let data = data else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                completion(.failure(self.makeDownloadError("instagram", "Instagram scraping returned status \(status)")))
                return
            }

            let urls = self.parseApifyInstagramUrls(from: data)
            guard !urls.isEmpty else {
                completion(.failure(self.makeDownloadError("instagram", "Apify did not return any image URLs")))
                return
            }

            self.downloadFirstValidImage(
                from: urls,
                platform: "instagram",
                session: session,
                completion: completion
            )
        }.resume()
    }

    private func parseApifyInstagramUrls(from data: Data) -> [String] {
        // Apify run-sync-get-dataset-items returns an array of items; each item may have displayUrl and images[]
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        var urls: [String] = []

        func addUrl(_ value: Any?) {
            guard let raw = value as? String, !raw.isEmpty else { return }
            urls.append(raw)
        }

        if let array = json as? [[String: Any]] {
            for item in array {
                addUrl(item["displayUrl"])
                if let images = item["images"] as? [Any] {
                    for img in images {
                        addUrl(img)
                    }
                }
                // For sidecar childPosts
                if let children = item["childPosts"] as? [[String: Any]] {
                    for child in children {
                        addUrl(child["displayUrl"])
                        if let cImages = child["images"] as? [Any] {
                            for img in cImages {
                                addUrl(img)
                            }
                        }
                    }
                }
            }
        } else if let dict = json as? [String: Any] {
            // Try to handle if response is wrapped in an object
            if let results = dict["data"] as? [[String: Any]] {
                for item in results {
                    addUrl(item["displayUrl"])
                }
            } else if let results = dict["results"] as? [[String: Any]] {
                for item in results {
                    addUrl(item["displayUrl"])
                }
            }
        }

        // Deduplicate while preserving order
        var seen = Set<String>()
        var unique: [String] = []
        for url in urls {
            if !seen.contains(url) {
                unique.append(url)
                seen.insert(url)
            }
        }
        return unique
    }

    private func suppressKeyboard() {
        let isResponder = textView?.isFirstResponder ?? false
        let isEditable = textView?.isEditable ?? false
        shareLog("suppressKeyboard invoked (isFirstResponder: \(isResponder), isEditable: \(isEditable))")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let scheduledResponder = self.textView?.isFirstResponder ?? false
            shareLog("suppressKeyboard applying changes (isFirstResponder: \(scheduledResponder))")
            self.textView?.isEditable = false
            self.textView?.isSelectable = false
            self.textView?.text = ""
            self.placeholder = ""
            self.textView?.resignFirstResponder()
            self.view.endEditing(true)
            self.textView?.inputView = UIView()
            self.textView?.inputAccessoryView = UIView()
            self.textView?.isHidden = true
            let finalResponder = self.textView?.isFirstResponder ?? false
            shareLog("suppressKeyboard completed (isFirstResponder: \(finalResponder))")
        }
    }

    private func loadIds() {
        let shareExtensionAppBundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        shareLog("bundle id: \(shareExtensionAppBundleIdentifier)")

        if let lastDot = shareExtensionAppBundleIdentifier.lastIndex(of: ".") {
            hostAppBundleIdentifier = String(shareExtensionAppBundleIdentifier[..<lastDot])
        }
        let defaultAppGroupId = "group.\(hostAppBundleIdentifier)"
        shareLog("default app group: \(defaultAppGroupId)")

        let customAppGroupId = Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String
        shareLog("Info.plist AppGroupId: \(customAppGroupId ?? "nil")")

        if let custom = customAppGroupId,
           !custom.isEmpty,
           custom != "$(CUSTOM_GROUP_ID)" {
            appGroupId = custom
        } else {
            appGroupId = defaultAppGroupId
        }
        shareLog("using app group: \(appGroupId)")
    }

    private func handleMedia(
        forLiteral item: String,
        type: SharedMediaType,
        index: Int,
        content: NSExtensionItem,
        completion: @escaping () -> Void
    ) {
        // Only process URLs
        guard type == .url else {
            appendLiteralShare(item: item, type: type)
            completion()
            return
        }

        // Debug: Log the URL being processed
        shareLog("handleMedia processing URL: \(item.prefix(120))")

        // Determine the platform type
        let platformName: String
        let platformType: String
        let downloadFunction: (String, @escaping (Result<[SharedMediaFile], Error>) -> Void) -> Void

        if isInstagramShareCandidate(item) {
            platformName = "Instagram"
            platformType = "instagram"
            downloadFunction = downloadInstagramMedia
        } else if isTikTokShareCandidate(item) {
            platformName = "TikTok"
            platformType = "tiktok"
            downloadFunction = downloadTikTokMedia
        } else if isPinterestShareCandidate(item) {
            platformName = "Pinterest"
            platformType = "pinterest"
            downloadFunction = downloadPinterestMedia
        } else if isYouTubeShareCandidate(item) {
            platformName = "YouTube"
            platformType = "youtube"
            downloadFunction = downloadYouTubeMedia
        } else if isSnapchatShareCandidate(item) {
            platformName = "Snapchat"
            platformType = "snapchat"
            downloadFunction = downloadSnapchatMedia
        } else if isXShareCandidate(item) {
            platformName = "X"
            platformType = "x"
            downloadFunction = downloadXMedia
        } else if isRedditShareCandidate(item) {
            platformName = "Reddit"
            platformType = "reddit"
            downloadFunction = downloadRedditMedia
        } else if isImdbShareCandidate(item) {
            platformName = "IMDb"
            platformType = "imdb"
            downloadFunction = downloadImdbMedia
        } else if isFacebookShareCandidate(item) {
            platformName = "Facebook"
            platformType = "facebook"
            downloadFunction = downloadFacebookMedia
        } else if isGoogleImageShareCandidate(item) {
            platformName = "Google Image"
            platformType = "google_image"
            downloadFunction = downloadGoogleImageMedia
        } else if item.lowercased().hasPrefix("http://") || item.lowercased().hasPrefix("https://") {
            // Generic web link (e.g., from Safari/Chrome/Firefox/Brave)
            platformName = "Generic Link"
            platformType = "generic"
            downloadFunction = downloadGenericLinkMedia
        } else {
            // Not a URL we can download from
            appendLiteralShare(item: item, type: type)
            completion()
            return
        }

        // Check if this is a supported tutorial platform
        // If it's from a specific app/platform but NOT in our tutorial list, show unsupported alert
        let isFromSpecificPlatform = platformType != "generic"
        let isGenericWebLink = platformType == "generic"

        if isFromSpecificPlatform && !isGenericWebLink && !isTutorialSupportedUrl(item) {
            shareLog("URL from \(platformName) is not in tutorial - showing unsupported alert")
            presentUnsupportedAlert(for: item)
            completion()
            return
        }

        shareLog("Detected \(platformName) URL share - showing choice UI before download")

        // Check if detection is configured
        let hasDetectionConfig = detectorEndpoint() != nil && serpApiKey() != nil

        if hasDetectionConfig {
            // Store the URL and completion for later processing
            pendingInstagramUrl = item
            pendingInstagramCompletion = completion
            pendingPlatformType = platformType

            // Choice UI is already visible - just wait for user decision
            shareLog("\(platformName) URL detected - awaiting user decision (buttons already visible)")
            shareLog("DEBUG: Stored pendingInstagramUrl for \(platformName) - URL: \(item.prefix(50))...")
            return
        } else {
            // No detection configured - proceed with normal download flow
            shareLog("No detection configured - starting normal \(platformName) download")
            updateProcessingStatus("processing")

            downloadFunction(item) { [weak self] result in
                guard let self = self else {
                    completion()
                    return
                }

                switch result {
                case .success(let downloaded):
                    if downloaded.isEmpty {
                        shareLog("\(platformName) download succeeded but returned no files - falling back to literal URL")
                        self.appendLiteralShare(item: item, type: type)
                    } else {
                        self.sharedMedia.append(contentsOf: downloaded)
                        shareLog("Appended \(downloaded.count) downloaded \(platformName) file(s) - count now \(self.sharedMedia.count)")
                    }
                    completion()
                case .failure(let error):
                    shareLog("ERROR: \(platformName) download failed - \(error.localizedDescription)")
                    self.appendLiteralShare(item: item, type: type)
                    completion()
                }
            }
            return
        }
    }

    private func handleMedia(
        forUIImage image: UIImage,
        type: SharedMediaType,
        index: Int,
        content: NSExtensionItem,
        completion: @escaping () -> Void
    ) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            shareLog("ERROR: containerURL was nil while handling UIImage")
            completion()
            return
        }
        let tempPath = containerURL.appendingPathComponent("TempImage.png")
        if writeTempFile(image, to: tempPath) {
            let newPathDecoded = tempPath.absoluteString.removingPercentEncoding ?? tempPath.absoluteString
            let shared = SharedMediaFile(
                path: newPathDecoded,
                mimeType: type == .image ? "image/png" : nil,
                type: type
            )
            sharedMedia.append(shared)
            shareLog("Saved UIImage to \(newPathDecoded) - count now \(sharedMedia.count)")

            // Capture pending image data for inline preview if not already set
            if pendingImageData == nil {
                if let data = try? Data(contentsOf: tempPath) {
                    pendingImageData = data
                    pendingSharedFile = shared
                    shareLog("Captured pendingImageData from UIImage for inline preview (\(data.count) bytes)")
                }
            }
        } else {
            shareLog("ERROR: Failed to write UIImage for index \(index)")
        }
        completion()
    }

    private func handleMedia(
        forFile url: URL,
        type: SharedMediaType,
        index: Int,
        content: NSExtensionItem,
        completion: @escaping () -> Void
    ) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            shareLog("ERROR: containerURL was nil while handling file URL")
            completion()
            return
        }
        let fileName = getFileName(from: url, type: type)
        let newPath = containerURL.appendingPathComponent(fileName)

        if copyFile(at: url, to: newPath) {
            let newPathDecoded = newPath.absoluteString.removingPercentEncoding ?? newPath.absoluteString
            shareLog("copyFile succeeded to \(newPathDecoded)")
            if type == .video {
                if let videoInfo = getVideoInfo(from: url) {
                    let thumbnailPathDecoded = videoInfo.thumbnail?.removingPercentEncoding
                    sharedMedia.append(SharedMediaFile(
                        path: newPathDecoded,
                        mimeType: url.mimeType(),
                        thumbnail: thumbnailPathDecoded,
                        duration: videoInfo.duration,
                        type: type
                    ))
                    shareLog("Stored video at \(newPathDecoded) - count now \(sharedMedia.count)")
                }
            } else {
                let shared = SharedMediaFile(
                    path: newPathDecoded,
                    mimeType: url.mimeType(),
                    type: type
                )
                sharedMedia.append(shared)
                shareLog("Stored file at \(newPathDecoded) - count now \(sharedMedia.count)")

                // Capture pending image data for inline preview when the file is an image
                if type == .image && pendingImageData == nil {
                    do {
                        let data = try Data(contentsOf: newPath)
                        pendingImageData = data
                        pendingSharedFile = shared
                        shareLog("Captured pendingImageData for inline preview (\(data.count) bytes)")
                    } catch {
                        shareLog("WARN: Failed to load image data for inline preview: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            shareLog("ERROR: Failed to copy file \(url)")
        }
        completion()
    }

    private func appendLiteralShare(item: String, type: SharedMediaType) {
        let mimeType: String?
        if type == .text {
            mimeType = "text/plain"
        } else if type == .url {
            mimeType = "text/plain"
        } else {
            mimeType = nil
        }

        sharedMedia.append(
            SharedMediaFile(
                path: item,
                mimeType: mimeType,
                message: type == .url ? item : nil,
                type: type
            )
        )
        shareLog("Appended literal item (type \(type)) - count now \(sharedMedia.count)")

        if pendingPlatformType == nil {
            if let inferred = inferredPlatformType {
                pendingPlatformType = inferred
            } else if type == .url {
                pendingPlatformType = "web"
            }
        }
    }

    private func presentUnsupportedAlert(for url: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.hasPresentedUnsupportedAlert { return }
            self.hasPresentedUnsupportedAlert = true

            let alert = UIAlertController(
                title: "Not supported",
                message: "This link isn't supported yet. Try Instagram, TikTok, Pinterest, IMDb, YouTube, X, or any website.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .cancel) { [weak self] _ in
                self?.hasPresentedUnsupportedAlert = false
                self?.extensionContext?.cancelRequest(withError: NSError(domain: "com.worthify.worthify", code: -1, userInfo: nil))
            })
            self.present(alert, animated: true, completion: nil)
        }
    }

    private func isTutorialSupportedUrl(_ value: String) -> Bool {
        // Apps shown in "Add your first style" tutorial page + YouTube and Google Images which work
        return isInstagramShareCandidate(value) ||
               isPinterestShareCandidate(value) ||
               isTikTokShareCandidate(value) ||
               isImdbShareCandidate(value) ||
               isYouTubeShareCandidate(value) ||
               isXShareCandidate(value) ||
               isGoogleImageShareCandidate(value)
    }

    private func isInstagramShareCandidate(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.contains("instagram.com/p/") || trimmed.contains("instagram.com/reel/")
    }

    private func isTikTokShareCandidate(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Match various TikTok URL formats:
        // - tiktok.com/@ (profile or video)
        // - tiktok.com/video/ (direct video)
        // - tiktok.com/t/ (short links)
        // - vm.tiktok.com/ (short redirect URLs)
        // - vt.tiktok.com/ (another short format)
        if trimmed.contains("vm.tiktok.com/") || trimmed.contains("vt.tiktok.com/") {
            return true
        }
        return trimmed.contains("tiktok.com/") && (trimmed.contains("/video/") || trimmed.contains("/@") || trimmed.contains("/t/"))
    }

    private func isPinterestShareCandidate(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.contains("pinterest.com/pin/") || trimmed.contains("pin.it/")
    }

    private func isImdbShareCandidate(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasDomain = trimmed.contains("imdb.com") || trimmed.contains("imdb.to")
        if !hasDomain { return false }

        let hasValidPattern = trimmed.contains("/title/tt") ||
                             trimmed.contains("/video/") ||
                             trimmed.contains("/name/nm") ||
                             trimmed.contains("/gallery/") ||
                             trimmed.contains("/mediaviewer/") ||
                             trimmed.contains("/rm")

        if hasValidPattern {
            shareLog("IMDb URL detected: \(trimmed.prefix(80))")
        } else {
            shareLog("IMDb domain found but no valid pattern: \(trimmed.prefix(80))")
        }

        return hasValidPattern
    }

    private func isYouTubeShareCandidate(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Check if it contains YouTube domain
        let hasYouTubeDomain = trimmed.contains("youtube.com") ||
                              trimmed.contains("youtu.be") ||
                              trimmed.contains("m.youtube.com")

        if !hasYouTubeDomain {
            return false
        }

        // Must have video ID indicator
        let hasVideoPattern = trimmed.contains("/watch") ||
                             trimmed.contains("/shorts/") ||
                             trimmed.contains("youtu.be/") ||
                             trimmed.contains("/v/") ||
                             trimmed.contains("/embed/") ||
                             trimmed.contains("?v=") ||
                             trimmed.contains("&v=")

        if hasVideoPattern {
            shareLog("YouTube URL detected: \(trimmed.prefix(80))")
        } else {
            shareLog("YouTube domain found but no video pattern: \(trimmed.prefix(80))")
        }

        return hasVideoPattern
    }

    private func isSnapchatShareCandidate(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Match Snapchat URL formats:
        // - snapchat.com/spotlight/ (Spotlight videos)
        // - snapchat.com/t/ (short links)
        // - snapchat.com/add/ (user profiles)
        let hasSnapchatDomain = trimmed.contains("snapchat.com")
        if !hasSnapchatDomain {
            return false
        }

        let hasValidPattern = trimmed.contains("/spotlight/") ||
                             trimmed.contains("/t/") ||
                             trimmed.contains("/add/")

        if hasValidPattern {
            shareLog("Snapchat URL detected: \(trimmed.prefix(80))")
        } else {
            shareLog("Snapchat domain found but no valid pattern: \(trimmed.prefix(80))")
        }

        return hasValidPattern
    }

    private func isRedditShareCandidate(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasDomain = trimmed.contains("reddit.com") || trimmed.contains("redd.it")
        if !hasDomain {
            return false
        }

        let hasValidPattern = trimmed.contains("/comments/") ||
                             trimmed.contains("/r/") ||
                             trimmed.contains("redd.it/")

        if hasValidPattern {
            shareLog("Reddit URL detected: \(trimmed.prefix(80))")
        } else {
            shareLog("Reddit domain found but no valid pattern: \(trimmed.prefix(80))")
        }

        return hasValidPattern
    }

    private func isXShareCandidate(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasDomain = trimmed.contains("x.com") || trimmed.contains("twitter.com")
        if !hasDomain {
            return false
        }

        let hasValidPattern = trimmed.contains("/status/") ||
                             trimmed.contains("/statuses/") ||
                             trimmed.contains("/i/web/status/") ||
                             trimmed.contains("/i/status/") ||
                             trimmed.contains("/photo/")

        if hasValidPattern {
            shareLog("X/Twitter URL detected: \(trimmed.prefix(80))")
        } else {
            shareLog("X/Twitter domain found but no valid pattern: \(trimmed.prefix(80))")
        }

        return hasValidPattern
    }

    private func isFacebookShareCandidate(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Match Facebook URL formats:
        // - facebook.com/share/ (share links)
        // - facebook.com/photo/ or facebook.com/photos/ (photo posts)
        // - facebook.com/permalink.php (permanent links)
        // - facebook.com/watch/ (videos)
        // - fb.watch/ (short video links)
        let hasFacebookDomain = trimmed.contains("facebook.com") || trimmed.contains("fb.watch")
        if !hasFacebookDomain {
            return false
        }

        let hasValidPattern = trimmed.contains("/share/") ||
                             trimmed.contains("/photo") ||
                             trimmed.contains("/photos/") ||
                             trimmed.contains("/permalink.php") ||
                             trimmed.contains("/watch/") ||
                             trimmed.contains("fb.watch/")

        if hasValidPattern {
            shareLog("Facebook URL detected: \(trimmed.prefix(80))")
        } else {
            shareLog("Facebook domain found but no valid pattern: \(trimmed.prefix(80))")
        }

        return hasValidPattern
    }

    private func isGoogleImageShareCandidate(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasGoogleHost = trimmed.contains("://www.google.") ||
                           trimmed.contains("://google.") ||
                           trimmed.contains("www.google.") ||
                           trimmed.contains("google.")
        if !hasGoogleHost { return false }
        let hasImgresPath = trimmed.contains("/imgres") || trimmed.contains("/search")
        if !hasImgresPath { return false }
        return trimmed.contains("imgurl=")
    }

    private func isDownloadableUrlCandidate(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isHttp = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")

        return isInstagramShareCandidate(value) ||
               isTikTokShareCandidate(value) ||
               isPinterestShareCandidate(value) ||
               isYouTubeShareCandidate(value) ||
               isSnapchatShareCandidate(value) ||
               isRedditShareCandidate(value) ||
               isXShareCandidate(value) ||
               isImdbShareCandidate(value) ||
               isFacebookShareCandidate(value) ||
               isGoogleImageShareCandidate(value) ||
               isHttp // allow generic web links (browsers) to flow through
    }

    // Legacy function for backward compatibility
    private func isSocialMediaShareCandidate(_ value: String) -> Bool {
        return isInstagramShareCandidate(value) || isTikTokShareCandidate(value)
    }

    private func apifyApiToken() -> String? {
        if let defaults = UserDefaults(suiteName: appGroupId),
           let key = defaults.string(forKey: "ApifyApiToken"),
           !key.isEmpty {
            shareLog("Using Apify token from shared defaults")
            return key
        }

        if let infoKey = Bundle.main.object(forInfoDictionaryKey: "ApifyApiToken") as? String,
           !infoKey.isEmpty {
            shareLog("Using Apify token from Info.plist fallback")
            return infoKey
        }

        return nil
    }

    private func updateProcessingStatus(_ status: String) {
        guard !appGroupId.isEmpty,
              let defaults = UserDefaults(suiteName: appGroupId) else { return }
        defaults.set(status, forKey: kProcessingStatusKey)
        defaults.synchronize()
        DispatchQueue.main.async { [weak self] in
            self?.refreshStatusLabel()
        }
    }

    private func downloadInstagramMedia(
        from urlString: String,
        completion: @escaping (Result<[SharedMediaFile], Error>) -> Void
    ) {
        if let serverBaseUrl = getServerBaseUrl() {
            fetchCachedInstagramImageUrl(
                instagramUrl: urlString,
                serverBaseUrl: serverBaseUrl
            ) { [weak self] cachedUrl in
                guard let self = self else { return }

                if let cachedUrl = cachedUrl {
                    shareLog("Instagram cache HIT (server) - using cached image URL")
                    self.downloadFirstValidImage(
                        from: [cachedUrl],
                        platform: "instagram",
                        session: URLSession.shared,
                        completion: completion
                    )
                    return
                }

                self.downloadInstagramViaApify(
                    urlString: urlString,
                    completion: completion
                )
            }
            return
        }

        downloadInstagramViaApify(urlString: urlString, completion: completion)
    }

    private func downloadInstagramViaApify(
        urlString: String,
        completion: @escaping (Result<[SharedMediaFile], Error>) -> Void
    ) {
        guard let apifyToken = apifyApiToken(), !apifyToken.isEmpty else {
            shareLog("[WARNING] Apify token missing - Instagram scraping disabled")
            completion(.failure(makeDownloadError("instagram", "Instagram scraping not configured. Please open the Worthify app to set up the Apify token.")))
            return
        }

        performInstagramApifyFetch(
            instagramUrl: urlString,
            apiToken: apifyToken,
            completion: completion
        )
    }

    private func fetchCachedInstagramImageUrl(
        instagramUrl: String,
        serverBaseUrl: String,
        completion: @escaping (String?) -> Void
    ) {
        guard var components = URLComponents(string: serverBaseUrl + "/api/v1/instagram/cache") else {
            completion(nil)
            return
        }

        components.queryItems = [
            URLQueryItem(name: "url", value: instagramUrl)
        ]

        guard let url = components.url else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 6.0

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                shareLog("Instagram cache check failed: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(nil)
                return
            }

            guard httpResponse.statusCode == 200, let data = data else {
                completion(nil)
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let cached = json["cached"] as? Bool ?? false
                    let imageUrl = json["image_url"] as? String
                    if cached, let imageUrl = imageUrl, !imageUrl.isEmpty {
                        completion(imageUrl)
                        return
                    }
                }
            } catch {
                shareLog("Instagram cache check parse error: \(error.localizedDescription)")
            }

            completion(nil)
        }
        task.resume()
    }

    // MARK: - TikTok Scraping

    private func downloadTikTokMedia(
        from urlString: String,
        completion: @escaping (Result<[SharedMediaFile], Error>) -> Void
    ) {
        // Free path: try TikTok oEmbed first (no ScrapingBee credits).
        fetchTikTokOEmbedThumbnail(urlString: urlString) { [weak self] thumbUrl in
            guard let self = self else { return }

            let fallbackToHtml: (String) -> Void = { [weak self] reason in
                guard let self = self else { return }
                shareLog("TikTok oEmbed path failed (\(reason)); attempting HTML scraping for slideshow/photo content...")
                self.downloadTikTokMediaViaHtmlScrape(from: urlString, completion: completion)
            }

            guard let thumbUrl = thumbUrl else {
                fallbackToHtml("oEmbed thumbnail unavailable")
                return
            }

            self.downloadFirstValidImage(
                from: [thumbUrl],
                platform: "tiktok",
                session: URLSession.shared,
                cropToAspect: 9.0 / 16.0
            ) { result in
                switch result {
                case .success(let downloaded):
                    if downloaded.isEmpty {
                        fallbackToHtml("oEmbed download returned no files")
                    } else {
                        completion(.success(downloaded))
                    }
                case .failure(let error):
                    shareLog("TikTok oEmbed thumbnail download failed - \(error.localizedDescription)")
                    fallbackToHtml(error.localizedDescription)
                }
            }
        }
    }

    private func downloadTikTokMediaViaHtmlScrape(
        from urlString: String,
        completion: @escaping (Result<[SharedMediaFile], Error>) -> Void
    ) {
        resolveTikTokRedirect(urlString: urlString) { [weak self] resolvedUrl in
            guard let self = self else { return }

            let targetUrl = resolvedUrl ?? urlString
            guard let url = URL(string: targetUrl) else {
                completion(.failure(self.makeDownloadError("tiktok", "Invalid URL")))
                return
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 15.0
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
                forHTTPHeaderField: "User-Agent"
            )

            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }

                guard error == nil,
                      let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let data = data,
                      let html = String(data: data, encoding: .utf8) else {
                    completion(.failure(self.makeDownloadError("tiktok", "Failed to fetch HTML")))
                    return
                }

                if self.isTikTokBlockedPage(html) {
                    shareLog("TikTok HTML appears login/verification gated - trying best-effort extraction")
                }

                let imageUrls = self.extractTikTokImageUrls(from: html)
                let viableImageUrls = imageUrls.filter { !self.isTikTokLoginOrStaticUrl($0) }

                let proceedWithImageUrls: ([String]) -> Void = { urls in
                    guard !urls.isEmpty else {
                        completion(.failure(self.makeDownloadError("tiktok", "No image URLs to try")))
                        return
                    }

                    shareLog("Found \(urls.count) slideshow image(s), downloading first one...")
                    self.downloadFirstValidImage(
                        from: urls,
                        platform: "tiktok",
                        session: URLSession.shared,
                        cropToAspect: 9.0 / 16.0,
                        completion: completion
                    )
                }

                if !viableImageUrls.isEmpty {
                    proceedWithImageUrls(viableImageUrls)
                    return
                }

                shareLog("No viable TikTok slideshow URLs from primary HTML parse; trying generic scrape fallback...")
                self.quickGenericImageScrape(urlString: targetUrl) { [weak self] quickImages in
                    guard let self = self else { return }
                    let quickViable = quickImages.filter { !self.isTikTokLoginOrStaticUrl($0) }
                    if !quickViable.isEmpty {
                        shareLog("Generic scrape fallback found \(quickViable.count) candidate image URL(s)")
                        proceedWithImageUrls(quickViable)
                        return
                    }

                    if targetUrl != urlString {
                        self.quickGenericImageScrape(urlString: urlString) { [weak self] shortLinkImages in
                            guard let self = self else { return }
                            let shortLinkViable = shortLinkImages.filter { !self.isTikTokLoginOrStaticUrl($0) }
                            if !shortLinkViable.isEmpty {
                                shareLog("Short-link generic fallback found \(shortLinkViable.count) candidate image URL(s)")
                                proceedWithImageUrls(shortLinkViable)
                            } else {
                                completion(.failure(self.makeDownloadError("tiktok", "No images found in slideshow")))
                            }
                        }
                    } else {
                        completion(.failure(self.makeDownloadError("tiktok", "No images found in slideshow")))
                    }
                }
            }
            task.resume()
        }
    }

    private func fetchTikTokOEmbedThumbnail(
        urlString: String,
        completion: @escaping (String?) -> Void
    ) {
        resolveTikTokRedirect(urlString: urlString) { [weak self] resolvedUrl in
            guard let self = self else { return }

            let targetUrl = resolvedUrl ?? urlString

            guard let encoded = targetUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let oembedUrl = URL(string: "https://www.tiktok.com/oembed?url=\(encoded)") else {
                completion(nil)
                return
            }

            var request = URLRequest(url: oembedUrl)
            request.timeoutInterval = 10.0
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
                forHTTPHeaderField: "User-Agent"
            )

            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }

                guard error == nil,
                      let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(nil)
                    return
                }

                if let thumb = (json["thumbnail_url"] as? String)
                    ?? (json["thumbnailUrl"] as? String)
                    ?? (json["thumbnailURL"] as? String),
                   !thumb.isEmpty {
                    shareLog("TikTok oEmbed thumbnail: \(thumb.prefix(80))...")
                    completion(thumb)
                    return
                }

                completion(nil)
            }
            task.resume()
        }
    }

    private func resolveTikTokRedirect(
        urlString: String,
        completion: @escaping (String?) -> Void
    ) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        request.httpMethod = "GET"

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil else {
                completion(nil)
                return
            }
            if let finalUrl = response?.url?.absoluteString, finalUrl != urlString {
                completion(finalUrl)
            } else {
                completion(nil)
            }
        }
        task.resume()
    }

    private func isTikTokBlockedPage(_ html: String) -> Bool {
        let lowered = html.lowercased()
        if lowered.contains("captcha") || lowered.contains("verify") || lowered.contains("login") && lowered.contains("tiktok") {
            return true
        }
        if lowered.contains("please enable javascript") || lowered.contains("robot check") {
            return true
        }
        if let titleRange = html.range(of: "<title>([^<]*)</title>", options: .regularExpression),
           html[titleRange].lowercased().contains("log in | tiktok") {
            return true
        }
        return false
    }

    private func isTikTokLoginOrStaticUrl(_ url: String) -> Bool {
        let lowered = url.lowercased()

        if lowered.contains("sf16-website-login") ||
            lowered.contains("website-login.neutral.tiktokcdn") ||
            lowered.contains("tiktok_web_login_static") ||
            lowered.contains("/obj/tiktok_web_login_static") {
            return true
        }

        return false
    }

    private func extractTikTokImageUrls(from html: String) -> [String] {
        var priorityResults: [String] = []
        var fallbackResults: [String] = []

        func appendUnique(_ url: String, to array: inout [String]) {
            if !array.contains(url) {
                array.append(url)
                shareLog("Added TikTok image URL: \(url.prefix(80))...")
            }
        }

        func cleaned(_ candidate: String) -> String {
            var cleaned = candidate.replacingOccurrences(of: "&amp;", with: "&")

            // Strip JSON delimiters and extract just the URL part
            // Example: https://url.com","other":"stuff -> https://url.com
            if let firstQuote = cleaned.firstIndex(of: "\"") {
                cleaned = String(cleaned[..<firstQuote])
            }
            if let firstComma = cleaned.firstIndex(of: ",") {
                cleaned = String(cleaned[..<firstComma])
            }

            return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func isLowValue(_ url: String) -> Bool {
            if self.isTikTokLoginOrStaticUrl(url) {
                shareLog("Filtered out low-value URL (login/static page): \(url.prefix(80))...")
                return true
            }

            // API endpoints and WebSocket URLs
            if url.contains("-api.") || url.contains("/api/") || url.contains("im-ws.") || url.contains("wss://") {
                shareLog("Filtered out low-value URL (API endpoint): \(url.prefix(80))...")
                return true
            }

            let lowered = url.lowercased()
            if lowered.contains(".js") || lowered.contains(".css") || lowered.contains(".map") {
                shareLog("Filtered out low-value URL (script/style): \(url.prefix(80))...")
                return true
            }

            // Must contain tiktokcdn for TikTok images
            if !url.contains("tiktokcdn") {
                shareLog("Filtered out low-value URL (not tiktokcdn): \(url.prefix(80))...")
                return true
            }

            // Filter out small thumbnails and avatars
            if url.contains("avt-") || url.contains("100x100") || url.contains("cropcenter") || url.contains("music") {
                shareLog("Filtered out low-value URL (thumbnail/avatar): \(url.prefix(80))...")
                return true
            }

            // Allow through - even if it has "login" or "static" in the path,
            // let the download attempt decide if it's valid
            return false
        }

        // Meta tags: og:image / twitter:image often hold the best thumbnail
        let metaPattern = "<meta[^>]+property=\"(?:og:image|twitter:image)\"[^>]+content=\"([^\"]+)\""
        if let regex = try? NSRegularExpression(pattern: metaPattern, options: [.caseInsensitive]) {
            let nsrange = NSRange(html.startIndex..<html.endIndex, in: html)
            regex.enumerateMatches(in: html, options: [], range: nsrange) { match, _, _ in
                guard let match = match,
                      match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: html) else { return }
                let candidate = cleaned(String(html[range]))
                if !isLowValue(candidate) {
                    appendUnique(candidate, to: &priorityResults)
                }
            }
        }

        // HIGHEST PRIORITY: Photo mode / slideshow images
        // These have "photomode" or "i-photomode" in the path
        let photomodePattern = "(https://[^\"\\s,]*tiktokcdn[^\"\\s,]*photomode[^\"\\s,]*)"
        if let regex = try? NSRegularExpression(pattern: photomodePattern, options: [.caseInsensitive]) {
            let nsrange = NSRange(html.startIndex..<html.endIndex, in: html)
            regex.enumerateMatches(in: html, options: [], range: nsrange) { match, _, _ in
                guard let match = match,
                      match.numberOfRanges > 0,
                      let range = Range(match.range(at: 0), in: html) else { return }
                let candidate = cleaned(String(html[range]))
                if !isLowValue(candidate) {
                    appendUnique(candidate, to: &priorityResults)
                }
            }
        }

        // If we found photomode images, return only those (highest quality)
        if !priorityResults.isEmpty {
            shareLog("Extracted \(priorityResults.count) TikTok photomode image URL(s)")
            return priorityResults
        }

        // JSON cover fields (present in TikTok initial data)
        let coverPattern = "\"cover\"\\s*:\\s*\"(https://[^\"]*tiktokcdn[^\"]*)\""
        if let regex = try? NSRegularExpression(pattern: coverPattern, options: [.caseInsensitive]) {
            let nsrange = NSRange(html.startIndex..<html.endIndex, in: html)
            regex.enumerateMatches(in: html, options: [], range: nsrange) { match, _, _ in
                guard let match = match,
                      match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: html) else { return }
                let candidate = cleaned(String(html[range]))
                if !isLowValue(candidate) {
                    appendUnique(candidate, to: &priorityResults)
                }
            }
        }

        // Pattern 1: Look for high-quality video thumbnails from tiktokcdn.com
        // These are in img src with tplv-tiktokx-origin.image (highest priority)
        let originPattern = "src=\"(https://[^\"]*tiktokcdn[^\"]*tplv-tiktokx-origin\\.image[^\"]*)\""
        if let regex = try? NSRegularExpression(pattern: originPattern, options: [.caseInsensitive]) {
            let nsrange = NSRange(html.startIndex..<html.endIndex, in: html)
            regex.enumerateMatches(in: html, options: [], range: nsrange) { match, _, _ in
                guard let match = match,
                      match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: html) else { return }
                let candidate = cleaned(String(html[range]))
                // Skip avatars and small images
                if isLowValue(candidate) {
                    return
                }
                appendUnique(candidate, to: &priorityResults)
            }
        }

        // If we found high-quality thumbnails, return only those
        if !priorityResults.isEmpty {
            shareLog("Extracted \(priorityResults.count) high-quality TikTok image URL(s)")
            return priorityResults
        }

        // Pattern 2: Look for poster images in video tags (fallback)
        let posterPattern = "poster=\"(https://[^\"]*tiktokcdn[^\"]*)\""
        if let regex = try? NSRegularExpression(pattern: posterPattern, options: [.caseInsensitive]) {
            let nsrange = NSRange(html.startIndex..<html.endIndex, in: html)
            regex.enumerateMatches(in: html, options: [], range: nsrange) { match, _, _ in
                guard let match = match,
                      match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: html) else { return }
                let candidate = cleaned(String(html[range]))
                if !isLowValue(candidate) {
                    appendUnique(candidate, to: &fallbackResults)
                }
            }
        }

        // Pattern 3: Any img src from tiktokcdn that looks like a thumbnail
        let imgPattern = "<img[^>]+src=\"(https://[^\"]*tiktokcdn[^\"]+)\""
        if let regex = try? NSRegularExpression(pattern: imgPattern, options: [.caseInsensitive]) {
            let nsrange = NSRange(html.startIndex..<html.endIndex, in: html)
            regex.enumerateMatches(in: html, options: [], range: nsrange) { match, _, _ in
                guard let match = match,
                      match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: html) else { return }
                let candidate = cleaned(String(html[range]))
                if !isLowValue(candidate) {
                    appendUnique(candidate, to: &fallbackResults)
                }
            }
        }

        // Pattern 4: Any tiktokcdn image URL in body as a last resort (supports photo-mode without extension)
        let loosePattern = "https://\\S*tiktokcdn\\S*"
        if let regex = try? NSRegularExpression(pattern: loosePattern, options: [.caseInsensitive]) {
            let nsrange = NSRange(html.startIndex..<html.endIndex, in: html)
            regex.enumerateMatches(in: html, options: [], range: nsrange) { match, _, _ in
                guard let match = match,
                      match.numberOfRanges > 0,
                      let range = Range(match.range(at: 0), in: html) else { return }
                let candidate = cleaned(String(html[range]))
                if !isLowValue(candidate) {
                    appendUnique(candidate, to: &fallbackResults)
                }
            }
        }

        // Pattern 5: Markdown image syntax ![](url) capturing tiktokcdn URLs specifically
        let markdownImagePattern = "!\\[[^\\]]*\\]\\((https?://[^)]+tiktokcdn[^)]+)\\)"
        if let regex = try? NSRegularExpression(pattern: markdownImagePattern, options: [.caseInsensitive]) {
            let nsrange = NSRange(html.startIndex..<html.endIndex, in: html)
            regex.enumerateMatches(in: html, options: [], range: nsrange) { match, _, _ in
                guard let match = match,
                      match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: html) else { return }
                let candidate = cleaned(String(html[range]))
                if !isLowValue(candidate) {
                    appendUnique(candidate, to: &fallbackResults)
                }
            }
        }

        // Some TikTok pages keep slideshow URLs in escaped JSON (https:\/\/...).
        // Decode escaped slashes and run a targeted pass for likely image URLs.
        let normalizedHtml = html.replacingOccurrences(of: "\\/", with: "/")
        if normalizedHtml != html {
            let normalizedPattern =
                "(https://[^\"\\s,]*tiktokcdn[^\"\\s,]*(?:photomode|tplv|\\.(?:jpe?g|png|webp))[^\"\\s,]*)"
            if let regex = try? NSRegularExpression(
                pattern: normalizedPattern,
                options: [.caseInsensitive]
            ) {
                let nsrange = NSRange(normalizedHtml.startIndex..<normalizedHtml.endIndex, in: normalizedHtml)
                regex.enumerateMatches(in: normalizedHtml, options: [], range: nsrange) { match, _, _ in
                    guard let match = match,
                          match.numberOfRanges > 0,
                          let range = Range(match.range(at: 0), in: normalizedHtml) else { return }
                    let candidate = cleaned(String(normalizedHtml[range]))
                    if !isLowValue(candidate) {
                        appendUnique(candidate, to: &priorityResults)
                    }
                }
            }
        }

        if !priorityResults.isEmpty {
            shareLog("Extracted \(priorityResults.count) TikTok image URL(s) from normalized JSON")
            return priorityResults
        }

        shareLog("Extracted \(fallbackResults.count) TikTok image URL(s)")
        return fallbackResults
    }

    // MARK: - Pinterest Scraping

    private func downloadPinterestMedia(
        from urlString: String,
        completion: @escaping (Result<[SharedMediaFile], Error>) -> Void
    ) {
        shareLog("Attempting to fetch Pinterest content...")

        resolvePinterestRedirect(urlString) { [weak self] resolvedUrl in
            guard let self = self else { return }
            let targetUrl = resolvedUrl ?? urlString
            if resolvedUrl != nil {
                shareLog("Pinterest short link resolved to \(targetUrl.prefix(120))")
            }

            // Try generic scrape first (free)
            self.quickGenericImageScrape(urlString: targetUrl) { [weak self] quickImages in
                guard let self = self else { return }

                if !quickImages.isEmpty {
                    shareLog("Found \(quickImages.count) image(s) from Pinterest via direct scrape")
                    self.downloadFirstValidImage(
                        from: quickImages,
                        platform: "pinterest",
                        session: URLSession.shared,
                        completion: completion
                    )
                    return
                }

                completion(.failure(self.makeDownloadError("Pinterest", "No images found in Pinterest content")))
            }
        }
    }

    private func resolvePinterestRedirect(_ urlString: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8.0
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        URLSession.shared.dataTask(with: request) { _, response, _ in
            let finalUrl = response?.url?.absoluteString
            if finalUrl == urlString {
                // No redirect occurred
                completion(nil)
            } else {
                completion(finalUrl)
            }
        }.resume()
    }

    private func extractPinterestImageUrls(from html: String) -> [String] {
        var results: [String] = []
        var seenUrls = Set<String>()

        // Pattern 1: og:image meta tag (usually highest quality)
        let ogImagePattern = "<meta[^>]+property=\"og:image\"[^>]+content=\"([^\"]+)\""
        if let regex = try? NSRegularExpression(pattern: ogImagePattern, options: [.caseInsensitive]) {
            let nsrange = NSRange(html.startIndex..<html.endIndex, in: html)
            if let match = regex.firstMatch(in: html, options: [], range: nsrange),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: html) {
                let url = String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
                if !seenUrls.contains(url) {
                    seenUrls.insert(url)
                    results.append(url)
                }
            }
        }

        // Pattern 2: originals pinimg (highest resolution)
        let originalsPattern = "src=\"(https://i\\.pinimg\\.com/originals/[^\"]+\\.(?:jpg|jpeg|png|webp))\""
        if let regex = try? NSRegularExpression(pattern: originalsPattern, options: [.caseInsensitive]) {
            let nsrange = NSRange(html.startIndex..<html.endIndex, in: html)
            regex.enumerateMatches(in: html, options: [], range: nsrange) { match, _, _ in
                guard let match = match, match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: html) else { return }
                let url = String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
                if !seenUrls.contains(url) {
                    seenUrls.insert(url)
                    results.append(url)
                }
            }
        }

        // Pattern 3: 564x pinimg (medium-high resolution)
        let mediumPattern = "src=\"(https://i\\.pinimg\\.com/564x/[^\"]+\\.(?:jpg|jpeg|png|webp))\""
        if let regex = try? NSRegularExpression(pattern: mediumPattern, options: [.caseInsensitive]) {
            let nsrange = NSRange(html.startIndex..<html.endIndex, in: html)
            regex.enumerateMatches(in: html, options: [], range: nsrange) { match, _, _ in
                guard let match = match, match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: html) else { return }
                let url = String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
                if !seenUrls.contains(url) {
                    seenUrls.insert(url)
                    results.append(url)
                }
            }
        }

        // Pattern 4: Any pinimg URL as fallback
        let anyPinimgPattern = "src=\"(https://i\\.pinimg\\.com/[^\"]+\\.(?:jpg|jpeg|png|webp))\""
        if let regex = try? NSRegularExpression(pattern: anyPinimgPattern, options: [.caseInsensitive]) {
            let nsrange = NSRange(html.startIndex..<html.endIndex, in: html)
            regex.enumerateMatches(in: html, options: [], range: nsrange) { match, _, _ in
                guard let match = match, match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: html) else { return }
                let url = String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
                if !seenUrls.contains(url) {
                    seenUrls.insert(url)
                    results.append(url)
                }
            }
        }

        shareLog("Extracted \(results.count) Pinterest image URL(s)")
        return results
    }

    // MARK: - YouTube Thumbnail Download

    private func downloadYouTubeMedia(
        from urlString: String,
        completion: @escaping (Result<[SharedMediaFile], Error>) -> Void
    ) {
        let isShortsLink = urlString.lowercased().contains("/shorts")
        guard let videoId = extractYouTubeVideoId(from: urlString) else {
            shareLog("Unable to extract YouTube video ID from \(urlString)")
            completion(.failure(makeDownloadError("YouTube", "Could not extract video ID")))
            return
        }

        let thumbnailUrls = buildYouTubeThumbnailCandidates(videoId: videoId)
        shareLog("Trying \(thumbnailUrls.count) YouTube thumbnail candidates for video \(videoId)")

        downloadFirstValidImage(
            from: thumbnailUrls,
            platform: "youtube",
            session: URLSession.shared,
            cropToAspect: isShortsLink ? (9.0 / 16.0) : nil,
            completion: completion
        )
    }

    private func extractYouTubeVideoId(from urlString: String) -> String? {
        // Pattern 1: youtu.be/VIDEO_ID
        if urlString.contains("youtu.be/") {
            if let range = urlString.range(of: "youtu.be/") {
                var videoId = String(urlString[range.upperBound...])
                // Remove query parameters
                if let queryIndex = videoId.firstIndex(of: "?") {
                    videoId = String(videoId[..<queryIndex])
                }
                return videoId.isEmpty ? nil : videoId
            }
        }

        // Pattern 2: youtube.com/watch?v=VIDEO_ID
        if let url = URL(string: urlString),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            for item in queryItems {
                if item.name == "v", let value = item.value, !value.isEmpty {
                    return value
                }
            }
        }

        // Pattern 3: youtube.com/shorts/VIDEO_ID or youtube.com/v/VIDEO_ID
        let patterns = ["/shorts/", "/v/", "/embed/"]
        for pattern in patterns {
            if let range = urlString.range(of: pattern) {
                var videoId = String(urlString[range.upperBound...])
                // Remove trailing path or query
                if let slashIndex = videoId.firstIndex(of: "/") {
                    videoId = String(videoId[..<slashIndex])
                }
                if let queryIndex = videoId.firstIndex(of: "?") {
                    videoId = String(videoId[..<queryIndex])
                }
                if !videoId.isEmpty {
                    return videoId
                }
            }
        }

        return nil
    }

    private func buildYouTubeThumbnailCandidates(videoId: String) -> [String] {
        var candidates: [String] = []

        // Priority 1: WebP format (better quality/compression) - highest quality
        candidates.append("https://i.ytimg.com/vi_webp/\(videoId)/maxresdefault.webp")
        candidates.append("https://i.ytimg.com/vi_webp/\(videoId)/sddefault.webp")
        candidates.append("https://i.ytimg.com/vi_webp/\(videoId)/hqdefault.webp")

        // Priority 2: Live stream variants (often higher quality for live content)
        candidates.append("https://i.ytimg.com/vi/\(videoId)/maxresdefault_live.jpg")

        // Priority 3: Standard JPG - highest quality variants
        let hosts = [
            "https://i.ytimg.com/vi",
            "https://img.youtube.com/vi"
        ]

        let variants = [
            "maxresdefault.jpg",  // 1920x1080
            "maxres1.jpg",        // Alternate max res
            "maxres2.jpg",
            "maxres3.jpg",
            "hq720.jpg",          // 1280x720
            "sddefault.jpg",      // 640x480
            "hqdefault.jpg",      // 480x360
            "mqdefault.jpg"       // 320x180 (fallback)
        ]

        for host in hosts {
            for variant in variants {
                candidates.append("\(host)/\(videoId)/\(variant)")
            }
        }

        return candidates
    }

    // MARK: - Snapchat Scraping

    private func downloadSnapchatMedia(
        from urlString: String,
        completion: @escaping (Result<[SharedMediaFile], Error>) -> Void
    ) {
        shareLog("Attempting to fetch Snapchat content (no Jina)...")

        // Try lightweight scrape first (og/twitter/img)
        quickGenericImageScrape(urlString: urlString) { [weak self] quickImages in
            guard let self = self else { return }

            if !quickImages.isEmpty {
                shareLog("Found \(quickImages.count) image(s) from Snapchat via direct scrape")

                self.downloadFirstValidImage(
                    from: Array(quickImages.prefix(5)),
                    platform: "snapchat",
                    session: URLSession.shared,
                    cropToAspect: 9.0 / 16.0,
                    completion: completion
                )
                return
            }

            shareLog("No images found via direct scrape for Snapchat URL")
            completion(.failure(self.makeDownloadError("Snapchat", "No images found in Snapchat content")))
        }
    }

    private func extractImagesFromSnapchatHtml(_ html: String, baseUrl: String) -> [String] {
        var posters: [String] = []
        var cdns: [String] = []
        var ogs: [String] = []
        var seen = Set<String>()

        func appendUnique(_ url: String, bucket: inout [String], label: String) {
            guard !url.isEmpty else { return }
            if seen.insert(url).inserted {
                shareLog("Found \(label): \(url.prefix(80))")
                bucket.append(url)
            }
        }

        // Pattern 1: poster attribute in video tags (prefer these first)
        let posterPattern = #"<video\s+[^>]*?poster\s*=\s*["\']([^"\']+)["\']"#
        if let posterRegex = try? NSRegularExpression(pattern: posterPattern, options: [.caseInsensitive]) {
            let nsHtml = html as NSString
            let matches = posterRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
            for match in matches where match.numberOfRanges > 1 {
                let urlRange = match.range(at: 1)
                let imageUrl = nsHtml.substring(with: urlRange)
                appendUnique(imageUrl, bucket: &posters, label: "video poster")
            }
        }

        // Pattern 2: Snapchat CDN images (story.snapchat.com or cf-st.sc-cdn.net)
        let cdnPattern = #"(https?://(?:story\.snapchat\.com|cf-st\.sc-cdn\.net)/[^\s"\'<>]+\.(?:jpg|jpeg|png|webp))"#
        if let cdnRegex = try? NSRegularExpression(pattern: cdnPattern, options: [.caseInsensitive]) {
            let nsHtml = html as NSString
            let matches = cdnRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
            for match in matches where match.numberOfRanges > 0 {
                let urlRange = match.range(at: 1)
                let imageUrl = nsHtml.substring(with: urlRange)
                appendUnique(imageUrl, bucket: &cdns, label: "Snapchat CDN image")
            }
        }

        // Pattern 3: og:image meta tag (fallback last; often has play overlay)
        let ogImagePattern = #"<meta\s+(?:[^>]*?\s+)?property\s*=\s*["\']og:image["\']\s+(?:[^>]*?\s+)?content\s*=\s*["\']([^"\']+)["\']"#
        if let ogRegex = try? NSRegularExpression(pattern: ogImagePattern, options: [.caseInsensitive]) {
            let nsHtml = html as NSString
            let matches = ogRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
            for match in matches where match.numberOfRanges > 1 {
                let urlRange = match.range(at: 1)
                let imageUrl = nsHtml.substring(with: urlRange)
                appendUnique(imageUrl, bucket: &ogs, label: "og:image")
            }
        }

        return posters + cdns + ogs
    }

    // MARK: - Facebook Scraping

    private func downloadFacebookMedia(
        from urlString: String,
        completion: @escaping (Result<[SharedMediaFile], Error>) -> Void
    ) {
        shareLog("Attempting to fetch Facebook content...")

        let candidates = buildFacebookCandidates(from: urlString)
        let userAgents = [
            // Facebook scraper UA
            "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.html)",
            // Mobile Safari UA
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            // Desktop Chrome UA
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36"
        ]

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var foundImages: [String] = []

            attemptLoop: for candidateUrl in candidates {
                for ua in userAgents {
                    if let html = self.fetchHtml(urlString: candidateUrl, userAgent: ua) {
                        let images = self.extractImagesFromFacebookHtml(html, baseUrl: candidateUrl)
                        if !images.isEmpty {
                            shareLog("Found \(images.count) image(s) from Facebook via direct scrape (\(candidateUrl.prefix(60)))")
                            foundImages = images
                            break attemptLoop
                        }
                    }
                }
            }

            DispatchQueue.main.async {
                if !foundImages.isEmpty {
                    self.downloadFirstValidImage(
                        from: Array(foundImages.prefix(5)),
                        platform: "facebook",
                        session: URLSession.shared,
                        completion: completion
                    )
                } else {
                    shareLog("No images found via direct scrape for Facebook URL")
                    completion(.failure(self.makeDownloadError("facebook", "No images found in Facebook post")))
                }
            }
        }
    }

    private func buildFacebookCandidates(from urlString: String) -> [String] {
        var urls: [String] = [urlString]
        if let url = URL(string: urlString), let host = url.host?.lowercased(), host.contains("facebook.com") {
            func replaceHost(_ newHost: String) -> String? {
                var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                comps?.host = newHost
                return comps?.url?.absoluteString
            }
            if let mobile = replaceHost("m.facebook.com") {
                urls.append(mobile)
            }
            if let basic = replaceHost("mbasic.facebook.com") {
                urls.append(basic)
            }
            if let touch = replaceHost("touch.facebook.com") {
                urls.append(touch)
            }
        }
        return Array(NSOrderedSet(array: urls)) as? [String] ?? urls
    }

    private func fetchHtml(urlString: String, userAgent: String, timeout: TimeInterval = 15.0) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let semaphore = DispatchSemaphore(value: 0)
        var resultHtml: String?

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let data = data else {
                return
            }
            if let utf8 = String(data: data, encoding: .utf8) {
                resultHtml = utf8
            } else if let iso = String(data: data, encoding: .isoLatin1) {
                resultHtml = iso
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + timeout + 2.0)
        return resultHtml
    }

    private func extractImagesFromFacebookHtml(_ html: String, baseUrl: String) -> [String] {
        var results: [String] = []
        func clean(_ url: String) -> String {
            return url.replacingOccurrences(of: "&amp;", with: "&")
        }

        // Pattern 1: og:image meta tags (Facebook's Open Graph images)
        let ogImagePattern = #"<meta\s+(?:[^>]*?\s+)?property\s*=\s*["\']og:image(?::secure_url)?["\']\s+(?:[^>]*?\s+)?content\s*=\s*["\']([^"\']+)["\']"#
        if let ogRegex = try? NSRegularExpression(pattern: ogImagePattern, options: [.caseInsensitive]) {
            let nsHtml = html as NSString
            let matches = ogRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
            for match in matches {
                if match.numberOfRanges > 1 {
                    let urlRange = match.range(at: 1)
                    let imageUrl = clean(nsHtml.substring(with: urlRange))
                    if !imageUrl.isEmpty && !imageUrl.contains("facebook.com/images/") {
                        shareLog("Found Facebook og:image: \(imageUrl.prefix(80))")
                        results.append(imageUrl)
                    }
                }
            }
        }

        // Pattern 2: Facebook CDN images (scontent, fbcdn)
        let fbCdnPattern = #"(https?://(?:scontent[^/]*\.fbcdn\.net|external[^/]*\.fbcdn\.net)/[^\s"\'<>]+\.(?:jpg|jpeg|png|webp))"#
        if let cdnRegex = try? NSRegularExpression(pattern: fbCdnPattern, options: [.caseInsensitive]) {
            let nsHtml = html as NSString
            let matches = cdnRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
            for match in matches {
                if match.numberOfRanges > 0 {
                    let urlRange = match.range(at: 1)
                    let imageUrl = clean(nsHtml.substring(with: urlRange))
                    if !imageUrl.isEmpty {
                        shareLog("Found Facebook CDN image: \(imageUrl.prefix(80))")
                        results.append(imageUrl)
                    }
                }
            }
        }

        // Pattern 3: img src tags with Facebook CDN URLs
        let imgSrcPattern = #"<img\s+[^>]*?src\s*=\s*["\']([^"\']+fbcdn\.net[^"\']+)["\']"#
        if let imgRegex = try? NSRegularExpression(pattern: imgSrcPattern, options: [.caseInsensitive]) {
            let nsHtml = html as NSString
            let matches = imgRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
            for match in matches {
                if match.numberOfRanges > 1 {
                    let urlRange = match.range(at: 1)
                    let imageUrl = clean(nsHtml.substring(with: urlRange))
                    if !imageUrl.isEmpty {
                        shareLog("Found Facebook img src: \(imageUrl.prefix(80))")
                        results.append(imageUrl)
                    }
                }
            }
        }

        return results
    }

    // MARK: - Reddit Scraping

    private func downloadRedditMedia(
        from urlString: String,
        completion: @escaping (Result<[SharedMediaFile], Error>) -> Void
    ) {
        shareLog("Attempting to fetch Reddit content...")

        resolveRedditRedirect(urlString) { [weak self] resolvedUrl in
            guard let self = self else { return }
            let targetUrl = resolvedUrl ?? urlString
            if let resolved = resolvedUrl {
                shareLog("Reddit short link resolved to \(resolved.prefix(120))")
            }

            // Try direct scrape first
            self.quickGenericImageScrape(urlString: targetUrl) { [weak self] quickImages in
                guard let self = self else { return }

                if !quickImages.isEmpty {
                    shareLog("Found \(quickImages.count) image(s) from Reddit via direct scrape")
                    self.downloadFirstValidImage(
                        from: Array(quickImages.prefix(6)),
                        platform: "reddit",
                        session: URLSession.shared,
                        completion: completion
                    )
                    return
                }

                completion(.failure(self.makeDownloadError("reddit", "No images found in Reddit post")))
            }
        }
    }

    private func resolveRedditRedirect(_ urlString: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8.0
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        URLSession.shared.dataTask(with: request) { _, response, _ in
            let finalUrl = response?.url?.absoluteString
            if finalUrl == urlString {
                completion(nil)
            } else {
                completion(finalUrl)
            }
        }.resume()
    }

    // MARK: - IMDb Scraping

    private func downloadImdbMedia(
        from urlString: String,
        completion: @escaping (Result<[SharedMediaFile], Error>) -> Void
    ) {
        shareLog("Attempting to fetch IMDb content...")

        // Try lightweight scrape first (og/twitter/img)
        quickGenericImageScrape(urlString: urlString) { [weak self] quickImages in
            guard let self = self else { return }

            if !quickImages.isEmpty {
                shareLog("Found \(quickImages.count) image(s) from IMDb via direct scrape")
                self.downloadFirstValidImage(
                    from: Array(quickImages.prefix(5)),
                    platform: "imdb",
                    session: URLSession.shared,
                    completion: completion
                )
                return
            }

            completion(.failure(self.makeDownloadError("IMDb", "No images found in IMDb content")))
        }
    }

    private func extractImagesFromRedditHtml(_ html: String, baseUrl: String) -> [String] {
        var results: [String] = []
        let nsHtml = html as NSString

        func appendIfValid(_ candidate: String) {
            let lowered = candidate.lowercased()
            if lowered.contains("communityicon") || lowered.contains("styles.redditmedia.com") {
                return
            }
            let cleaned = candidate.replacingOccurrences(of: "&amp;", with: "&")
            let upgraded = preferOriginalRedditVariant(cleaned)
            guard isAllowedRedditImageUrl(upgraded) else { return }
            if !results.contains(upgraded) {
                shareLog("Found Reddit image: \(upgraded.prefix(80))")
                results.append(upgraded)
            }
        }

        // Pattern 1: og:image
        let ogImagePattern = #"<meta\s+(?:[^>]*?\s+)?property\s*=\s*["\']og:image["\']\s+(?:[^>]*?\s+)?content\s*=\s*["\']([^"\']+)["\']"#
        if let ogRegex = try? NSRegularExpression(pattern: ogImagePattern, options: [.caseInsensitive]) {
            let matches = ogRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
            for match in matches where match.numberOfRanges > 1 {
                let urlRange = match.range(at: 1)
                let imageUrl = nsHtml.substring(with: urlRange)
                appendIfValid(imageUrl)
            }
        }

        // Pattern 2: preview.redd.it CDN
        let previewPattern = #"(https?://preview\.redd\.it/[^\s"\'<>]+)"#
        if let previewRegex = try? NSRegularExpression(pattern: previewPattern, options: [.caseInsensitive]) {
            let matches = previewRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
            for match in matches where match.numberOfRanges > 0 {
                let urlRange = match.range(at: 1)
                let imageUrl = nsHtml.substring(with: urlRange)
                appendIfValid(imageUrl)
            }
        }

        // Pattern 3: i.redd.it direct images
        let ireddPattern = #"(https?://i\.redd\.it/[^\s"\'<>]+)"#
        if let ireddRegex = try? NSRegularExpression(pattern: ireddPattern, options: [.caseInsensitive]) {
            let matches = ireddRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
            for match in matches where match.numberOfRanges > 0 {
                let urlRange = match.range(at: 1)
                let imageUrl = nsHtml.substring(with: urlRange)
                appendIfValid(imageUrl)
            }
        }

        // Pattern 4: img src pointing to redd.it hosts
        let imgPattern = #"<img\s+[^>]*?src\s*=\s*["\']([^"\']+redd\.it[^"\']+)["\']"#
        if let imgRegex = try? NSRegularExpression(pattern: imgPattern, options: [.caseInsensitive]) {
            let matches = imgRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
            for match in matches where match.numberOfRanges > 1 {
                let urlRange = match.range(at: 1)
                let imageUrl = nsHtml.substring(with: urlRange)
                appendIfValid(imageUrl)
            }
        }

        // Pattern 5: styles.redditmedia.com URLs that may embed preview images
        let stylesPattern = #"(https?://styles\.redditmedia\.com/[^\s"\'<>]+)"#
        if let stylesRegex = try? NSRegularExpression(pattern: stylesPattern, options: [.caseInsensitive]) {
            let matches = stylesRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
            for match in matches where match.numberOfRanges > 0 {
                let urlRange = match.range(at: 1)
                let imageUrl = nsHtml.substring(with: urlRange)
                appendIfValid(imageUrl)
            }
        }

        return results
    }

    private func isAllowedRedditImageUrl(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else { return false }

        let lowerPath = url.path.lowercased()
        // Skip obvious UI assets
        if lowerPath.contains("communityicon") || lowerPath.contains("awards") {
            return false
        }

        return host.contains("preview.redd.it") ||
               host.contains("i.redd.it") ||
               host.contains("redd.it") ||
               host.contains("redditmedia.com") ||
               host.contains("imgur.com")
    }

    private func preferOriginalRedditVariant(_ url: String) -> String {
        guard var components = URLComponents(string: url) else { return url }

        // Normalize query params for higher quality
        var queryItems = components.queryItems ?? []
        var didMutate = false

        for index in queryItems.indices.reversed() {
            switch queryItems[index].name {
            case "width":
                queryItems[index].value = "2048"
                didMutate = true
            case "format":
                queryItems[index].value = "jpg"
                didMutate = true
            case "auto":
                queryItems[index].value = "webp"
                didMutate = true
            case "crop":
                queryItems.remove(at: index)
                didMutate = true
            default:
                break
            }
        }

        if didMutate {
            components.queryItems = queryItems
        }

        return components.url?.absoluteString ?? url
    }

    // MARK: - X (Twitter) Scraping

    private func downloadXMedia(
        from urlString: String,
        completion: @escaping (Result<[SharedMediaFile], Error>) -> Void
    ) {
        shareLog("Attempting to fetch X content via Jina...")

        fetchXViaJina(urlString: urlString) { [weak self] imageUrls in
            guard let self = self else { return }

            if imageUrls.isEmpty {
                completion(.failure(self.makeDownloadError("x", "No images found in X post")))
                return
            }

            shareLog("Found \(imageUrls.count) image(s) from X via Jina")

            self.downloadFirstValidImage(
                from: Array(imageUrls.prefix(6)),
                platform: "x",
                session: URLSession.shared,
                completion: completion
            )
        }
    }

    private func fetchXViaJina(
        urlString: String,
        completion: @escaping ([String]) -> Void
    ) {
        let rfc3986 = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=")
        guard let encodedTarget = urlString.addingPercentEncoding(withAllowedCharacters: rfc3986) else {
            completion([])
            return
        }
        let proxyString = "https://r.jina.ai/\(encodedTarget)"
        guard let proxyUrl = URL(string: proxyString) else {
            completion([])
            return
        }

        var request = URLRequest(url: proxyUrl)
        request.timeoutInterval = 15.0
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            guard error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let data = data,
                  let html = String(data: data, encoding: .utf8) else {
                completion([])
                return
            }

            let imageUrls = self.extractImagesFromXHtml(html, baseUrl: urlString)
            completion(imageUrls)
        }

        task.resume()
    }

    private func extractImagesFromXHtml(_ html: String, baseUrl: String) -> [String] {
        var results: [String] = []

        func appendIfAllowed(_ candidate: String) {
            guard !candidate.isEmpty else { return }
            let cleaned = candidate.replacingOccurrences(of: "&amp;", with: "&")
            let upgraded = preferOriginalXVariant(cleaned)
            guard isAllowedXImageUrl(upgraded) else { return }
            if !results.contains(upgraded) {
                shareLog("Found X media URL: \(upgraded.prefix(80))")
                results.append(upgraded)
            }
        }

        // Pattern 1: og:image meta tag
        let ogImagePattern = #"<meta\s+(?:[^>]*?\s+)?property\s*=\s*["\']og:image["\']\s+(?:[^>]*?\s+)?content\s*=\s*["\']([^"\']+)["\']"#
        if let ogRegex = try? NSRegularExpression(pattern: ogImagePattern, options: [.caseInsensitive]) {
            let nsHtml = html as NSString
            let matches = ogRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
            for match in matches {
                if match.numberOfRanges > 1 {
                    let urlRange = match.range(at: 1)
                    let imageUrl = nsHtml.substring(with: urlRange)
                    appendIfAllowed(imageUrl)
                }
            }
        }

        // Pattern 2: twitter:image meta tag
        let twitterImagePattern = #"<meta\s+(?:[^>]*?\s+)?name\s*=\s*["\']twitter:image["\']\s+(?:[^>]*?\s+)?content\s*=\s*["\']([^"\']+)["\']"#
        if let twitterRegex = try? NSRegularExpression(pattern: twitterImagePattern, options: [.caseInsensitive]) {
            let nsHtml = html as NSString
            let matches = twitterRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
            for match in matches {
                if match.numberOfRanges > 1 {
                    let urlRange = match.range(at: 1)
                    let imageUrl = nsHtml.substring(with: urlRange)
                    appendIfAllowed(imageUrl)
                }
            }
        }

        // Pattern 3: Direct twimg CDN URLs (images or video thumbnails)
        let twimgPattern = #"(https?://(?:pbs\.twimg\.com|video\.twimg\.com)/[^\s"\'<>]+)"#
        if let cdnRegex = try? NSRegularExpression(pattern: twimgPattern, options: [.caseInsensitive]) {
            let nsHtml = html as NSString
            let matches = cdnRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
            for match in matches {
                if match.numberOfRanges > 1 {
                    let urlRange = match.range(at: 1)
                    let imageUrl = nsHtml.substring(with: urlRange)
                    appendIfAllowed(imageUrl)
                }
            }
        }

        // Pattern 4: img src attributes pointing to twimg hosts
        let imgSrcPattern = #"<img\s+[^>]*?src\s*=\s*["\']([^"\']+twimg\.com[^"\']+)["\']"#
        if let imgRegex = try? NSRegularExpression(pattern: imgSrcPattern, options: [.caseInsensitive]) {
            let nsHtml = html as NSString
            let matches = imgRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))
            for match in matches {
                if match.numberOfRanges > 1 {
                    let urlRange = match.range(at: 1)
                    let imageUrl = nsHtml.substring(with: urlRange)
                    appendIfAllowed(imageUrl)
                }
            }
        }

        return results
    }

    private func isAllowedXImageUrl(_ urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return false }
        return host.contains("pbs.twimg.com") || host.contains("video.twimg.com")
    }

    private func preferOriginalXVariant(_ url: String) -> String {
        guard let components = URLComponents(string: url) else { return url }

        var updatedComponents = components

        // Only adjust image CDN URLs; leave others untouched
        if let host = components.host?.lowercased(), host.contains("pbs.twimg.com") {
            var queryItems = components.queryItems ?? []
            var hasName = false

            // Replace any existing name parameter with orig
            for idx in queryItems.indices {
                if queryItems[idx].name == "name" {
                    queryItems[idx].value = "orig"
                    hasName = true
                }
            }

            // If no name parameter, append the highest-quality variant
            if !hasName {
                queryItems.append(URLQueryItem(name: "name", value: "orig"))
            }

            updatedComponents.queryItems = queryItems
        }

        return updatedComponents.url?.absoluteString ?? url
    }

    // MARK: - Google Image Download

    private func downloadGoogleImageMedia(
        from urlString: String,
        completion: @escaping (Result<[SharedMediaFile], Error>) -> Void
    ) {
        guard let imageUrl = extractGoogleImageUrl(from: urlString) else {
            shareLog("Could not extract imgurl from Google link")
            completion(.failure(makeDownloadError("GoogleImage", "Could not parse image URL")))
            return
        }

        let cleanedUrl = imageUrl.hasPrefix("http") ? imageUrl : "https://\(imageUrl)"
        shareLog("Downloading Google Image directly: \(cleanedUrl.prefix(80))...")

        downloadFirstValidImage(from: [cleanedUrl], platform: "google_image", session: URLSession.shared, completion: completion)
    }

    private func extractGoogleImageUrl(from urlString: String) -> String? {
        let lowercased = urlString.lowercased()
        guard let index = lowercased.range(of: "imgurl=") else { return nil }

        let startIndex = urlString.index(index.upperBound, offsetBy: 0, limitedBy: urlString.endIndex) ?? urlString.endIndex
        let raw = String(urlString[startIndex...])

        let endIndex = raw.firstIndex(of: "&") ?? raw.endIndex
        let candidate = String(raw[..<endIndex])

        // URL decode
        return candidate.removingPercentEncoding ?? candidate
    }

    // MARK: - Generic Link Scraping

    private func downloadGenericLinkMedia(
        from urlString: String,
        completion: @escaping (Result<[SharedMediaFile], Error>) -> Void
    ) {
        // Free path: quick HTML fetch to grab og/twitter/img
        quickGenericImageScrape(urlString: urlString) { [weak self] quickImages in
            guard let self = self else { return }

            if !quickImages.isEmpty {
                self.downloadFirstValidImage(
                    from: Array(quickImages.prefix(5)),
                    platform: "generic",
                    session: URLSession.shared,
                    completion: completion
                )
                return
            }

            // No images found in quick scrape; return failure without ScrapingBee
            completion(.failure(self.makeDownloadError("GenericLink", "No images found on page")))
        }
    }

    private func quickGenericImageScrape(
        urlString: String,
        completion: @escaping ([String]) -> Void
    ) {
        // Google imgres: extract imgurl directly (creditless)
        if let imgUrl = extractGoogleImgUrl(from: urlString) {
            completion([imgUrl])
            return
        }

        // Direct image URL: return immediately
        if looksLikeImageUrl(urlString) {
            completion([urlString])
            return
        }

        guard let url = URL(string: urlString) else {
            completion([])
            return
        }

        // Google Images thumbnail/shared URLs (encrypted-tbn* or imgres without imgurl)
        if let host = url.host?.lowercased(), host.contains("gstatic.com"), host.contains("tbn") {
            resolveGoogleThumbToOriginal(thumbUrl: urlString) { resolved in
                if let resolved = resolved {
                    completion([resolved])
                } else if let preferred = self.extractPreferredImageParam(from: urlString) {
                    completion([preferred])
                } else {
                    completion([urlString])
                }
            }
            return // resolution handled asynchronously
        }
        if let host = url.host?.lowercased(),
           host.contains("google."),
           (url.path.lowercased().contains("/imgres") || url.query?.contains("tbn:") == true) {
            resolveGoogleThumbToOriginal(thumbUrl: urlString) { resolved in
                if let resolved = resolved {
                    completion([resolved])
                } else if let preferred = self.extractPreferredImageParam(from: urlString) {
                    completion([preferred])
                } else {
                    completion([urlString])
                }
            }
            return // resolution handled asynchronously
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8.0
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            guard error == nil,
                  let httpResponse = response as? HTTPURLResponse else {
                completion([])
                return
            }

            let statusCode = httpResponse.statusCode
            guard (200...299).contains(statusCode),
                  let data = data else {
                shareLog("Generic link fetch failed (status \(statusCode)) for \(url.absoluteString.prefix(120))")
                completion([])
                return
            }

            // If the response itself is an image (Squarespace CDN, etc.), skip HTML parsing
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            if contentType.contains("image/") {
                shareLog("Generic link returned image content-type (\(contentType)) - treating as direct image")
                completion([url.absoluteString])
                return
            }

            // Some CDNs serve raw bytes without a helpful content-type; sniff the payload
            if contentType.isEmpty || contentType.contains("octet-stream") {
                if UIImage(data: data) != nil {
                    shareLog("Generic link response looked like raw image data - treating as direct image")
                    completion([url.absoluteString])
                    return
                }
            }

            guard let html = String(data: data, encoding: .utf8) else {
                completion([])
                return
            }

            let images = self.extractGenericImageUrls(from: html, baseUrl: url)
            if let best = images.first {
                completion([best])
            } else {
                completion([])
            }
        }.resume()
    }

    private func extractGenericImageUrls(from html: String, baseUrl: URL) -> [String] {
        var results: [String] = []

        func resolve(_ raw: String?) -> String? {
            guard let raw = raw, !raw.isEmpty, !raw.hasPrefix("data:") else { return nil }
            let lower = raw.lowercased()
            if lower.contains("favicon") ||
                lower.contains("googlelogo") ||
                lower.contains("gstatic.com/favicon") ||
                lower.contains("tbn:") ||
                lower.contains("tbn0.gstatic.com") {
                return nil
            }
            return baseUrl.resolve(raw)
        }

        let patterns = [
            "<meta[^>]+property=\"og:image\"[^>]+content=\"([^\"]+)\"",
            "<meta[^>]+name=\"twitter:image\"[^>]+content=\"([^\"]+)\"",
        ]

        for pat in patterns {
            if let regex = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) {
                let nsrange = NSRange(html.startIndex..<html.endIndex, in: html)
                if let match = regex.firstMatch(in: html, options: [], range: nsrange),
                   match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: html),
                   let resolved = resolve(String(html[range])),
                   !results.contains(resolved) {
                    results.append(resolved)
                }
            }
        }

        let imgPattern = "<img[^>]+src=\"([^\"]+)\""
        if let regex = try? NSRegularExpression(pattern: imgPattern, options: [.caseInsensitive]) {
            let nsrange = NSRange(html.startIndex..<html.endIndex, in: html)
            var count = 0
            regex.enumerateMatches(in: html, options: [], range: nsrange) { match, _, stop in
                guard count < 5,
                      let match = match,
                      match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: html),
                      let resolved = resolve(String(html[range])),
                      !results.contains(resolved) else { return }
                results.append(resolved)
                count += 1
                if count >= 5 { stop.pointee = true }
            }
        }

        return results
    }

    private func looksLikeImageUrl(_ urlString: String) -> Bool {
        let lower = urlString.lowercased()

        if let components = URLComponents(string: urlString),
           let host = components.host?.lowercased() {
            // Squarespace CDN often serves images without an extension
            if host.contains("squarespace-cdn.com"),
               components.path.contains("/content/") {
                return true
            }
            // Inspogroup CDN transforms images with extensionless paths
            if host.contains("inspogroup.net") || host.contains("cdn.inspogroup.net") {
                return true
            }
        }

        return lower.hasSuffix(".jpg") ||
            lower.hasSuffix(".jpeg") ||
            lower.hasSuffix(".png") ||
            lower.hasSuffix(".webp") ||
            lower.contains(".jpg?") ||
            lower.contains(".jpeg?") ||
            lower.contains(".png?") ||
            lower.contains(".webp?") ||
            lower.contains("tbn:") // Google Images thumbnails
    }

    private func extractGoogleImgUrl(from urlString: String) -> String? {
        let lower = urlString.lowercased()
        guard lower.contains("google.") && lower.contains("imgurl=") else { return nil }

        return extractPreferredImageParam(from: urlString, keys: ["imgurl"])
    }

    private func extractPreferredImageParam(from urlString: String, keys: [String] = ["imgurl", "mediaurl", "url", "image_url"]) -> String? {
        guard let components = URLComponents(string: urlString),
              let items = components.queryItems else { return nil }
        for key in keys {
            if let value = items.first(where: { $0.name.lowercased() == key.lowercased() })?.value,
               !value.isEmpty {
                return value.removingPercentEncoding ?? value
            }
        }
        return nil
    }

    private func resolveGoogleThumbToOriginal(thumbUrl: String, completion: @escaping (String?) -> Void) {
        // Build a Google "search by image" URL to get the best available image URL
        guard let encodedThumb = thumbUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchUrl = URL(string: "https://www.google.com/searchbyimage?image_url=\(encodedThumb)&encoded_url=1&hl=en") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: searchUrl)
        request.timeoutInterval = 6.0
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { completion(nil); return }
            guard error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let data = data,
                  let html = String(data: data, encoding: .utf8) else {
                completion(nil)
                return
            }

            // Try to extract imgurl= from any link
            if let preferred = self.extractPreferredImageParam(from: html, keys: ["imgurl"]) {
                completion(preferred)
                return
            }

            // Fallback: look for data:image-url or "imgurl=" inline
            if let match = self.extractFirstMatch(in: html, pattern: "imgurl=([^&\"'>]+)") {
                completion(match.removingPercentEncoding ?? match)
                return
            }
            if let match = self.extractFirstMatch(in: html, pattern: "data:image-url=\"([^\"]+)\"") {
                completion(match.removingPercentEncoding ?? match)
                return
            }

            completion(nil)
        }.resume()
    }

    private func extractFirstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = regex.firstMatch(in: text, options: [], range: nsrange),
           match.numberOfRanges > 1,
           let range = Range(match.range(at: 1), in: text) {
            return String(text[range])
        }
        return nil
    }

    // MARK: - Common Download Helper

    private func downloadFirstValidImage(
        from urls: [String],
        platform: String,
        session: URLSession,
        cropToAspect: CGFloat? = nil,
        completion: @escaping (Result<[SharedMediaFile], Error>) -> Void
    ) {
        guard !urls.isEmpty else {
            DispatchQueue.main.async {
                completion(.failure(self.makeDownloadError(platform, "No image URLs to try")))
            }
            return
        }

        var urlsToTry = urls
        let rawUrl = urlsToTry.removeFirst()
        let firstUrl = rawUrl.replacingOccurrences(of: "&amp;", with: "&")

        guard let url = URL(string: firstUrl) else {
            // Try next URL
            downloadFirstValidImage(from: urlsToTry, platform: platform, session: session, cropToAspect: cropToAspect, completion: completion)
            return
        }

        shareLog("Trying to download \(platform) image: \(firstUrl.prefix(80))...")

        var request = URLRequest(url: url)
        // Some CDNs (fbcdn) can be picky without a UA / language / referer
        if platform == "facebook" {
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            request.setValue("https://www.facebook.com/", forHTTPHeaderField: "Referer")
            request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        } else if platform == "tiktok" {
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("https://www.tiktok.com/", forHTTPHeaderField: "Referer")
            request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        } else if platform == "generic" {
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        }

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            // Check if download succeeded
            if let error = error {
                shareLog("Failed to download from \(firstUrl.prefix(50))...: \(error.localizedDescription)")
                // Try next URL
                self.downloadFirstValidImage(from: urlsToTry, platform: platform, session: session, cropToAspect: cropToAspect, completion: completion)
                return
            }

            guard let data = data, !data.isEmpty,
                  let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                shareLog("Failed to download \(platform) image (status \(status)) from \(firstUrl.prefix(80))")

                // If Facebook blocks, try a dl=1 variant once
                if platform == "facebook",
                   !firstUrl.contains("dl=1"),
                   var comps = URLComponents(string: firstUrl) {
                    var queryItems = comps.queryItems ?? []
                    queryItems.append(URLQueryItem(name: "dl", value: "1"))
                    comps.queryItems = queryItems
                    if let dlUrl = comps.url?.absoluteString {
                        var next = urlsToTry
                        next.insert(dlUrl, at: 0)
                        self.downloadFirstValidImage(from: next, platform: platform, session: session, cropToAspect: cropToAspect, completion: completion)
                        return
                    }
                }
                // Try next URL
                self.downloadFirstValidImage(from: urlsToTry, platform: platform, session: session, cropToAspect: cropToAspect, completion: completion)
                return
            }

            var dataToSave = data
            if let targetAspect = cropToAspect,
               let image = UIImage(data: data),
               image.size.width > 0,
               image.size.height > 0 {
                let currentAspect = image.size.width / image.size.height
                if abs(currentAspect - targetAspect) > 0.01 {
                    var cropRect = CGRect(origin: .zero, size: image.size)
                    if currentAspect > targetAspect {
                        let targetWidth = image.size.height * targetAspect
                        let originX = max(0, (image.size.width - targetWidth) / 2)
                        cropRect = CGRect(x: originX, y: 0, width: targetWidth, height: image.size.height)
                    } else {
                        let targetHeight = image.size.width / targetAspect
                        let originY = max(0, (image.size.height - targetHeight) / 2)
                        cropRect = CGRect(x: 0, y: originY, width: image.size.width, height: targetHeight)
                    }

                    if let cgImage = image.cgImage?.cropping(to: cropRect.integral) {
                        let cropped = UIImage(cgImage: cgImage)
                        if let croppedData = cropped.jpegData(compressionQuality: 0.95) {
                            dataToSave = croppedData
                            shareLog("Cropped \(platform) image to aspect \(String(format: "%.2f", targetAspect)) -> \(Int(cropRect.width))x\(Int(cropRect.height))")
                        }
                    }
                }
            }

            // Save to shared container
            guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: self.appGroupId) else {
                DispatchQueue.main.async {
                    completion(.failure(self.makeDownloadError(platform, "Cannot access shared container")))
                }
                return
            }

            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let fileName = "\(platform)_image_\(timestamp).jpg"
            let fileURL = containerURL.appendingPathComponent(fileName)

            do {
                try dataToSave.write(to: fileURL, options: .atomic)
                shareLog("Saved \(platform) image to \(fileName) (\(dataToSave.count) bytes)")

                let sharedFile = SharedMediaFile(
                    path: fileURL.absoluteString,
                    thumbnail: nil,
                    duration: nil,
                    type: .image
                )

                DispatchQueue.main.async {
                    completion(.success([sharedFile]))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(self.makeDownloadError(platform, "Failed to save image: \(error.localizedDescription)")))
                }
            }
        }
        task.resume()
    }

    private func makeDownloadError(_ platform: String, _ message: String, code: Int = -1) -> NSError {
        return NSError(
            domain: "\(platform)Scraper",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    // MARK: - Platform Helper Functions

    private func getDownloadFunction(for platformType: String?) -> (String, @escaping (Result<[SharedMediaFile], Error>) -> Void) -> Void {
        switch platformType {
        case "instagram":
            return downloadInstagramMedia
        case "tiktok":
            return downloadTikTokMedia
        case "pinterest":
            return downloadPinterestMedia
        case "youtube":
            return downloadYouTubeMedia
        case "snapchat":
            return downloadSnapchatMedia
        case "x":
            return downloadXMedia
        case "reddit":
            return downloadRedditMedia
        case "imdb":
            return downloadImdbMedia
        case "facebook":
            return downloadFacebookMedia
        case "google_image":
            return downloadGoogleImageMedia
        case "generic":
            return downloadGenericLinkMedia
        default:
            // Fallback to generic
            return downloadGenericLinkMedia
        }
    }

    private func getPlatformDisplayName(_ platformType: String?) -> String {
        switch platformType {
        case "instagram":
            return "Instagram"
        case "tiktok":
            return "TikTok"
        case "pinterest":
            return "Pinterest"
        case "youtube":
            return "YouTube"
        case "snapchat":
            return "Snapchat"
        case "x":
            return "X"
        case "reddit":
            return "Reddit"
        case "imdb":
            return "IMDb"
        case "facebook":
            return "Facebook"
        case "google_image":
            return "Google Image"
        case "generic":
            return "Generic Link"
        default:
            return "Unknown"
        }
    }

    // Get detector endpoint from UserDefaults or fallback
    private func detectorEndpoint() -> String? {
        if let defaults = UserDefaults(suiteName: appGroupId),
           let endpoint = defaults.string(forKey: kDetectorEndpoint),
           !endpoint.isEmpty {
            return endpoint
        }
        // Fallback to local/ngrok for development (will be set by Flutter app)
        shareLog("Warning: DetectorEndpoint not found in UserDefaults - run Flutter app first")
        return nil
    }

    // Get SerpAPI key from UserDefaults
    private func serpApiKey() -> String? {
        if let defaults = UserDefaults(suiteName: appGroupId),
           let key = defaults.string(forKey: kSerpApiKey),
           !key.isEmpty {
            return key
        }
        return nil
    }


    private func runDetectionAnalysis(imageUrl: String?, imageBase64: String) {
        let urlForLog = imageUrl ?? "<nil>"
        shareLog("START runDetectionAnalysis - imageUrl: \(urlForLog), base64 length: \(imageBase64.count)")
        shareLog("DEBUG: pendingInstagramUrl = \(pendingInstagramUrl ?? "<NIL>")")
        shareLog("DEBUG: pendingPlatformType = \(pendingPlatformType ?? "<NIL>")")

        guard let serverBaseUrl = getServerBaseUrl() else {
            shareLog("ERROR: Could not determine server base URL")
            handleDetectionFailure(reason: "Detection setup is incomplete. Please open Worthify to finish configuring analysis.")
            return
        }

        // Use new caching endpoint
        let analyzeEndpoint = serverBaseUrl + "/api/v1/analyze"
        shareLog("Detection endpoint: \(analyzeEndpoint)")
        targetProgress = max(targetProgress, detectTargetCap)

        // Ensure status rotation is running (in case we came from a path that didn't start it)
        if currentStatusMessages.isEmpty {
            let searchMessages = [
                "Analyzing look...",
                "Finding similar items...",
                "Checking retailers...",
                "Finalizing results..."
            ]
            startStatusRotation(messages: searchMessages, interval: 2.0, stopAtLast: true)
        }

        // Determine search type based on source
        var searchType = "unknown"
        var sourceUrl: String? = nil
        var sourceUsername: String? = nil

        if let pendingUrl = pendingInstagramUrl {
            sourceUrl = pendingUrl
            shareLog("DEBUG: Using pendingInstagramUrl as sourceUrl: \(pendingUrl)")
            let lowercased = pendingUrl.lowercased()

            // Detect platform from URL
            if lowercased.contains("instagram.com") {
                searchType = "instagram"
                sourceUsername = extractInstagramUsername(from: pendingUrl)
            } else if lowercased.contains("tiktok.com") {
                searchType = "tiktok"
            } else if lowercased.contains("pinterest.com") || lowercased.contains("pin.it") {
                searchType = "pinterest"
            } else if lowercased.contains("twitter.com") || lowercased.contains("x.com") {
                searchType = "twitter"
            } else if lowercased.contains("facebook.com") || lowercased.contains("fb.com") {
                searchType = "facebook"
            } else {
                // Generic web source
                searchType = "web"
            }
        } else if imageUrl != nil {
            searchType = "photos"
        } else {
            searchType = "camera"
        }

        let resolvedUserId = getUserId()
        if resolvedUserId == "anonymous" {
            shareLog("ERROR: Cannot run detection without a valid authenticated user ID")
            handleDetectionFailure(reason: "We couldn't sync your account for this share. Open Worthify once, then try sharing again.")
            return
        }

        var requestBody: [String: Any] = [
            "user_id": resolvedUserId,
            "image_base64": imageBase64,
            "search_type": searchType
        ]

        // Add device locale for localized search results
        let deviceLocale = getDeviceLocale()
        requestBody["country"] = deviceLocale.country
        requestBody["language"] = deviceLocale.language

        if let imageUrl = imageUrl, !imageUrl.isEmpty {
            requestBody["image_url"] = imageUrl
        }

        if let sourceUrl = sourceUrl {
            requestBody["source_url"] = sourceUrl
            shareLog("DEBUG: Adding source_url to request: \(sourceUrl)")
        } else {
            shareLog("DEBUG: NO source_url - will not benefit from cache")
        }

        if let sourceUsername = sourceUsername {
            requestBody["source_username"] = sourceUsername
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            shareLog("ERROR: Failed to serialize detection request JSON")
            handleDetectionFailure(reason: "Could not prepare the analysis request. Please try sharing again.")
            return
        }

        shareLog("Request body size: \(jsonData.count) bytes")

        guard let url = URL(string: analyzeEndpoint) else {
            shareLog("ERROR: Invalid detection endpoint URL: \(analyzeEndpoint)")
            handleDetectionFailure(reason: "The detection service URL looks invalid. Check your configuration in Worthify.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 120.0  // Match server timeout of 120s

        shareLog("Sending detection API request to: \(analyzeEndpoint)")
        shareLog("Request timeout set to: 120.0 seconds")

        // Cancel any existing detection task
        if let existingTask = detectionTask {
            shareLog("Cancelling existing detection task")
            existingTask.cancel()
        }

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                shareLog("Share extension deallocated during API call")
                return
            }

            // Log memory usage after response received
            let memoryMB = Double(self.getMemoryUsage()) / 1_048_576.0
            shareLog("Memory usage after API response: \(String(format: "%.1f", memoryMB)) MB")

            if let error = error {
                shareLog("ERROR: Detection API network error: \(error.localizedDescription)")
                self.detectionTask = nil // Clear task reference
                self.handleDetectionFailure(reason: "We couldn't reach the detection service (\(error.localizedDescription)).")
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            shareLog("Detection API response - status code: \(statusCode)")

            guard let data = data else {
                shareLog("ERROR: Detection API response has no data")
                self.handleDetectionFailure(reason: "The detection service responded without data. Please try again.")
                return
            }

            shareLog("Detection API response data size: \(data.count) bytes")

            // Log response preview for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                let preview = responseString.prefix(500)
                shareLog("Detection API response preview: \(preview)")
            }

            guard statusCode == 200 else {
                shareLog("ERROR: Detection API returned non-200 status: \(statusCode)")
                self.handleDetectionFailure(reason: "Detection service returned status \(statusCode).")
                return
            }

            do {
                let decoder = JSONDecoder()
                let detectionResponse = try decoder.decode(DetectionResponse.self, from: data)

                shareLog("Detection response parsed - success: \(detectionResponse.success)")

                if detectionResponse.success {
                    shareLog("SUCCESS: Detection found \(detectionResponse.total_results) results")

                    // Clear task reference on success
                    self.detectionTask = nil

                    // Store search_id and image_cache_id for favorites/save functionality
                    self.currentSearchId = detectionResponse.search_id
                    self.currentImageCacheId = detectionResponse.image_cache_id
                    if let searchId = detectionResponse.search_id {
                        shareLog("Stored search_id: \(searchId)")
                    } else {
                        shareLog("WARNING: Detection succeeded but search_id is nil (history entry may not have been created)")
                    }
                    let wasCacheHit = detectionResponse.cached ?? false
                    if wasCacheHit {
                        shareLog("Cache status: HIT")
                    } else {
                        shareLog("Cache status: MISS")
                    }

                    // Deduct credits based on garment count (skip for cache hits)
                    if !wasCacheHit {
                        if let garmentCount = detectionResponse.garments_searched, garmentCount > 0 {
                            self.deductCredits(garmentCount: garmentCount)
                        }
                    } else {
                        shareLog("[Credits] Cache hit - no credits deducted")
                    }

                    // Set target to 100% and wait for progress bar to reach it
                    DispatchQueue.main.async {
                        self.targetProgress = 1.0
                        self.updateProgress(1.0, status: "Analysis complete")

                        // Wait for progress bar to actually reach 100% before showing results
                        self.waitForProgressCompletion {
                            self.stopSmoothProgress()
                            let serverResults = detectionResponse.results
                            let sanitized = self.sanitize(results: serverResults)
                            if sanitized.count != serverResults.count {
                                shareLog("Sanitized \(serverResults.count - sanitized.count) banned keyword results")
                            }
                            self.detectionResults = sanitized
                            self.isShowingDetectionResults = true
                            self.maybeShowPostAnalysisOutOfCreditsModal()

                            // Haptic feedback for successful analysis
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()

                            shareLog("Calling showDetectionResults with \(self.detectionResults.count) items")
                            for (index, item) in self.detectionResults.prefix(10).enumerated() {
                                let categories = item.normalizedCategories.map { $0.displayName }.joined(separator: ", ")
                                shareLog("Category normalization [\(index)]: \(categories) => \(item.categoryGroup.displayName) (confidence: \(item.normalizedCategoryConfidence)) for \(item.product_name)")
                            }
                            self.showDetectionResults()
                        }
                    }
                } else {
                    shareLog("ERROR: Detection failed - \(detectionResponse.message ?? "Unknown error")")
                    self.detectionTask = nil // Clear task reference
                    let message = detectionResponse.message ?? "We couldn't find any products to show."
                    self.handleDetectionFailure(reason: message)
                }
            } catch {
                shareLog("ERROR: Failed to parse detection response: \(error.localizedDescription)")
                self.detectionTask = nil // Clear task reference
                self.handleDetectionFailure(reason: "We couldn't read the detection results (\(error.localizedDescription)).")
            }
        }

        // Store task for cancellation if needed
        detectionTask = task
        task.resume()
        shareLog("Detection API task started and stored for potential cancellation")
    }

    private func handleDetectionFailure(reason: String) {
        shareLog("Detection failure: \(reason)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.hasQueuedRedirect { return }
            if self.hasPresentedDetectionFailureAlert { return }
            self.hasPresentedDetectionFailureAlert = true
            self.shouldAttemptDetection = false
            self.isShowingDetectionResults = false
            self.stopStatusRotation()
            self.stopSmoothProgress()
            self.activityIndicator?.stopAnimating()
            self.statusLabel?.isHidden = false
            self.statusLabel?.text = reason

            let alert = UIAlertController(
                title: "Analysis Unavailable",
                message: reason,
                preferredStyle: .alert
            )

            alert.addAction(UIAlertAction(
                title: "Open Worthify",
                style: .default
            ) { _ in
                self.proceedWithNormalFlow()
            })

            alert.addAction(UIAlertAction(
                title: "Cancel Share",
                style: .cancel
            ) { _ in
                self.closeExtension()
            })

            if self.presentedViewController == nil {
                self.present(alert, animated: true)
            }
        }
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applySheetCornerRadius(38)

        if let cardView = imageComparisonContainerView,
           let widthConstraint = imageComparisonWidthConstraint,
           let tapArea = cardView.superview {
            let availableWidth = tapArea.bounds.width - 32
            if availableWidth > 0 {
                widthConstraint.constant = min(408, availableWidth)
            }
        }

        updateResultsHeaderLayout()
    }

    private func updateResultsHeaderLayout() {
        guard !isUpdatingResultsHeaderLayout else { return }
        isUpdatingResultsHeaderLayout = true
        defer { isUpdatingResultsHeaderLayout = false }

        guard let tableView = resultsTableView,
              resultsHeaderContainerView != nil else { return }

        tableView.beginUpdates()
        tableView.endUpdates()
        tableView.layoutIfNeeded()
    }

    private func applySheetCornerRadius(_ radius: CGFloat) {
        if #available(iOS 15.0, *) {
            if let sheet = presentationController as? UISheetPresentationController {
                if sheet.preferredCornerRadius != radius {
                    sheet.preferredCornerRadius = radius
                }
            }
        }

        view.layer.cornerRadius = radius
        if #available(iOS 13.0, *) {
            view.layer.cornerCurve = .continuous
        }
        view.layer.masksToBounds = true

        var current = view.superview
        var hops = 0

        while let container = current, hops < 4 {
            container.layer.cornerRadius = radius
            if #available(iOS 13.0, *) {
                container.layer.cornerCurve = .continuous
            }
            container.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            container.layer.masksToBounds = true
            current = container.superview
            hops += 1
        }
    }

    @discardableResult
    private func addResultsHeaderIfNeeded() -> UIView? {
        guard let overlay = loadingView else { return nil }

        if headerContainerView == nil {
            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false

            let logo = UIImageView(image: UIImage(named: "logo"))
            logo.contentMode = .scaleAspectFit
            logo.translatesAutoresizingMaskIntoConstraints = false

            let cancelButton: UIButton
            if let existingButton = cancelButtonView {
                cancelButton = existingButton
            } else {
                let button = UIButton(type: .system)
                button.setTitle("Cancel", for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
                button.addTarget(self, action: #selector(cancelImportTapped), for: .touchUpInside)
                cancelButton = button
            }
            cancelButton.translatesAutoresizingMaskIntoConstraints = false
            cancelButtonView = cancelButton

            container.addSubview(logo)
            container.addSubview(cancelButton)

            overlay.addSubview(container)

            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: -5),
                container.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -16),
                container.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 14),
                container.heightAnchor.constraint(equalToConstant: 48),

                logo.centerXAnchor.constraint(equalTo: container.centerXAnchor, constant: 12),
                logo.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                logo.heightAnchor.constraint(equalToConstant: 28),
                logo.widthAnchor.constraint(equalToConstant: 132),

                cancelButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                cancelButton.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])

            headerContainerView = container
            headerLogoImageView = logo
        }

        // Add/show back button when showing results or preview
        if isShowingResults || isShowingPreview {
            if backButtonView == nil {
                let backButton = UIButton(type: .system)
                backButton.translatesAutoresizingMaskIntoConstraints = false
                backButton.adjustsImageWhenHighlighted = false

                backButton.addTarget(self, action: #selector(backButtonTapped), for: .touchUpInside)

                headerContainerView?.addSubview(backButton)

                NSLayoutConstraint.activate([
                    backButton.leadingAnchor.constraint(equalTo: headerContainerView!.leadingAnchor, constant: 16),
                    backButton.centerYAnchor.constraint(equalTo: headerContainerView!.centerYAnchor, constant: 1),
                    backButton.widthAnchor.constraint(equalToConstant: 18),
                    backButton.heightAnchor.constraint(equalToConstant: 18)
                ])

                backButtonView = backButton
            }

            // Apply onboarding-style appearance (also when reusing an existing button)
            if let backButton = backButtonView {
                let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                let backImage = UIImage(systemName: "chevron.left", withConfiguration: config)
                backButton.setImage(backImage, for: .normal)
                backButton.tintColor = UIColor(red: 28/255, green: 28/255, blue: 37/255, alpha: 1.0)
                backButton.adjustsImageWhenHighlighted = false

                // Ensure size matches onboarding style even if constraints already existed
                backButton.constraints.forEach { constraint in
                    if constraint.firstAttribute == .width {
                        constraint.constant = 18
                    } else if constraint.firstAttribute == .height {
                        constraint.constant = 18
                    } else if constraint.firstAttribute == .centerY {
                        constraint.constant = 1
                    }
                }

                backButton.isHidden = false
            }
        } else {
            backButtonView?.isHidden = true
        }

        headerContainerView?.isHidden = false
        return headerContainerView
    }

    private func removeResultsHeader() {
        headerLogoImageView = nil
        headerContainerView?.removeFromSuperview()
        headerContainerView = nil
        cancelButtonView = nil
        backButtonView = nil
    }

    // Resize image to max dimension to prevent server timeout and reduce bandwidth
    private func resizeImageForAPI(_ imageData: Data, maxDimension: CGFloat) -> Data? {
        // If image is already small in file size, don't resize (would make it bigger)
        let maxFileSize = 1_000_000 // 1MB
        if imageData.count <= maxFileSize {
            return imageData
        }

        guard let image = UIImage(data: imageData) else { return nil }

        let size = image.size
        let maxDim = max(size.width, size.height)

        // Already small enough, no need to resize
        if maxDim <= maxDimension { return imageData }

        let scale = maxDimension / maxDim
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resizedImage?.jpegData(compressionQuality: 0.8)
    }

    // Trigger detection using the Cloudinary-backed API
    private func uploadAndDetect(imageData: Data) {
        shareLog("START uploadAndDetect - image size: \(imageData.count) bytes")

        // Store the image for sharing later
        analyzedImageData = imageData

        // Stop status polling since we're now in detection mode
        stopStatusPolling()
        hasPresentedDetectionFailureAlert = false

        // Resize image to max 1600px to prevent server timeout
        let resizedData = resizeImageForAPI(imageData, maxDimension: 1600) ?? imageData
        shareLog("Resized image for API - size: \(resizedData.count) bytes (was \(imageData.count) bytes)")

        let base64Image = resizedData.base64EncodedString()
        shareLog("Base64 encoded - length: \(base64Image.count) chars")

        // Log memory usage before API call
        let usedMemoryMB = Double(getMemoryUsage()) / 1_048_576.0
        shareLog("Memory usage before API call: \(String(format: "%.1f", usedMemoryMB)) MB")

        let resolvedUrl = pendingImageUrl?.isEmpty == false ? pendingImageUrl : downloadedImageUrl
        downloadedImageUrl = resolvedUrl
        shareLog("Calling runDetectionAnalysis...")

        runDetectionAnalysis(imageUrl: resolvedUrl, imageBase64: base64Image)
    }

    // Update status label helper
    private func updateStatusLabel(_ text: String) {
        if isPhotosSourceApp {
            enforcePhotosStatusIfNeeded()
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.statusLabel?.text = text
        }
    }

    // Get current memory usage in bytes
    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        return kerr == KERN_SUCCESS ? info.resident_size : 0
    }

    // Check which products are already favorited
    private func checkFavoriteStatus(completion: @escaping () -> Void) {
        guard let serverBaseUrl = getServerBaseUrl() else {
            shareLog("Cannot check favorites - no server URL")
            completion()
            return
        }

        let productIds = detectionResults.map { $0.id }
        guard !productIds.isEmpty else {
            completion()
            return
        }

        let userId = getUserId()
        let endpoint = serverBaseUrl + "/api/v1/users/\(userId)/favorites/check"

        guard let url = URL(string: endpoint) else {
            shareLog("Invalid favorites check URL")
            completion()
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let jsonData = try? JSONSerialization.data(withJSONObject: productIds) else {
            shareLog("Failed to serialize product IDs")
            completion()
            return
        }

        request.httpBody = jsonData
        request.timeoutInterval = 10.0

        shareLog("Checking favorite status for \(productIds.count) products")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                completion()
                return
            }

            if let error = error {
                shareLog("Favorites check network error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion() }
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            shareLog("Favorites check response - status code: \(statusCode)")

            guard statusCode == 200, let data = data else {
                shareLog("Favorites check failed or returned non-200 status")
                DispatchQueue.main.async { completion() }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let favoritedIds = json["favorited_product_ids"] as? [String] {
                    shareLog("Found \(favoritedIds.count) already-favorited products")
                    DispatchQueue.main.async {
                        self.favoritedProductIds = Set(favoritedIds)
                        self.updateFavoriteMappings(for: favoritedIds)
                        completion()
                    }
                } else {
                    shareLog("Failed to parse favorites check response")
                    DispatchQueue.main.async { completion() }
                }
            } catch {
                shareLog("Error parsing favorites check: \(error.localizedDescription)")
                DispatchQueue.main.async { completion() }
            }
        }

        task.resume()
    }

    // Show UI when no results are found
    private func showNoResultsUI() {
        shareLog("Displaying no results UI")

        // Treat this as a results state so the back button appears in the header
        isShowingResults = true
        isShowingPreview = false
        addLogoAndCancel()

        // Hide loading indicator and progress bar
        activityIndicator?.stopAnimating()
        activityIndicator?.isHidden = true
        statusLabel?.isHidden = true
        progressView?.isHidden = true

        guard let loadingView = loadingView else {
            shareLog("ERROR: loadingView is nil - cannot show no results UI")
            return
        }

        // Create container for no results message
        let noResultsContainer = UIView()
        noResultsContainer.translatesAutoresizingMaskIntoConstraints = false

        // Icon
        let iconImageView = UIImageView()
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 48, weight: .light)
        iconImageView.image = UIImage(systemName: "magnifyingglass", withConfiguration: config)
        iconImageView.tintColor = UIColor.systemGray3
        iconImageView.contentMode = .scaleAspectFit

        // Title
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "No Results Found"
        titleLabel.font = UIFont(name: "PlusJakartaSans-SemiBold", size: 20)
            ?? .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        // Subtitle
        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "We couldn't find any matching products.\nTry a different image with clearer clothing items."
        subtitleLabel.font = UIFont(name: "PlusJakartaSans-Regular", size: 14)
            ?? .systemFont(ofSize: 14, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        // Tip label
        let tipLabel = UILabel()
        tipLabel.translatesAutoresizingMaskIntoConstraints = false
        tipLabel.text = "Tip: Avoid cropping too tight around the garment for better results."
        tipLabel.font = UIFont(name: "PlusJakartaSans-Regular", size: 12)
            ?? .systemFont(ofSize: 12, weight: .regular)
        tipLabel.textColor = UIColor.secondaryLabel
        tipLabel.textAlignment = .center
        tipLabel.numberOfLines = 0

        // Add main content to container (without tip)
        noResultsContainer.addSubview(iconImageView)
        noResultsContainer.addSubview(titleLabel)
        noResultsContainer.addSubview(subtitleLabel)

        loadingView.addSubview(noResultsContainer)
        loadingView.addSubview(tipLabel)

        NSLayoutConstraint.activate([
            // Main content centered (same approach as choice buttons page)
            noResultsContainer.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
            noResultsContainer.centerYAnchor.constraint(equalTo: loadingView.centerYAnchor),
            noResultsContainer.leadingAnchor.constraint(equalTo: loadingView.leadingAnchor, constant: 32),
            noResultsContainer.trailingAnchor.constraint(equalTo: loadingView.trailingAnchor, constant: -32),

            iconImageView.topAnchor.constraint(equalTo: noResultsContainer.topAnchor),
            iconImageView.centerXAnchor.constraint(equalTo: noResultsContainer.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 64),
            iconImageView.heightAnchor.constraint(equalToConstant: 64),

            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: noResultsContainer.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: noResultsContainer.trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            subtitleLabel.leadingAnchor.constraint(equalTo: noResultsContainer.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: noResultsContainer.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: noResultsContainer.bottomAnchor),

            // Tip at bottom (same approach as disclaimer on choice buttons page)
            tipLabel.leadingAnchor.constraint(equalTo: loadingView.leadingAnchor, constant: 32),
            tipLabel.trailingAnchor.constraint(equalTo: loadingView.trailingAnchor, constant: -32),
            tipLabel.bottomAnchor.constraint(equalTo: loadingView.safeAreaLayoutGuide.bottomAnchor, constant: -32)
        ])

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    @objc private func openAppFromNoResults() {
        shareLog("Open app tapped from no results screen")
        openWorthifyApp()
    }

    private func openWorthifyApp() {
        // Provide light feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        loadIds()
        guard let url = URL(string: "\(kSchemePrefix)-\(hostAppBundleIdentifier):share") else {
            shareLog("ERROR: Failed to create app URL for openWorthifyApp")
            return
        }

        shareLog("Attempting to open Worthify app with URL: \(url.absoluteString)")

        var responder: UIResponder? = self
        if #available(iOS 18.0, *) {
            while let current = responder {
                if let application = current as? UIApplication {
                    application.open(url, options: [:], completionHandler: nil)
                    break
                }
                responder = current.next
            }
        } else {
            while responder != nil {
                if responder!.responds(to: #selector(UIApplication.openURL(_:))) {
                    responder!.perform(#selector(UIApplication.openURL(_:)), with: url)
                    break
                }
                responder = responder!.next
            }
        }
    }

    // Show detection results in table view
    private func showDetectionResults() {
        shareLog("=== showDetectionResults START ===")
        shareLog("detectionResults.count: \(detectionResults.count)")
        shareLog("loadingView exists: \(loadingView != nil)")
        shareLog("resultsTableView exists: \(resultsTableView != nil)")

        guard !detectionResults.isEmpty else {
            shareLog("No results found - showing empty state UI")
            showNoResultsUI()
            return
        }

        // Prevent re-creating UI if already showing results
        if resultsTableView != nil {
            shareLog("[SKIP] showDetectionResults called again - results already displayed, skipping UI creation")
            return
        }

        shareLog("Showing \(detectionResults.count) detection results")

        // REQUEST EXTENDED EXECUTION TIME to prevent iOS from killing the extension
        // while user is browsing results. Critical for real device stability.
        requestExtendedExecution()

        // Check which products are already favorited before showing UI
        checkFavoriteStatus {
            self.displayResultsUI()
        }
    }

    private func displayResultsUI() {

        // Mark that we're showing results (for back button)
        isShowingResults = true
        isShowingPreview = false

        // Hide loading indicator
        activityIndicator?.stopAnimating()
        activityIndicator?.isHidden = true
        statusLabel?.isHidden = true

        // Initialize filtered results
        filteredResults = detectionResults
        selectedGroup = nil

        shareLog("Creating table view...")
        // Create table view if not exists
        if resultsTableView == nil {
            let tableView = UITableView(frame: .zero, style: .plain)
            tableView.translatesAutoresizingMaskIntoConstraints = false
            tableView.delegate = self
            tableView.dataSource = self
            tableView.register(ResultCell.self, forCellReuseIdentifier: "ResultCell")
            tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ResultsHeaderCell")
            tableView.rowHeight = UITableView.automaticDimension
            tableView.estimatedRowHeight = 100
            tableView.backgroundColor = .systemBackground
            tableView.separatorStyle = .singleLine
            tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

            // Prevent white space issues when header resizes
            tableView.contentInsetAdjustmentBehavior = .never
            tableView.insetsContentViewsToSafeArea = false

            resultsTableView = tableView
            shareLog("Table view created successfully")
        }

        // Create bottom bar with Share button
        let bottomBarContainer = UIView()
        bottomBarContainer.backgroundColor = .systemBackground
        bottomBarContainer.translatesAutoresizingMaskIntoConstraints = false

        // Separator line
        let separator = UIView()
        separator.backgroundColor = UIColor.systemGray5
        separator.translatesAutoresizingMaskIntoConstraints = false

        // Share button (primary style - previously Save button)
        let shareButton = UIButton(type: .system)
        shareButton.setTitle("Share", for: .normal)
        shareButton.titleLabel?.font = UIFont(name: "PlusJakartaSans-Bold", size: 16)
            ?? .systemFont(ofSize: 16, weight: .bold)
        shareButton.backgroundColor = UIColor(red: 242/255, green: 0, blue: 60/255, alpha: 1.0)
        shareButton.setTitleColor(.white, for: .normal)
        shareButton.layer.cornerRadius = 28
        shareButton.addTarget(self, action: #selector(shareResultsTapped), for: .touchUpInside)
        shareButton.translatesAutoresizingMaskIntoConstraints = false

        bottomBarContainer.addSubview(separator)
        bottomBarContainer.addSubview(shareButton)

        // Layout constraints - safely unwrap FIRST to prevent crashes
        guard let loadingView = loadingView, let tableView = resultsTableView else {
            shareLog("ERROR: loadingView or resultsTableView is nil - cannot display results")
            return
        }

        let headerView = addResultsHeaderIfNeeded()

        // Create results header view containing image comparison + results count
        let resultsHeaderContainer = UIView()
        resultsHeaderContainer.backgroundColor = .systemBackground
        resultsHeaderContainer.translatesAutoresizingMaskIntoConstraints = false
        resultsHeaderContainerView = resultsHeaderContainer

        // Image comparison view
        let imageComparisonView = createImageComparisonView()

        // Results count label
        let resultsLabel = UILabel()
        let resultsCount = detectionResults.count
        resultsLabel.text = "Found \(resultsCount) similar match\(resultsCount == 1 ? "" : "es")"
        resultsLabel.font = UIFont(name: "PlusJakartaSans-Medium", size: 16)
            ?? .systemFont(ofSize: 17, weight: .medium)
        resultsLabel.textColor = UIColor(red: 242/255, green: 0, blue: 60/255, alpha: 1.0) // Munsell red
        resultsLabel.translatesAutoresizingMaskIntoConstraints = false

        let imageComparisonTapArea = UIControl()
        imageComparisonTapArea.translatesAutoresizingMaskIntoConstraints = false
        imageComparisonTapArea.addTarget(self, action: #selector(toggleImageComparison), for: .touchUpInside)

        resultsHeaderContainer.addSubview(imageComparisonTapArea)
        imageComparisonTapArea.addSubview(imageComparisonView)
        resultsHeaderContainer.addSubview(resultsLabel)

        // Prefer a fixed card width, but clamp it to available space.
        let widthConstraint = imageComparisonView.widthAnchor.constraint(equalToConstant: 408)
        widthConstraint.priority = .defaultHigh
        imageComparisonWidthConstraint = widthConstraint

        let fallbackWidthConstraint = imageComparisonView.widthAnchor.constraint(
            equalTo: imageComparisonTapArea.widthAnchor,
            constant: -32
        )
        fallbackWidthConstraint.priority = .defaultLow

        NSLayoutConstraint.activate([
            // Tap area spans full row width so the entire row is clickable.
            imageComparisonTapArea.topAnchor.constraint(equalTo: resultsHeaderContainer.topAnchor, constant: 12),
            imageComparisonTapArea.leadingAnchor.constraint(equalTo: resultsHeaderContainer.leadingAnchor),
            imageComparisonTapArea.trailingAnchor.constraint(equalTo: resultsHeaderContainer.trailingAnchor),

            // Image comparison card inside the tap area.
            imageComparisonView.topAnchor.constraint(equalTo: imageComparisonTapArea.topAnchor),
            imageComparisonView.leadingAnchor.constraint(equalTo: imageComparisonTapArea.leadingAnchor, constant: 16),
            imageComparisonView.bottomAnchor.constraint(equalTo: imageComparisonTapArea.bottomAnchor),
            imageComparisonView.heightAnchor.constraint(equalToConstant: 68),
            widthConstraint,
            imageComparisonView.widthAnchor.constraint(lessThanOrEqualTo: imageComparisonTapArea.widthAnchor, constant: -32),
            fallbackWidthConstraint,

            // Results label below image comparison
            resultsLabel.topAnchor.constraint(equalTo: imageComparisonTapArea.bottomAnchor, constant: 16),
            resultsLabel.leadingAnchor.constraint(equalTo: resultsHeaderContainer.leadingAnchor, constant: 16),
            resultsLabel.trailingAnchor.constraint(equalTo: resultsHeaderContainer.trailingAnchor, constant: -16),
            resultsLabel.bottomAnchor.constraint(equalTo: resultsHeaderContainer.bottomAnchor, constant: -12),
        ])

        // Add all views to loadingView
        loadingView.addSubview(tableView)
        loadingView.addSubview(bottomBarContainer)
        if let headerView = headerView {
            loadingView.bringSubviewToFront(headerView)
        }

        let tableTopAnchor: NSLayoutYAxisAnchor
        if let headerView = headerView {
            tableTopAnchor = headerView.bottomAnchor
        } else {
            tableTopAnchor = loadingView.safeAreaLayoutGuide.topAnchor
        }

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: tableTopAnchor),
            tableView.leadingAnchor.constraint(equalTo: loadingView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: loadingView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomBarContainer.topAnchor),

            bottomBarContainer.leadingAnchor.constraint(equalTo: loadingView.leadingAnchor),
            bottomBarContainer.trailingAnchor.constraint(equalTo: loadingView.trailingAnchor),
            bottomBarContainer.bottomAnchor.constraint(equalTo: loadingView.safeAreaLayoutGuide.bottomAnchor),
            bottomBarContainer.heightAnchor.constraint(equalToConstant: 90),

            separator.topAnchor.constraint(equalTo: bottomBarContainer.topAnchor),
            separator.leadingAnchor.constraint(equalTo: bottomBarContainer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: bottomBarContainer.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            // Share button (full width)
            shareButton.topAnchor.constraint(equalTo: bottomBarContainer.topAnchor, constant: 16),
            shareButton.leadingAnchor.constraint(equalTo: bottomBarContainer.leadingAnchor, constant: 16),
            shareButton.trailingAnchor.constraint(equalTo: bottomBarContainer.trailingAnchor, constant: -16),
            shareButton.heightAnchor.constraint(equalToConstant: 56)
        ])

        tableView.reloadData()
        shareLog("Results UI successfully displayed")
    }

    private func createImageComparisonView() -> UIView {
        let container = UIView()
        // Match Flutter Colors.grey.shade50 (RGB 249, 249, 249)
        container.backgroundColor = UIColor(red: 249/255, green: 249/255, blue: 249/255, alpha: 1.0)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.cornerRadius = 12
        container.clipsToBounds = true
        container.isUserInteractionEnabled = false

        // Collapsed state UI - thumbnail + text + icon
        let collapsedStackView = UIStackView()
        collapsedStackView.axis = .horizontal
        collapsedStackView.spacing = 12
        collapsedStackView.alignment = .center
        collapsedStackView.translatesAutoresizingMaskIntoConstraints = false
        collapsedStackView.tag = 1001 // Tag for easy reference

        // Thumbnail image view
        let thumbnailImageView = UIImageView()
        thumbnailImageView.contentMode = .scaleAspectFill
        thumbnailImageView.clipsToBounds = true
        thumbnailImageView.layer.cornerRadius = 8
        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
        // Use lighter background for thumbnail
        thumbnailImageView.backgroundColor = UIColor(red: 249/255, green: 249/255, blue: 249/255, alpha: 1.0)

        // Load image from pendingImageData or analyzedImageData
        if let data = pendingImageData ?? analyzedImageData, let image = UIImage(data: data) {
            thumbnailImageView.image = image
            shareLog("[ImageComparison] Thumbnail loaded from image data")
        } else {
            shareLog("[ImageComparison] WARNING: No image data available for thumbnail")
        }
        imageComparisonThumbnailImageView = thumbnailImageView

        // Text label
        let textLabel = UILabel()
        textLabel.text = "Compare with original"
        textLabel.font = UIFont(name: "PlusJakartaSans-Medium", size: 14)
            ?? .systemFont(ofSize: 15, weight: .medium)
        textLabel.textColor = .label
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Expand/collapse icon
        let iconImageView = UIImageView()
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        iconImageView.image = UIImage(systemName: "chevron.down", withConfiguration: iconConfig)
        iconImageView.tintColor = .secondaryLabel
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.tag = 1002 // Tag for rotation animation

        collapsedStackView.addArrangedSubview(thumbnailImageView)
        collapsedStackView.addArrangedSubview(textLabel)
        collapsedStackView.addArrangedSubview(UIView()) // Spacer
        collapsedStackView.addArrangedSubview(iconImageView)

        // Expanded state UI - full image
        let fullImageView = UIImageView()
        fullImageView.contentMode = .scaleAspectFill
        fullImageView.clipsToBounds = true
        fullImageView.layer.cornerRadius = 12
        fullImageView.translatesAutoresizingMaskIntoConstraints = false
        fullImageView.alpha = 0 // Hidden initially
        fullImageView.tag = 1003
        // Match container background to prevent white flash during fade
        fullImageView.backgroundColor = UIColor(red: 249/255, green: 249/255, blue: 249/255, alpha: 1.0)

        // Load image from pendingImageData or analyzedImageData
        if let data = pendingImageData ?? analyzedImageData, let image = UIImage(data: data) {
            fullImageView.image = image
            shareLog("[ImageComparison] Full image loaded from image data")
        } else {
            shareLog("[ImageComparison] WARNING: No image data available for full view")
        }
        imageComparisonFullImageView = fullImageView

        container.addSubview(collapsedStackView)
        container.addSubview(fullImageView)

        NSLayoutConstraint.activate([
            // Thumbnail constraints (48x48 instead of 56x56 for less height)
            thumbnailImageView.widthAnchor.constraint(equalToConstant: 48),
            thumbnailImageView.heightAnchor.constraint(equalToConstant: 48),

            // Icon constraints
            iconImageView.widthAnchor.constraint(equalToConstant: 16),
            iconImageView.heightAnchor.constraint(equalToConstant: 16),

            // Collapsed stack view (10px padding instead of 12px for less height)
            collapsedStackView.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            collapsedStackView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            collapsedStackView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            collapsedStackView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),

            // Full image view (takes full container when expanded)
            fullImageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            fullImageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            fullImageView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            fullImageView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])

        imageComparisonContainerView = container
        return container
    }

    @objc private func toggleImageComparison() {
        guard let container = imageComparisonContainerView else { return }

        isImageComparisonExpanded.toggle()

        let collapsedView = container.viewWithTag(1001)
        let fullImageView = container.viewWithTag(1003) as? UIImageView
        let iconView = container.viewWithTag(1002) as? UIImageView

        // Calculate expanded height based on image aspect ratio
        let expandedHeight: CGFloat
        if let image = fullImageView?.image {
            let containerWidth = container.frame.width - 32 // Account for padding
            let aspectRatio = image.size.height / image.size.width
            // Calculate height maintaining aspect ratio, with max height of 400
            let calculatedHeight = (containerWidth * aspectRatio) + 24 // Add padding
            expandedHeight = min(calculatedHeight, 400)
        } else {
            expandedHeight = 300 // Default fallback
        }

        // Update height constraint BEFORE animation
        if let heightConstraint = container.constraints.first(where: { $0.firstAttribute == .height }) {
            heightConstraint.isActive = false
        }

        let newHeight: CGFloat = isImageComparisonExpanded ? expandedHeight : 68
        let heightConstraint = container.heightAnchor.constraint(equalToConstant: newHeight)
        heightConstraint.isActive = true

        // Animate with smoother cross-fade and layout update
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
            if self.isImageComparisonExpanded {
                // Expand: cross-fade from collapsed to full image
                collapsedView?.alpha = 0
                fullImageView?.alpha = 1
                iconView?.transform = CGAffineTransform(rotationAngle: .pi)
            } else {
                // Collapse: cross-fade from full image to collapsed
                collapsedView?.alpha = 1
                fullImageView?.alpha = 0
                iconView?.transform = .identity
            }

            // Layout container and update table header
            container.layoutIfNeeded()
            if let loadingView = self.loadingView {
                loadingView.layoutIfNeeded()
            } else {
                container.superview?.layoutIfNeeded()
            }
            self.resultsTableView?.beginUpdates()
            self.resultsTableView?.endUpdates()
        } completion: { _ in
            if let loadingView = self.loadingView {
                loadingView.layoutIfNeeded()
            }
            self.resultsTableView?.beginUpdates()
            self.resultsTableView?.endUpdates()
        }
    }

    private func createCategoryFilters() -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .systemBackground
        containerView.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let button = UIButton(type: .system)
        let primaryRed = UIColor(red: 242/255, green: 0, blue: 60/255, alpha: 1.0)
        button.setTitle(CategoryGroup.all.displayName, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        button.layer.cornerRadius = 18
        button.clipsToBounds = true
        button.layer.borderWidth = 1
        button.layer.borderColor = primaryRed.cgColor
        button.backgroundColor = primaryRed
        button.setTitleColor(.white, for: .normal)
        button.isUserInteractionEnabled = false
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true

        stackView.addArrangedSubview(button)

        // Results count label on far right
        let resultsCountLabel = UILabel()
        resultsCountLabel.translatesAutoresizingMaskIntoConstraints = false
        resultsCountLabel.font = .systemFont(ofSize: 14, weight: .medium)
        resultsCountLabel.textColor = .secondaryLabel
        resultsCountLabel.textAlignment = .right
        let count = detectionResults.count
        resultsCountLabel.text = count == 1 ? "1 result" : "\(count) results"
        resultsCountLabel.tag = 1001 // Tag for updating later

        scrollView.addSubview(stackView)
        containerView.addSubview(scrollView)
        containerView.addSubview(resultsCountLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: resultsCountLabel.leadingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),

            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),

            resultsCountLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            resultsCountLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])

        return containerView
    }

    // Convert server category to display name
    @objc private func categoryFilterTapped(_ sender: UIButton) {
        // Only "All" chip exists; no filtering required.
        filterResultsByCategory()
    }

    private func filterResultsByCategory() {
        filteredResults = detectionResults
        resultsTableView?.reloadData()
        shareLog("Filtered to \(filteredResults.count) results for category: All")
    }

    private func sanitize(results: [DetectionResultItem]) -> [DetectionResultItem] {
        return results.filter { isAllowed(result: $0) }
    }

    private func isAllowed(result: DetectionResultItem) -> Bool {
        let fields = [
            result.product_name,
            result.brand ?? "",
            result.description ?? "",
            result.purchase_url ?? ""
        ].joined(separator: " ")

        let range = NSRange(location: 0, length: (fields as NSString).length)
        for regex in bannedKeywordPatterns {
            if regex.firstMatch(in: fields, options: [], range: range) != nil {
                return false
            }
        }
        return true
    }

    @objc private func saveAllTapped() {
        shareLog("Save All button tapped - saving all results and redirecting")

        // End extended execution since we're wrapping up
        endExtendedExecution()

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Call backend API to save search
        if let searchId = currentSearchId {
            saveSearchToBackend(searchId: searchId)
        } else {
            shareLog("WARNING: No search_id available - skipping backend save")
        }

        // Write the pending image file to shared container
        if let data = pendingImageData, let file = pendingSharedFile {
            guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
                shareLog("ERROR: Cannot get container URL for Save All")
                return
            }

            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let fileName = "instagram_image_\(timestamp)_all.jpg"
            let fileURL = containerURL.appendingPathComponent(fileName)

            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                try data.write(to: fileURL, options: .atomic)
                shareLog("SAVE ALL: Wrote file to shared container: \(fileURL.path)")

                // Update the shared file path
                var updatedFile = file
                updatedFile.path = fileURL.absoluteString

                // Save all detection results and the file to UserDefaults
                if let defaults = UserDefaults(suiteName: appGroupId) {
                    // Encode all detection results
                    if let resultsData = try? JSONEncoder().encode(detectionResults),
                       let jsonString = String(data: resultsData, encoding: .utf8) {
                        defaults.set(jsonString, forKey: "AllDetectionResults")
                        shareLog("SAVE ALL: Saved \(detectionResults.count) results to UserDefaults")
                    }

                    // Save the file
                    defaults.set(toData(data: [updatedFile]), forKey: kUserDefaultsKey)
                    defaults.synchronize()
                    shareLog("SAVE ALL: Saved file to UserDefaults")
                }
            } catch {
                shareLog("ERROR writing file for Save All: \(error.localizedDescription)")
                return
            }
        }

        // Redirect to app
        loadIds()
        guard let redirectURL = URL(string: "\(kSchemePrefix)-\(hostAppBundleIdentifier):detection-all") else {
            shareLog("ERROR: Failed to build redirect URL for Save All")
            return
        }

        hasQueuedRedirect = true
        shareLog("Redirecting to app with all detection results")
        let minimumDuration = isPhotosSourceApp ? 2.0 : 0.0
        enqueueRedirect(to: redirectURL, minimumDuration: minimumDuration) { [weak self] in
            self?.finishExtensionRequest()
        }
    }

    // Get server base URL from detection endpoint
    private func getServerBaseUrl() -> String? {
        guard let endpoint = detectorEndpoint() else {
            return nil
        }

        // Extract base URL from endpoint like "https://domain.com/detect-and-search"
        if let url = URL(string: endpoint),
           let scheme = url.scheme,
           let host = url.host {
            var baseUrl = "\(scheme)://\(host)"
            if let port = url.port {
                baseUrl += ":\(port)"
            }
            return baseUrl
        }

        return nil
    }

    // Backend API calls for favorites and save
    private func saveSearchToBackend(searchId: String) {
        guard let serverBaseUrl = getServerBaseUrl(),
              let serverUrl = URL(string: serverBaseUrl) else {
            shareLog("ERROR: Could not determine server URL from detection endpoint")
            return
        }

        let endpoint = serverUrl.appendingPathComponent("api/v1/searches/\(searchId)/save")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "user_id": getUserId(),
            "name": nil as Any?
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            shareLog("ERROR: Failed to serialize save search request: \(error.localizedDescription)")
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                shareLog("ERROR: Save search request failed: \(error.localizedDescription)")
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                shareLog("Save search response status: \(httpResponse.statusCode)")
                if httpResponse.statusCode == 200 {
                    shareLog("Search saved successfully")
                } else {
                    shareLog("Save search failed with status \(httpResponse.statusCode)")
                }
            }
        }

        task.resume()
    }

    private func addFavoriteToBackend(product: DetectionResultItem, completion: @escaping (Bool) -> Void) {
        guard let serverBaseUrl = getServerBaseUrl(),
              let serverUrl = URL(string: serverBaseUrl) else {
            shareLog("ERROR: Could not determine server URL from detection endpoint")
            completion(false)
            return
        }

        let endpoint = serverUrl.appendingPathComponent("api/v1/favorites")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let productData: [String: Any] = [
            "id": product.id,
            "product_id": product.id,  // Also include as product_id for backwards compatibility
            "product_name": product.product_name,
            "brand": product.brand ?? "",
            "price": product.priceValue ?? 0.0,
            "image_url": product.image_url,
            "purchase_url": product.purchase_url ?? "",
            "category": product.category
        ]

        let body: [String: Any] = [
            "user_id": getUserId(),
            "search_id": currentSearchId as Any?,
            "product": productData
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            shareLog("ERROR: Failed to serialize add favorite request: \(error.localizedDescription)")
            completion(false)
            return
        }

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            if let error = error {
                shareLog("ERROR: Add favorite request failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(false) }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                shareLog("ERROR: Add favorite response missing HTTP status")
                DispatchQueue.main.async { completion(false) }
                return
            }

            shareLog("Add favorite response status: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            var favoriteId: String?
            var alreadyExisted = false

            if let data = data {
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        favoriteId = json["favorite_id"] as? String
                        alreadyExisted = json["already_existed"] as? Bool ?? false
                    }
                } catch {
                    shareLog("ERROR: Unable to parse add favorite response: \(error.localizedDescription)")
                }
            } else {
                shareLog("WARNING: Add favorite response contained no body")
            }

            if let favoriteId = favoriteId {
                DispatchQueue.main.async {
                    self.favoriteIdByProductId[product.id] = favoriteId
                    shareLog("Add favorite success - favorite_id: \(favoriteId), already existed: \(alreadyExisted)")
                    completion(true)
                }
            } else {
                shareLog("WARNING: favorite_id missing after add favorite, attempting mapping refresh")
                self.updateFavoriteMappings(for: [product.id]) { _ in
                    completion(true)
                }
            }
        }

        task.resume()
    }

    private func removeFavoriteFromBackend(
        product: DetectionResultItem,
        completion: @escaping (Bool) -> Void
    ) {
        ensureFavoriteId(for: product.id) { [weak self] favoriteId in
            guard let self = self else {
                completion(false)
                return
            }

            guard let favoriteId = favoriteId else {
                shareLog("ERROR: Unable to resolve favorite_id for product \(product.id)")
                completion(false)
                return
            }

            guard let serverBaseUrl = self.getServerBaseUrl() else {
                shareLog("ERROR: Could not determine server URL for remove favorite")
                completion(false)
                return
            }

            guard var components = URLComponents(string: serverBaseUrl + "/api/v1/favorites/\(favoriteId)") else {
                shareLog("ERROR: Invalid remove favorite URL for id \(favoriteId)")
                completion(false)
                return
            }

            components.queryItems = [
                URLQueryItem(name: "user_id", value: self.getUserId())
            ]

            guard let url = components.url else {
                shareLog("ERROR: Failed to construct remove favorite URL")
                completion(false)
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.timeoutInterval = 10.0

            URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
                guard let self = self else {
                    DispatchQueue.main.async { completion(false) }
                    return
                }

                if let error = error {
                    shareLog("ERROR: Remove favorite request failed: \(error.localizedDescription)")
                    DispatchQueue.main.async { completion(false) }
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    shareLog("ERROR: Remove favorite response missing HTTP status")
                    DispatchQueue.main.async { completion(false) }
                    return
                }

                shareLog("Remove favorite response status: \(httpResponse.statusCode)")

                guard httpResponse.statusCode == 200 else {
                    DispatchQueue.main.async { completion(false) }
                    return
                }

                DispatchQueue.main.async {
                    self.favoriteIdByProductId.removeValue(forKey: product.id)
                    completion(true)
                }
            }.resume()
        }
    }

    private func ensureFavoriteId(
        for productId: String,
        completion: @escaping (String?) -> Void
    ) {
        if let cachedId = favoriteIdByProductId[productId] {
            completion(cachedId)
            return
        }

        updateFavoriteMappings(for: [productId]) { [weak self] mappings in
            guard let self = self else {
                completion(nil)
                return
            }

            let resolvedId = mappings[productId] ?? self.favoriteIdByProductId[productId]
            if let resolvedId = resolvedId {
                shareLog("Resolved favorite_id \(resolvedId) for product \(productId)")
            } else {
                shareLog("WARNING: Unable to resolve favorite_id for product \(productId)")
            }
            completion(resolvedId)
        }
    }

    private func updateFavoriteMappings(
        for productIds: [String],
        completion: (([String: String]) -> Void)? = nil
    ) {
        let uniqueIds = Array(Set(productIds))
        let unresolvedIds = uniqueIds.filter { favoriteIdByProductId[$0] == nil }

        if !uniqueIds.isEmpty && unresolvedIds.isEmpty {
            DispatchQueue.main.async { completion?([:]) }
            return
        }

        guard let serverBaseUrl = getServerBaseUrl() else {
            shareLog("Cannot refresh favorite mappings - no server URL available")
            DispatchQueue.main.async { completion?([:]) }
            return
        }

        let userId = getUserId()
        var components = URLComponents(string: serverBaseUrl + "/api/v1/users/\(userId)/favorites")
        components?.queryItems = [
            URLQueryItem(name: "limit", value: "200"),
            URLQueryItem(name: "offset", value: "0")
        ]

        guard let url = components?.url else {
            shareLog("Invalid URL when refreshing favorite mappings")
            DispatchQueue.main.async { completion?([:]) }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0

        let filterSet: Set<String>? = uniqueIds.isEmpty ? nil : Set(unresolvedIds)
        let fetchDescriptionText: String
        if let filterSet = filterSet {
            fetchDescriptionText = "\(filterSet.count)"
        } else {
            fetchDescriptionText = "all available"
        }
        shareLog("Refreshing favorite mappings for \(fetchDescriptionText) products (requested \(uniqueIds.count))")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                DispatchQueue.main.async { completion?([:]) }
                return
            }

            var mappingUpdates: [String: String] = [:]

            if let error = error {
                shareLog("ERROR: Favorite mappings fetch failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion?(mappingUpdates) }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                shareLog("ERROR: Favorite mappings response missing HTTP status")
                DispatchQueue.main.async { completion?(mappingUpdates) }
                return
            }

            shareLog("Favorite mappings fetch status: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200, let data = data else {
                shareLog("Favorite mappings fetch failed or returned no data")
                DispatchQueue.main.async { completion?(mappingUpdates) }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let favorites = json["favorites"] as? [[String: Any]] {
                    for entry in favorites {
                        guard
                            let productId = entry["product_id"] as? String,
                            let favoriteId = entry["id"] as? String
                        else { continue }

                        if let filterSet = filterSet, !filterSet.contains(productId) {
                            continue
                        }

                        mappingUpdates[productId] = favoriteId
                    }
                } else {
                    shareLog("WARNING: Unexpected favorites payload when refreshing mappings")
                }
            } catch {
                shareLog("ERROR: Failed to parse favorite mappings: \(error.localizedDescription)")
            }

            DispatchQueue.main.async {
                if !mappingUpdates.isEmpty {
                    self.favoriteIdByProductId.merge(mappingUpdates) { _, new in new }
                }
                completion?(mappingUpdates)
            }
        }.resume()
    }

    private func getUserId() -> String {
        // Get Supabase auth user ID from shared UserDefaults
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            shareLog("ERROR: Could not access shared UserDefaults with appGroupId: \(appGroupId)")
            return "anonymous"
        }

        // Check auth flag (primary + legacy alias)
        let isAuthenticated = defaults.bool(forKey: "user_authenticated") || defaults.bool(forKey: "is_authenticated")
        shareLog("getUserId - isAuthenticated flag: \(isAuthenticated)")

        // Try primary and legacy user ID keys.
        let candidateKeys = ["supabase_user_id", "user_id"]
        for key in candidateKeys {
            if let raw = defaults.string(forKey: key) {
                let userId = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if userId.isEmpty {
                    shareLog("WARNING: \(key) exists but is EMPTY")
                    continue
                }

                if UUID(uuidString: userId) != nil {
                    shareLog("getUserId - Using Supabase user ID from \(key): \(userId)")
                    return userId
                } else {
                    shareLog("WARNING: \(key) is not a valid UUID: \(userId)")
                }
            }
        }

        // Debug: List all keys in UserDefaults
        let allKeys = Array(defaults.dictionaryRepresentation().keys)
        shareLog("DEBUG: All UserDefaults keys: \(allKeys.joined(separator: ", "))")

        // Never use device ID fallback for analysis writes.
        // If authenticated but no valid user ID is synced, backend history links break.
        if isAuthenticated {
            shareLog("ERROR: Authenticated user missing valid Supabase user ID in shared defaults")
        } else {
            shareLog("WARNING: User not authenticated while resolving user ID")
        }

        return "anonymous"
    }

    private func deductCredits(garmentCount: Int) {
        shareLog("[Credits] Attempting to deduct \(garmentCount) credits")

        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            shareLog("[Credits] ERROR: Could not access shared UserDefaults")
            return
        }

        guard let supabaseUrl = defaults.string(forKey: kSupabaseUrlKey),
              let supabaseAnonKey = defaults.string(forKey: kSupabaseAnonKeyKey) else {
            shareLog("[Credits] ERROR: Supabase configuration not found in UserDefaults")
            return
        }

        let userId = getUserId()
        shareLog("[Credits] Using user ID: \(userId)")

        let rpcEndpoint = "\(supabaseUrl)/rest/v1/rpc/deduct_credits"
        shareLog("[Credits] RPC endpoint: \(rpcEndpoint)")

        guard let url = URL(string: rpcEndpoint) else {
            shareLog("[Credits] ERROR: Invalid RPC endpoint URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "p_user_id": userId,
            "p_garment_count": garmentCount
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            shareLog("[Credits] ERROR: Failed to serialize request body: \(error)")
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                shareLog("[Credits] ERROR: Request failed: \(error.localizedDescription)")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                shareLog("[Credits] ERROR: Invalid response type")
                return
            }

            shareLog("[Credits] Response status code: \(httpResponse.statusCode)")

            guard let data = data else {
                shareLog("[Credits] ERROR: No response data")
                return
            }

            if let responseString = String(data: data, encoding: .utf8) {
                shareLog("[Credits] Response: \(responseString)")
            }

            if httpResponse.statusCode == 200 {
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                       let result = json.first {
                        if let success = result["success"] as? Bool, success {
                            let remaining = result["paid_credits_remaining"] as? Int ?? 0
                            shareLog("[Credits] SUCCESS: Deducted \(garmentCount) credits, remaining: \(remaining)")

                            // Update credits in UserDefaults for UI
                            DispatchQueue.main.async {
                                defaults.set(remaining, forKey: "user_available_credits")
                                defaults.synchronize()
                                if remaining <= 0 {
                                    shareLog("[Credits] Remaining credits are now 0 - scheduling out of credits modal")
                                    self.shouldShowOutOfCreditsAfterAnalysis = true
                                    self.maybeShowPostAnalysisOutOfCreditsModal()
                                }
                            }
                        } else {
                            let message = result["message"] as? String ?? "Unknown error"
                            shareLog("[Credits] FAILED: \(message)")
                        }
                    }
                } catch {
                    shareLog("[Credits] ERROR: Failed to parse response: \(error)")
                }
            } else {
                shareLog("[Credits] ERROR: Server returned status \(httpResponse.statusCode)")
            }
        }

        task.resume()
    }

    private func extractInstagramUsername(from url: String) -> String? {
        // Extract username from Instagram URLs like:
        // https://www.instagram.com/username/...
        // https://instagram.com/username/...
        if let regex = try? NSRegularExpression(pattern: "instagram\\.com/([^/]+)", options: []),
           let match = regex.firstMatch(in: url, options: [], range: NSRange(url.startIndex..., in: url)),
           match.numberOfRanges > 1,
           let usernameRange = Range(match.range(at: 1), in: url) {
            let username = String(url[usernameRange])
            // Filter out non-username paths like 'p', 'reel', 'tv', etc.
            if !["p", "reel", "tv", "stories", "explore"].contains(username.lowercased()) {
                return username
            }
        }
        return nil
    }

    // Custom activity item source for rich share metadata
    private class WorthifyShareItem: NSObject, UIActivityItemSource {
        let imageURL: URL
        let imageTitle: String
        let imageSubject: String
        let thumbnailImage: UIImage?

        init(imageURL: URL, title: String, subject: String, thumbnailImage: UIImage?) {
            self.imageURL = imageURL
            self.imageTitle = title
            self.imageSubject = subject
            self.thumbnailImage = thumbnailImage
            super.init()
        }

        func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
            return imageURL
        }

        func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
            return imageURL
        }

        func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
            return imageSubject
        }

        func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
            return "public.jpeg"
        }

        func activityViewController(_ activityViewController: UIActivityViewController, thumbnailImageForActivityType activityType: UIActivity.ActivityType?, suggestedSize size: CGSize) -> UIImage? {
            guard let heroImage = thumbnailImage else {
                return nil
            }

            // Calculate aspect-fit size to show entire analyzed image in thumbnail
            let imageSize = heroImage.size
            let widthRatio = size.width / imageSize.width
            let heightRatio = size.height / imageSize.height
            let scaleFactor = min(widthRatio, heightRatio)

            let scaledSize = CGSize(
                width: imageSize.width * scaleFactor,
                height: imageSize.height * scaleFactor
            )

            // Render thumbnail at proper size
            let renderer = UIGraphicsImageRenderer(size: scaledSize)
            return renderer.image { _ in
                heroImage.draw(in: CGRect(origin: .zero, size: scaledSize))
            }
        }

        @available(iOS 13.0, *)
        func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
            let metadata = LPLinkMetadata()
            metadata.title = imageSubject

            if let thumbnail = thumbnailImage {
                metadata.imageProvider = NSItemProvider(object: thumbnail)
                metadata.iconProvider = NSItemProvider(object: thumbnail)
            }

            return metadata
        }
    }

    @objc private func shareResultsTapped() {
        shareLog("Share button tapped - preparing share content")
        shareLog("analyzedImageData exists: \(analyzedImageData != nil)")
        if let data = analyzedImageData {
            shareLog("analyzedImageData size: \(data.count) bytes")
        }

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Show loading indicator while preparing share content
        let loadingView = UIView(frame: view.bounds)
        loadingView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        loadingView.tag = 9999 // Tag for easy removal

        let loadingContainer = UIView()
        loadingContainer.backgroundColor = UIColor.systemBackground
        loadingContainer.layer.cornerRadius = 12
        loadingContainer.translatesAutoresizingMaskIntoConstraints = false

        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.startAnimating()
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        let loadingLabel = UILabel()
        loadingLabel.text = "Preparing to share..."
        loadingLabel.font = .systemFont(ofSize: 14, weight: .medium)
        loadingLabel.textColor = .label
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false

        loadingContainer.addSubview(activityIndicator)
        loadingContainer.addSubview(loadingLabel)
        loadingView.addSubview(loadingContainer)
        view.addSubview(loadingView)

        NSLayoutConstraint.activate([
            loadingContainer.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
            loadingContainer.centerYAnchor.constraint(equalTo: loadingView.centerYAnchor),
            loadingContainer.widthAnchor.constraint(equalToConstant: 200),
            loadingContainer.heightAnchor.constraint(equalToConstant: 80),

            activityIndicator.centerXAnchor.constraint(equalTo: loadingContainer.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: loadingContainer.topAnchor, constant: 16),

            loadingLabel.centerXAnchor.constraint(equalTo: loadingContainer.centerXAnchor),
            loadingLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 8)
        ])

        // Prepare share content asynchronously to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            self.prepareAndPresentShare(loadingView: loadingView)
        }
    }

    private func generateShareCard(heroImage: UIImage, products: [DetectionResultItem]) -> UIImage? {
        // Card dimensions - scaled down 40% (60% of original)
        let canvasWidth: CGFloat = 648
        let canvasHeight: CGFloat = 1290

        // Helper for scaling
        let scale = canvasWidth / 1080
        func s(_ value: CGFloat) -> CGFloat {
            return value * scale
        }

        let cardPadding = s(40)
        let heroPadding = s(240)
        let heroHeight = s(600)
        let heroRadius = s(72)
        let cardRadius = s(96)

        // Create rendering context
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvasWidth, height: canvasHeight), format: UIGraphicsImageRendererFormat())

        return renderer.image { context in
            let ctx = context.cgContext

            // White card background with shadow - fills entire canvas
            let cardPath = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight), cornerRadius: cardRadius)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: s(20)), blur: s(40), color: UIColor.black.withAlphaComponent(0.08).cgColor)
            UIColor.white.setFill()
            cardPath.fill()
            ctx.restoreGState()

            // Pre-calculate text sizes for vertical centering
            let topText = "I snapped this 📸"
            let topFont = UIFont(name: "PlusJakartaSans-SemiBold", size: s(48)) ?? UIFont.systemFont(ofSize: s(48), weight: .semibold)
            let topAttributes: [NSAttributedString.Key: Any] = [
                .font: topFont,
                .foregroundColor: UIColor(red: 43/255, green: 43/255, blue: 43/255, alpha: 1.0),
                .kern: 0.3
            ]
            let topSize = (topText as NSString).size(withAttributes: topAttributes)

            let badgeText = "Top Visual Matches 🔥"
            let badgeFont = UIFont(name: "PlusJakartaSans-SemiBold", size: s(48)) ?? UIFont.systemFont(ofSize: s(48), weight: .semibold)
            let badgeAttributes: [NSAttributedString.Key: Any] = [
                .font: badgeFont,
                .foregroundColor: UIColor(red: 43/255, green: 43/255, blue: 43/255, alpha: 1.0),
                .kern: 0.3
            ]
            let badgeSize = (badgeText as NSString).size(withAttributes: badgeAttributes)

            // Calculate total content height to center vertically (matching Flutter's Column with center alignment)
            let totalContentHeight = s(60) + topSize.height + s(32) + heroHeight + s(32) + s(120) + s(24) + badgeSize.height + s(40) + s(480) + s(100) + s(64) + s(80)

            // Center content vertically in canvas
            let startY = (canvasHeight - totalContentHeight) / 2

            // "I snapped this 📸"
            var currentY: CGFloat = startY + s(60)
            (topText as NSString).draw(at: CGPoint(x: canvasWidth / 2 - topSize.width / 2, y: currentY), withAttributes: topAttributes)

            // Hero image with shadow
            currentY += topSize.height + s(32)
            let heroX = heroPadding
            let heroWidth = canvasWidth - heroPadding * 2
            let heroPath = UIBezierPath(roundedRect: CGRect(x: heroX, y: currentY, width: heroWidth, height: heroHeight), cornerRadius: heroRadius)
            ctx.saveGState()
            // Add shadow to hero image
            ctx.setShadow(offset: CGSize(width: 0, height: s(16)), blur: s(40), color: UIColor.black.withAlphaComponent(0.20).cgColor)
            heroPath.addClip()

            // Draw background
            UIColor(red: 245/255, green: 245/255, blue: 245/255, alpha: 1.0).setFill()
            heroPath.fill()

            // Calculate fitWidth rect for the image (fills width, centers vertically)
            let imageSize = heroImage.size
            let imageAspect = imageSize.width / imageSize.height
            let scaledHeight = heroWidth / imageAspect

            var drawRect = CGRect(x: heroX, y: currentY, width: heroWidth, height: scaledHeight)
            // Center vertically if image is smaller than container
            if scaledHeight < heroHeight {
                drawRect.origin.y += (heroHeight - scaledHeight) / 2
            }

            heroImage.draw(in: drawRect)
            ctx.restoreGState()

            // Arrow image
            currentY += heroHeight + s(32)
            if let arrowImage = UIImage(named: "arrow-share-card") {
                let arrowHeight = s(120)
                let arrowAspect = arrowImage.size.width / arrowImage.size.height
                let arrowWidth = arrowHeight * arrowAspect
                let arrowX = canvasWidth / 2 - arrowWidth / 2
                arrowImage.draw(in: CGRect(x: arrowX, y: currentY, width: arrowWidth, height: arrowHeight))
                currentY += arrowHeight
            }

            // "Top Visual Matches 🔥" text (clean, no container)
            currentY += s(24)
            (badgeText as NSString).draw(at: CGPoint(x: canvasWidth / 2 - badgeSize.width / 2, y: currentY), withAttributes: badgeAttributes)

            // Product images in Stack container (top 3 only)
            currentY += badgeSize.height + s(40)

            // Download product images first
            var productImages: [UIImage] = []
            for product in products.prefix(3) {
                if !product.image_url.isEmpty, let imageUrl = URL(string: product.image_url),
                   let imageData = try? Data(contentsOf: imageUrl), let productImage = UIImage(data: imageData) {
                    productImages.append(productImage)
                }
            }

            // Stack container for products - 480px height like Flutter
            let stackHeight = s(480)
            let productSize = s(390)  // Square like Flutter
            let productOverlap = s(170)
            let productRadius = s(68)
            let startX = (canvasWidth - s(680)) / 2

            // Draw products in stack (back to front for proper layering)
            for (index, productImage) in productImages.enumerated() {
                let productX = startX + (CGFloat(index) * productOverlap)
                let productY = currentY + (CGFloat(index) * s(30))

                ctx.saveGState()

                // Draw square product card with shadow
                let productRect = CGRect(x: productX, y: productY, width: productSize, height: productSize)
                let productPath = UIBezierPath(roundedRect: productRect, cornerRadius: productRadius)

                // Shadow matching Flutter elevation
                let elevation = 8.0 + (Double(index) * 3.0)
                ctx.setShadow(
                    offset: CGSize(width: 0, height: elevation),
                    blur: elevation * 2,
                    color: UIColor.black.withAlphaComponent(0.12).cgColor
                )

                // Fill path with white to create shadow
                UIColor.white.setFill()
                productPath.fill()

                // Clear shadow for image drawing
                ctx.setShadow(offset: .zero, blur: 0, color: nil)

                // Clip and draw image
                productPath.addClip()
                productImage.draw(in: productRect, blendMode: .normal, alpha: 1.0)

                ctx.restoreGState()
            }

            // Logo - 100px spacing after stack container + 80px bottom padding
            currentY += stackHeight + s(100)
            if let logoImage = UIImage(named: "logo") {
                let logoHeight = s(64)
                let logoAspect = logoImage.size.width / logoImage.size.height
                let logoWidth = logoHeight * logoAspect
                let logoX = canvasWidth / 2 - logoWidth / 2
                logoImage.draw(in: CGRect(x: logoX, y: currentY, width: logoWidth, height: logoHeight))
            }
        }
    }

    private func prepareAndPresentShare(loadingView: UIView) {
        // Get top 3 products for sharing - stacked display
        let topProducts = Array(detectionResults.prefix(3))
        let totalResults = detectionResults.count

        // Create share text
        let shareText = "Get Worthify and try for yourself: https://worthify.app"

        // Prepare items to share - build array with image first for proper iOS preview
        var itemsToShare: [Any] = []
        var shareImage: UIImage?
        var heroImage: UIImage?

        // Try to get the analyzed image
        if let imageData = analyzedImageData {
            shareLog("Attempting to create UIImage from \(imageData.count) bytes")
            if let image = UIImage(data: imageData) {
                heroImage = image
                shareLog("[SUCCESS] Successfully loaded analyzed image (size: \(image.size))")
            } else {
                shareLog("[ERROR] Failed to create UIImage from imageData")
            }
        } else {
            shareLog("[WARNING] analyzedImageData is nil - trying fallback")
        }

        // Fallback: Try to use the first product's image if original image unavailable
        if heroImage == nil && !detectionResults.isEmpty {
            if let firstProduct = detectionResults.first {
                let imageUrlString = firstProduct.image_url
                if !imageUrlString.isEmpty, let imageUrl = URL(string: imageUrlString) {
                    shareLog("Fallback: Attempting to download product image from: \(imageUrlString)")

                    // Download image synchronously (we're already in share flow)
                    if let imageData = try? Data(contentsOf: imageUrl),
                       let image = UIImage(data: imageData) {
                        heroImage = image
                        shareLog("[SUCCESS] Successfully loaded product image as fallback (size: \(image.size))")
                    } else {
                        shareLog("[ERROR] Failed to download fallback image")
                    }
                }
            }
        }

        // Generate share card if we have hero image and products
        if let hero = heroImage, !topProducts.isEmpty {
            shareLog("Generating share card with hero image and \(topProducts.count) products")
            if let card = generateShareCard(heroImage: hero, products: topProducts) {
                shareImage = card
                shareLog("[SUCCESS] Share card generated successfully (size: \(card.size))")
            } else {
                shareLog("[WARNING] Share card generation failed - using hero image as fallback")
                shareImage = hero
            }
        } else {
            shareLog("[WARNING] Cannot generate share card - missing hero image or products")
            shareImage = heroImage
        }

        // Build items array: image MUST be first for iOS preview thumbnail
        // iOS share sheet preview works best with file URLs, not UIImage objects
        if let image = shareImage {
            // Simple, clean filename
            let tempDir = FileManager.default.temporaryDirectory
            let imageFileName = "worthify_share_fashion.png"
            let imageURL = tempDir.appendingPathComponent(imageFileName)

            // Consistent subject for share sheet
            let subject = "Worthify Fashion Share"

            if let pngData = image.pngData() {
                do {
                    try pngData.write(to: imageURL)

                    // Use custom activity item source for rich metadata
                    let shareItem = WorthifyShareItem(
                        imageURL: imageURL,
                        title: subject,
                        subject: subject,
                        thumbnailImage: heroImage
                    )
                    itemsToShare.append(shareItem)
                    itemsToShare.append(shareText)
                    shareLog("[SUCCESS] Share items: [custom image item, text] - wrote temp file: \(imageFileName)")
                    shareLog("   Subject: \(subject)")
                } catch {
                    shareLog("[ERROR] Failed to write temp image file: \(error)")
                    // Fallback to UIImage if file write fails
                    itemsToShare.append(image)
                    itemsToShare.append(shareText)
                    shareLog("[WARNING] Fallback: using UIImage instead of file URL")
                }
            } else {
                shareLog("[ERROR] Failed to convert image to PNG")
                itemsToShare.append(image)
                itemsToShare.append(shareText)
                shareLog("[WARNING] Fallback: using UIImage instead of PNG")
            }
        } else {
            itemsToShare.append(shareText)
            shareLog("[WARNING] Share items: [text only] - no image available")
        }

        // Present iOS share sheet on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Remove loading view
            loadingView.removeFromSuperview()

            let activityVC = UIActivityViewController(activityItems: itemsToShare, applicationActivities: nil)

            // Exclude some activities that don't make sense
            activityVC.excludedActivityTypes = [
                .assignToContact,
                .addToReadingList,
                .openInIBooks
            ]

            // For iPad support
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = self.view
                popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }

            self.present(activityVC, animated: true) {
                shareLog("Share sheet presented successfully")
            }
        }
    }

    @objc private func doneButtonTapped() {
        shareLog("Done button tapped - closing extension")
        closeExtension()
    }

    // Public method that can be called from WebViewController to close the entire extension
    func closeExtension() {
        shareLog("Closing share extension")

        // Cancel any pending detection API call
        if let task = detectionTask {
            shareLog("Cancelling pending detection task")
            task.cancel()
            detectionTask = nil
        }

        // End extended execution
        endExtendedExecution()

        // Immediately hide default UI to prevent flash
        hideDefaultUI()

        // Clean up state
        loadingHideWorkItem?.cancel()
        loadingHideWorkItem = nil
        isShowingDetectionResults = false
        shouldAttemptDetection = false
        detectionResults.removeAll()
        filteredResults.removeAll()
        pendingImageData = nil
        pendingSharedFile = nil
        pendingImageUrl = nil

        clearSharedData()
        hideLoadingUI()

        // Log final memory usage
        let memoryMB = Double(getMemoryUsage()) / 1_048_576.0
        shareLog("Memory usage at cleanup: \(String(format: "%.1f", memoryMB)) MB")

        // Complete the extension request - this dismisses the share sheet and returns to source app
        let error = NSError(
            domain: "com.worthify.shareExtension",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "User cancelled"]
        )
        didCompleteRequest = true
        extensionContext?.cancelRequest(withError: error)
        shareLog("Extension closed - user returned to source app")
    }

    // Proceed with normal flow (save and redirect to app)
    private func proceedWithNormalFlow() {
        guard !hasQueuedRedirect else {
            shareLog("[WARNING] proceedWithNormalFlow called but redirect already queued")
            return
        }
        shareLog("[INFO] Proceeding with normal flow (detection failed or no results)")
        isShowingDetectionResults = false
        shouldAttemptDetection = false
        hasQueuedRedirect = true

        // NOW write the file to shared container so Flutter can pick it up
        if let data = pendingImageData, let file = pendingSharedFile {
            guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
                shareLog("[ERROR] Cannot get container URL for normal flow")
                saveAndRedirect()
                return
            }

            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let fileName = "instagram_image_\(timestamp)_fallback.jpg"
            let fileURL = containerURL.appendingPathComponent(fileName)

            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                try data.write(to: fileURL, options: .atomic)
                shareLog("[SAVED] NORMAL FLOW: Wrote file to shared container: \(fileURL.path)")

                // Update the shared file path
                var updatedFile = file
                updatedFile.path = fileURL.absoluteString

                // Save to UserDefaults
                let userDefaults = UserDefaults(suiteName: appGroupId)
                userDefaults?.set(toData(data: [updatedFile]), forKey: kUserDefaultsKey)
                userDefaults?.synchronize()
                shareLog("NORMAL FLOW: Saved file to UserDefaults")
            } catch {
                shareLog("ERROR writing file in normal flow: \(error.localizedDescription)")
            }
        }

        // Save platform type for Flutter to read
        if pendingPlatformType == nil {
            pendingPlatformType = inferredPlatformType
        }

        if let platformType = pendingPlatformType {
            let userDefaults = UserDefaults(suiteName: appGroupId)
            userDefaults?.set(platformType, forKey: "pending_platform_type")
            userDefaults?.synchronize()
            shareLog("Saved pending platform type: \(platformType)")
        }

        saveAndRedirect()
    }

    private func extractInstagramImageUrls(from html: String) -> [String] {
        var urls: [String] = []

        func cleaned(_ raw: String) -> String {
            return sanitizeInstagramURLString(raw)
        }

        func appendIfValid(_ candidate: String) {
            guard !candidate.isEmpty,
                  !candidate.contains("150x150"),
                  !candidate.contains("profile"),
                  !urls.contains(candidate) else { return }
            urls.append(candidate)
        }

        // Fast path: first ig_cache_key in JSON
        let cacheKeyPattern = "\"src\":\"(https:\\\\/\\\\/scontent[^\"]+?ig_cache_key[^\"]*)\""
        if let regex = try? NSRegularExpression(pattern: cacheKeyPattern, options: []) {
            let nsrange = NSRange(html.startIndex..<html.endIndex, in: html)
            if let match = regex.firstMatch(in: html, options: [], range: nsrange),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: html) {
                appendIfValid(cleaned(String(html[range])))
            }
        }

        if !urls.isEmpty { return urls }

        // Fast path: first display_url
        let displayPattern = "\"display_url\"\\s*:\\s*\"([^\"]+)\""
        if let regex = try? NSRegularExpression(pattern: displayPattern, options: []) {
            let nsrange = NSRange(html.startIndex..<html.endIndex, in: html)
            if let match = regex.firstMatch(in: html, options: [], range: nsrange),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: html) {
                appendIfValid(cleaned(String(html[range])))
            }
        }

        if !urls.isEmpty { return urls }

        // img src (limit to first 5) - only ig_cache_key to avoid low-quality/blocked URLs
        let imgPattern = "<img[^>]+src=\"([^\"]+)\""
        if let regex = try? NSRegularExpression(pattern: imgPattern, options: [.caseInsensitive]) {
            let nsrange = NSRange(html.startIndex..<html.endIndex, in: html)
            var count = 0
            regex.enumerateMatches(in: html, options: [], range: nsrange) { match, _, stop in
                guard count < 5,
                      let match = match,
                      match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: html) else { return }
                let candidate = cleaned(String(html[range]))
                if !candidate.contains("ig_cache_key") { return }
                appendIfValid(candidate)
                count += 1
                if count >= 5 { stop.pointee = true }
            }
        }

        if !urls.isEmpty { return urls }

        // og:image fallback
        let ogPattern = "<meta property=\"og:image\" content=\"([^\"]+)\""
        if let regex = try? NSRegularExpression(pattern: ogPattern, options: [.caseInsensitive]) {
            let nsrange = NSRange(html.startIndex..<html.endIndex, in: html)
            if let match = regex.firstMatch(in: html, options: [], range: nsrange),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: html) {
                appendIfValid(cleaned(String(html[range])))
            }
        }

        return urls
    }

    private func sanitizeInstagramURLString(_ value: String) -> String {
        var sanitized = value
        sanitized = sanitized.replacingOccurrences(of: "\\u0026", with: "&")
        sanitized = sanitized.replacingOccurrences(of: "\\/", with: "/")
        sanitized = sanitized.replacingOccurrences(of: "&amp;", with: "&")
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.contains("ig_cache_key") {
            return sanitized
        }
        return normalizeInstagramCdnUrl(sanitized)
    }

    private func normalizeInstagramCdnUrl(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else {
            return urlString
        }

        if var queryItems = components.percentEncodedQueryItems {
            for index in 0..<queryItems.count {
                if queryItems[index].name == "stp",
                let value = queryItems[index].value,
                value.contains("c") || value.contains("s640x640") {
                    queryItems[index].value = value
                        .replacingOccurrences(of: "c288.0.864.864a_", with: "")
                        .replacingOccurrences(of: "s640x640_", with: "")
                }
            }
            components.percentEncodedQueryItems = queryItems
        }

        let path = components.percentEncodedPath
        if let regex = try? NSRegularExpression(pattern: "_s\\d+x\\d+", options: []) {
            let range = NSRange(location: 0, length: path.count)
            if regex.firstMatch(in: path, options: [], range: range) != nil {
                let mutablePath = NSMutableString(string: path)
                regex.replaceMatches(in: mutablePath, options: [], range: range, withTemplate: "")
                components.percentEncodedPath = mutablePath as String
            }
        }

        return components.string ?? urlString
    }

    private func downloadInstagramImages(
        _ urls: [String],
        originalURL: String,
        session: URLSession,
        completion: @escaping (Result<[SharedMediaFile], Error>) -> Void
    ) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            completion(.failure(makeDownloadError("instagram", "Unable to resolve shared container URL")))
            return
        }

        var uniqueUrls: [String] = []
        for url in urls {
            let sanitized = sanitizeInstagramURLString(url)
            if !sanitized.isEmpty && !uniqueUrls.contains(sanitized) {
                uniqueUrls.append(sanitized)
                shareLog("Queueing Instagram image candidate: \(sanitized)")
            }
        }

        guard !uniqueUrls.isEmpty else {
            completion(.failure(makeDownloadError("instagram", "No valid Instagram image URLs after sanitization")))
            return
        }

        // 🆕 Only pick one image by index
        let userSelectedIndex = UserDefaults.standard.integer(forKey: "InstagramImageIndex") // default 0
        let safeIndex = min(max(userSelectedIndex, 0), uniqueUrls.count - 1)
        let selectedUrl = uniqueUrls[safeIndex]
        shareLog("[SUCCESS] Selected Instagram image index \(safeIndex) of \(uniqueUrls.count): \(selectedUrl)")

        // 🆕 Download just that one image
        downloadSingleImage(
            urlString: selectedUrl,
            originalURL: originalURL,
            containerURL: containerURL,
            session: session,
            index: safeIndex
        ) { result in
            switch result {
            case .success(let file):
                session.finishTasksAndInvalidate()
                if let file = file {
                    completion(.success([file]))
                } else {
                    completion(.success([]))
                }
            case .failure(let error):
                session.invalidateAndCancel()
                completion(.failure(error))
            }
        }
    }

    private func downloadSingleImage(
        urlString: String,
        originalURL: String,
        containerURL: URL,
        session: URLSession,
        index: Int,
        completion: @escaping (Result<SharedMediaFile?, Error>) -> Void
    ) {
        guard let url = URL(string: urlString) else {
            completion(.failure(makeDownloadError("instagram", "Invalid image URL: \(urlString)")))
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20.0
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.instagram.com/", forHTTPHeaderField: "Referer")

        shareLog("Downloading Instagram CDN image: \(urlString)")
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                completion(.failure(self.makeDownloadError("instagram", "Image download failed with status \(status)", code: status)))
                return
            }

            guard let data = data else {
                completion(.failure(self.makeDownloadError("instagram", "Image download returned no data")))
                return
            }

            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let fileName = "instagram_image_\(timestamp)_\(index).jpg"
            let fileURL = containerURL.appendingPathComponent(fileName)

            // User has already made their choice via the choice UI before download started
            // Just write the file and complete
            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                try data.write(to: fileURL, options: .atomic)
                shareLog("Saved Instagram image to shared container: \(fileURL.path)")

                let sharedFile = SharedMediaFile(
                    path: fileURL.absoluteString,
                    mimeType: "image/jpeg",
                    message: originalURL,
                    type: .image
                )

                completion(.success(sharedFile))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func downloadImageFromUrl(_ urlString: String, completion: @escaping (Result<[SharedMediaFile], Error>) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "com.worthify.shareExtension", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image URL"])))
            return
        }

        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            completion(.failure(NSError(domain: "com.worthify.shareExtension", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot access app group container"])))
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20.0
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                completion(.failure(NSError(domain: "com.worthify.shareExtension", code: status, userInfo: [NSLocalizedDescriptionKey: "Download failed with status \(status)"])))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: "com.worthify.shareExtension", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }

            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let fileName = "cached_instagram_image_\(timestamp).jpg"
            let fileURL = containerURL.appendingPathComponent(fileName)

            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                try data.write(to: fileURL, options: .atomic)

                let sharedFile = SharedMediaFile(
                    path: fileURL.absoluteString,
                    mimeType: "image/jpeg",
                    type: .image
                )

                completion(.success([sharedFile]))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func saveAndRedirect(message: String? = nil) {
        hasQueuedRedirect = true
        let userDefaults = UserDefaults(suiteName: appGroupId)
        userDefaults?.set(toData(data: sharedMedia), forKey: kUserDefaultsKey)
        let resolvedMessage = (message?.isEmpty ?? true) ? nil : message
        userDefaults?.set(resolvedMessage, forKey: kUserDefaultsMessageKey)
        let sessionId = UUID().uuidString
        currentProcessingSession = sessionId
        userDefaults?.set("pending", forKey: kProcessingStatusKey)
        userDefaults?.set(sessionId, forKey: kProcessingSessionKey)
        userDefaults?.synchronize()
        shareLog("Saved \(sharedMedia.count) item(s) to UserDefaults - redirecting (session: \(sessionId))")
        pendingPostMessage = nil
        redirectToHostApp(sessionId: sessionId)
    }

    private func enqueueRedirect(
        to url: URL,
        minimumDuration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        loadingHideWorkItem?.cancel()
        let elapsed = loadingShownAt.map { Date().timeIntervalSince($0) } ?? 0
        let delay = max(0, minimumDuration - elapsed)
        shareLog("Redirect scheduled in \(delay) seconds (elapsed: \(elapsed)) -> \(url.absoluteString)")

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.loadingHideWorkItem = nil
            self.performRedirect(to: url)
            completion()
        }

        loadingHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func redirectToHostApp(sessionId: String) {
        loadIds()
        guard let redirectURL = URL(string: "\(kSchemePrefix)-\(hostAppBundleIdentifier):share") else {
            shareLog("ERROR: Failed to build redirect URL")
            dismissWithError()
            return
        }

        let minimumDuration: TimeInterval = isPhotosSourceApp ? 2.0 : 0.5
        enqueueRedirect(to: redirectURL, minimumDuration: minimumDuration) { [weak self] in
            self?.finishExtensionRequest()
        }
    }


    private func performRedirect(to url: URL) {
        shareLog("Redirecting to host app with URL: \(url.absoluteString)")
        var responder: UIResponder? = self
        if #available(iOS 18.0, *) {
            while let current = responder {
                if let application = current as? UIApplication {
                    application.open(url, options: [:], completionHandler: nil)
                    break
                }
                responder = current.next
            }
        } else {
            let selectorOpenURL = sel_registerName("openURL:")
            while let current = responder {
                if current.responds(to: selectorOpenURL) {
                    _ = current.perform(selectorOpenURL, with: url)
                    break
                }
                responder = current.next
            }
        }
    }

    private func performRedirectFallback(to url: URL) -> Bool {
        shareLog("Using responder chain fallback to open URL")
        var responder: UIResponder? = self
        let selectorOpenURL = sel_registerName("openURL:")
        while let current = responder {
            if current.responds(to: selectorOpenURL) {
                _ = current.perform(selectorOpenURL, with: url)
                shareLog("Opened URL via responder chain")
                return true
            }
            responder = current.next
        }
        shareLog("Responder chain fallback could not find a responder to open URL")
        return false
    }

    private func finishExtensionRequest() {
        guard !didCompleteRequest else { return }
        didCompleteRequest = true
        DispatchQueue.main.async {
            self.endExtendedExecution()
            self.currentProcessingSession = nil
            if let defaults = UserDefaults(suiteName: self.appGroupId) {
                defaults.removeObject(forKey: kProcessingStatusKey)
                defaults.removeObject(forKey: kProcessingSessionKey)
                defaults.synchronize()
            }
            // DON'T hide loading UI - keep it visible to prevent flash of default UI
            // self.hideLoadingUI()
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            shareLog("Completed extension request")
        }
    }

    private func showConfigurationError() {
        shareLog("Showing configuration error")
        hideLoadingUI()
        stopStatusPolling()

        let alert = UIAlertController(
            title: "Configuration Required",
            message: "Please open the Worthify app first to complete setup. Instagram image detection requires API keys to be configured.",
            preferredStyle: .alert
        )

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            guard let self = self else { return }
            let error = NSError(
                domain: "com.worthify.shareExtension",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Configuration required"]
            )
            self.didCompleteRequest = true
            self.extensionContext?.cancelRequest(withError: error)
        }

        alert.addAction(cancelAction)
        present(alert, animated: true, completion: nil)
    }

    private func dismissWithError() {
        shareLog("ERROR: dismissWithError called")
        DispatchQueue.main.async {
            self.endExtendedExecution()
            self.hideLoadingUI()
            let alert = UIAlertController(title: "Error", message: "Error loading data", preferredStyle: .alert)
            let action = UIAlertAction(title: "OK", style: .cancel) { _ in
                self.dismiss(animated: true, completion: nil)
            }
            alert.addAction(action)
            self.present(alert, animated: true, completion: nil)
            self.didCompleteRequest = true
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    private func getFileName(from url: URL, type: SharedMediaType) -> String {
        var name = url.lastPathComponent
        if name.isEmpty {
            switch type {
            case .image: name = UUID().uuidString + ".png"
            case .video: name = UUID().uuidString + ".mp4"
            case .text:  name = UUID().uuidString + ".txt"
            default:     name = UUID().uuidString
            }
        }
        return name
    }

    private func writeTempFile(_ image: UIImage, to dstURL: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: dstURL.path) {
                try FileManager.default.removeItem(at: dstURL)
            }
            let pngData = image.pngData()
            try pngData?.write(to: dstURL)
            shareLog("writeTempFile succeeded at \(dstURL.path)")
            return true
        } catch {
            shareLog("ERROR: Cannot write temp file - \(error.localizedDescription)")
            return false
        }
    }

    private func copyFile(at srcURL: URL, to dstURL: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: dstURL.path) {
                try FileManager.default.removeItem(at: dstURL)
            }
            try FileManager.default.copyItem(at: srcURL, to: dstURL)
            return true
        } catch {
            shareLog("ERROR: Cannot copy item from \(srcURL) to \(dstURL.path): \(error.localizedDescription)")
            return false
        }
    }

    private func getVideoInfo(from url: URL) -> (thumbnail: String?, duration: Double)? {
        let asset = AVAsset(url: url)
        let duration = (CMTimeGetSeconds(asset.duration) * 1000).rounded()
        let thumbnailPath = getThumbnailPath(for: url)

        if FileManager.default.fileExists(atPath: thumbnailPath.path) {
            return (thumbnail: thumbnailPath.absoluteString, duration: duration)
        }

        var saved = false
        let assetImgGenerate = AVAssetImageGenerator(asset: asset)
        assetImgGenerate.appliesPreferredTrackTransform = true
        assetImgGenerate.maximumSize = CGSize(width: 360, height: 360)
        do {
            let img = try assetImgGenerate.copyCGImage(at: CMTimeMakeWithSeconds(0, preferredTimescale: 1), actualTime: nil)
            try UIImage(cgImage: img).pngData()?.write(to: thumbnailPath)
            saved = true
        } catch {
            shareLog("ERROR: Failed to generate video thumbnail - \(error.localizedDescription)")
            saved = false
        }

        return saved ? (thumbnail: thumbnailPath.absoluteString, duration: duration) : nil
    }

    private func getThumbnailPath(for url: URL) -> URL {
        let fileName = Data(url.lastPathComponent.utf8).base64EncodedString().replacingOccurrences(of: "==", with: "")
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)!
            .appendingPathComponent("\(fileName).jpg")
    }

    private func toData(data: [SharedMediaFile]) -> Data {
        (try? JSONEncoder().encode(data)) ?? Data()
    }

    private func enforcePhotosStatusIfNeeded() {
        guard isPhotosSourceApp else { return }
        stopStatusRotation()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.statusLabel?.text = self.photoImportStatusMessage
        }
    }

    private func setupLoadingUI() {
        let overlay = UIView(frame: view.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = UIColor.systemBackground

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false

        let activity = UIActivityIndicatorView(style: .large)
        activity.startAnimating()
        activityIndicator = activity
        stack.addArrangedSubview(activity)

        let status = UILabel()
        status.text = "Preparing analysis..."
        status.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        status.textAlignment = .center
        status.textColor = UIColor.label
        status.numberOfLines = 0  // Allow unlimited lines for long error messages
        stack.addArrangedSubview(status)
        statusLabel = status

        // Add shimmer animation to status label
        DispatchQueue.main.async { [weak self] in
            self?.addShimmerAnimation(to: status)
        }

        // Progress bar
        let progress = UIProgressView(progressViewStyle: .default)
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.progressTintColor = UIColor(red: 242/255, green: 0, blue: 60/255, alpha: 1.0)
        progress.trackTintColor = UIColor.systemGray5
        progress.layer.cornerRadius = 3
        progress.clipsToBounds = true
        progress.setProgress(0.0, animated: false)
        progressView = progress
        stack.addArrangedSubview(progress)

        NSLayoutConstraint.activate([
            progress.widthAnchor.constraint(equalToConstant: 180),
            progress.heightAnchor.constraint(equalToConstant: 6)
        ])

        overlay.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: overlay.trailingAnchor, constant: -32)
        ])

        overlay.tag = 9999 // Tag to identify our custom view
        view.addSubview(overlay)
        loadingView = overlay
        loadingShownAt = Date()

        if let header = addResultsHeaderIfNeeded() {
            overlay.bringSubviewToFront(header)
        }

        // Ensure default UI stays hidden
        hideDefaultUI()
    }

    private func showImagePreview(imageData: Data, resetOriginal: Bool = false) {
        shareLog("Showing image preview")

        // Mark that we're showing preview (and not results) so back button appears on the header
        isShowingResults = false
        isShowingPreview = true

        // Hide loading UI
        hideLoadingUI()

        // Store image data for later analysis and preserve the original for revert
        if resetOriginal || originalImageData == nil {
            originalImageData = imageData
        }
        analyzedImageData = imageData

        // Create preview overlay
        let overlay = UIView(frame: view.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = UIColor.systemBackground
        overlay.tag = 9997 // Tag to identify preview overlay

        // Image view with aspect-fill to cover entire rectangle
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 16
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tag = 9998 // Tag to identify image view for later updates

        if let image = UIImage(data: imageData) {
            imageView.image = image
            shareLog("Preview image loaded - size: \(image.size)")
        } else {
            shareLog("ERROR: Failed to create UIImage from imageData")
            dismissWithError()
            return
        }

        // Store reference for later updates
        previewImageView = imageView
        overlay.addSubview(imageView)

        // Revert crop button (appears after a crop)
        revertCropButton?.removeFromSuperview()
        let revertButton = UIButton(type: .system)
        revertButton.translatesAutoresizingMaskIntoConstraints = false
        let revertConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold, scale: .small)
        // Match the crop tool's reset icon for consistency with TOCropViewController.
        let revertImage = UIImage(systemName: "arrow.counterclockwise", withConfiguration: revertConfig)
        revertButton.setImage(revertImage, for: .normal)
        revertButton.setPreferredSymbolConfiguration(revertConfig, forImageIn: .normal)
        revertButton.imageEdgeInsets = UIEdgeInsets(top: -1, left: 0, bottom: 1, right: 0)
        revertButton.tintColor = .white
        revertButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        revertButton.layer.cornerRadius = 20
        revertButton.layer.masksToBounds = true
        revertButton.addTarget(self, action: #selector(revertCropTapped), for: .touchUpInside)
        revertButton.accessibilityLabel = "Revert to original image"
        overlay.addSubview(revertButton)
        revertCropButton = revertButton

        // "Crop" button (secondary style - white with border)
        let cropButton = UIButton(type: .system)
        cropButton.setTitle("Crop", for: .normal)
        cropButton.titleLabel?.font = UIFont(name: "PlusJakartaSans-Bold", size: 16)
            ?? .systemFont(ofSize: 16, weight: .bold)
        cropButton.backgroundColor = .white
        cropButton.setTitleColor(UIColor(red: 28/255, green: 28/255, blue: 37/255, alpha: 1.0), for: .normal)
        cropButton.layer.borderWidth = 1.5
        cropButton.layer.borderColor = UIColor(red: 229/255, green: 231/255, blue: 235/255, alpha: 1.0).cgColor
        cropButton.layer.cornerRadius = 28
        cropButton.translatesAutoresizingMaskIntoConstraints = false
        cropButton.addTarget(self, action: #selector(cropButtonTapped), for: .touchUpInside)

        overlay.addSubview(cropButton)

        // "Analyze" button at bottom (primary red style)
        let analyzeButton = UIButton(type: .system)
        analyzeButton.setTitle("Analyze", for: .normal)
        analyzeButton.titleLabel?.font = UIFont(name: "PlusJakartaSans-Bold", size: 16)
            ?? .systemFont(ofSize: 16, weight: .bold)
        analyzeButton.backgroundColor = UIColor(red: 242/255, green: 0, blue: 60/255, alpha: 1.0)
        analyzeButton.setTitleColor(.white, for: .normal)
        analyzeButton.layer.cornerRadius = 28
        analyzeButton.translatesAutoresizingMaskIntoConstraints = false
        analyzeButton.addTarget(self, action: #selector(analyzeFromPreviewTapped), for: .touchUpInside)

        overlay.addSubview(analyzeButton)

        // Layout constraints
        NSLayoutConstraint.activate([
            // Image takes most of the space, with padding for header (logo + cancel button)
            imageView.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 70),
            imageView.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 20),
            imageView.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -20),
            imageView.bottomAnchor.constraint(equalTo: cropButton.topAnchor, constant: -16),

            // Revert button anchored to image corner
            revertButton.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -12),
            revertButton.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -12),
            revertButton.widthAnchor.constraint(equalToConstant: 40),
            revertButton.heightAnchor.constraint(equalToConstant: 40),

            // Crop button above analyze button
            cropButton.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 32),
            cropButton.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -32),
            cropButton.bottomAnchor.constraint(equalTo: analyzeButton.topAnchor, constant: -12),
            cropButton.heightAnchor.constraint(equalToConstant: 56),

            // Analyze button at bottom
            analyzeButton.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 32),
            analyzeButton.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -32),
            analyzeButton.bottomAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            analyzeButton.heightAnchor.constraint(equalToConstant: 56),
        ])

        view.addSubview(overlay)
        loadingView = overlay

        if let header = addResultsHeaderIfNeeded() {
            overlay.bringSubviewToFront(header)
        }
        if let revertButton = revertCropButton {
            overlay.bringSubviewToFront(revertButton)
        }

        hideDefaultUI()
        updateRevertButtonVisibility()
        shareLog("Image preview displayed")
    }

    private func updateRevertButtonVisibility() {
        let shouldShow = (originalImageData != nil) &&
            (analyzedImageData != nil) &&
            (analyzedImageData != originalImageData)
        revertCropButton?.isHidden = !shouldShow
        revertCropButton?.isEnabled = shouldShow
    }

    @objc private func revertCropTapped() {
        shareLog("Revert crop tapped")

        guard let originalData = originalImageData else {
            shareLog("ERROR: No original image available to revert")
            return
        }

        // Update stored data back to original
        analyzedImageData = originalData

        if let image = UIImage(data: originalData), let previewImageView = previewImageView {
            UIView.transition(with: previewImageView, duration: 0.25, options: .transitionCrossDissolve, animations: {
                previewImageView.image = image
            }, completion: nil)
        }

        // Light feedback so the user knows we reverted
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        updateRevertButtonVisibility()
    }

    @objc private func analyzeFromPreviewTapped() {
        shareLog("Analyze button tapped from preview")

        // Check if user is authenticated first
        if !isUserAuthenticated() {
            shareLog("User not authenticated - showing login required modal")
            showLoginRequiredModal()
            return
        }

        // Check if user has available credits
        if !hasAvailableCredits() {
            shareLog("Local credits unavailable - attempting server verification before blocking preview analysis")
            resolveCreditAccess { [weak self] hasCredits in
                guard let self = self else { return }
                if hasCredits {
                    shareLog("Server verification succeeded - retrying preview analysis")
                    self.analyzeFromPreviewTapped()
                } else {
                    shareLog("User has no credits - showing out of credits modal")
                    self.showOutOfCreditsModal()
                }
            }
            return
        }

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // Leave preview state before showing the loading UI
        isShowingPreview = false

        // Get the stored image data
        guard let imageData = analyzedImageData else {
            shareLog("ERROR: No image data available for analysis")
            dismissWithError()
            return
        }

        // Replace preview overlay with the standard loading UI used during detection
        hideLoadingUI()
        updateProcessingStatus("processing")
        setupLoadingUI()

        // Start detection (cache checking disabled)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stopStatusPolling()
            self.startSmoothProgress()

            // Unified progress profile for all platforms
            self.progressRateMultiplier = 0.28  // Reach 95% in ~6-7 seconds
            self.targetProgress = 0.95  // Cap at 95% until API responds

            let rotatingMessages = [
                "Analyzing look...",
                "Finding similar items...",
                "Checking retailers...",
                "Finalizing results..."
            ]
            self.startStatusRotation(messages: rotatingMessages, interval: 2.0, stopAtLast: true)
        }

        shareLog("Starting detection from preview with \(imageData.count) bytes")
        uploadAndDetect(imageData: imageData)
    }

    private func fadeInCropToolbarButtons(_ cropViewController: TOCropViewController) {
        UIView.animate(withDuration: 0.3, delay: 0.1, options: .curveEaseOut, animations: {
            cropViewController.toolbar.subviews.forEach { $0.alpha = 1.0 }
        }, completion: nil)
    }

    @objc private func cropButtonTapped() {
        shareLog("Crop button tapped")

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // Get the current image
        guard let imageData = analyzedImageData,
              let image = UIImage(data: imageData) else {
            shareLog("ERROR: No image available for cropping")
            return
        }

        // Present crop view controller with proper layout handling
        let cropViewController = TOCropViewController(image: image)
        cropViewController.delegate = self
        cropViewController.aspectRatioPreset = .presetSquare
        cropViewController.aspectRatioLockEnabled = false
        cropViewController.resetAspectRatioEnabled = true
        cropViewController.aspectRatioPickerButtonHidden = false
        cropViewController.rotateButtonsHidden = false
        cropViewController.rotateClockwiseButtonHidden = true
        cropViewController.toolbar.clampButtonHidden = true

        // Hide toolbar buttons initially to prevent flash - they will fade in
        cropViewController.toolbar.doneTextButton.alpha = 0
        cropViewController.toolbar.cancelTextButton.alpha = 0
        cropViewController.toolbar.subviews.forEach { $0.alpha = 0 }

        // Set toolbar buttons tint to white for better visibility
        let worthifyRed = UIColor(red: 242/255, green: 0, blue: 60/255, alpha: 1.0)
        cropViewController.toolbar.tintColor = .white
        cropViewController.toolbar.doneTextButton.setTitleColor(worthifyRed, for: .normal)
        cropViewController.toolbar.doneTextButton.setTitleColor(worthifyRed.withAlphaComponent(0.8), for: .highlighted)
        // Reset to default sizing: no extra padding or scaling tweaks on the toolbar buttons.
        cropViewController.toolbar.doneTextButton.contentEdgeInsets = .zero
        cropViewController.toolbar.cancelTextButton.contentEdgeInsets = .zero
        cropViewController.toolbar.doneTextButton.titleLabel?.adjustsFontSizeToFitWidth = false
        cropViewController.toolbar.cancelTextButton.titleLabel?.adjustsFontSizeToFitWidth = false

        // Wrap in navigation controller for proper safe area handling in Share Extension
        let navController = UINavigationController(rootViewController: cropViewController)
        navController.modalPresentationStyle = .fullScreen
        navController.isNavigationBarHidden = true

        shareLog("Presenting crop view controller")
        present(navController, animated: true) {
            // Fade in the built-in toolbar buttons (Done/Cancel + tools)
            self.fadeInCropToolbarButtons(cropViewController)
        }
    }

    private func startSmoothProgress() {
        stopSmoothProgress()

        currentProgress = 0.0
        targetProgress = 0.0

        DispatchQueue.main.async { [weak self] in
            self?.progressView?.setProgress(0.0, animated: false)

            self?.progressTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
                guard let self = self else { return }

                // Smoothly increment toward target with adaptive speed
                if self.currentProgress < self.targetProgress {
                    let remaining = max(self.targetProgress - self.currentProgress, 0)
                    // More linear progression - reduced adaptive coefficient for slower start
                    let baseIncrement: Float = max(remaining * 0.05 * self.progressRateMultiplier,
                                                   0.004 * self.progressRateMultiplier)
                    // Slow slightly once we cross 70% to stretch the final climb
                    let slowdownFactor: Float = self.currentProgress >= 0.70 ? 0.7 : 1.0
                    let increment = baseIncrement * slowdownFactor
                    let cappedIncrement = min(increment, 0.02) // prevent huge jumps
                    self.currentProgress = min(self.currentProgress + cappedIncrement, self.targetProgress)
                    self.progressView?.setProgress(self.currentProgress, animated: true)
                }
            }
        }
    }

    private func stopSmoothProgress() {
        progressTimer?.invalidate()
        progressTimer = nil
        stopStatusRotation()
    }

    /// Waits for progress bar to reach 100% before calling completion
    private func waitForProgressCompletion(completion: @escaping () -> Void) {
        let startTime = Date()
        let maxWaitTime: TimeInterval = 5.0  // Safety timeout

        // Poll every 0.1 seconds to check if progress reached target
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                completion()
                return
            }

            // Check if progress bar reached 99% or higher (close enough to 100%)
            if self.currentProgress >= 0.99 {
                timer.invalidate()
                shareLog("Progress bar reached 100% - showing results")
                completion()
                return
            }

            // Safety timeout - don't wait forever
            if Date().timeIntervalSince(startTime) > maxWaitTime {
                timer.invalidate()
                shareLog("Progress completion timeout - showing results anyway")
                completion()
                return
            }
        }
    }

    private func updateProgress(_ progress: Float, status: String) {
        // Never regress progress; only move forward
        targetProgress = max(targetProgress, progress)

        if isPhotosSourceApp {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.statusLabel?.text = self.photoImportStatusMessage
                shareLog("Progress: \(Int(progress * 100))% - \(status)")
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.statusLabel?.text = status
            shareLog("Progress: \(Int(progress * 100))% - \(status)")
        }
    }

    // Start rotating through multiple status messages
    private func startStatusRotation(messages: [String], interval: TimeInterval = 2.5, stopAtLast: Bool = false) {
        guard !messages.isEmpty else { return }

        if isPhotosSourceApp {
            enforcePhotosStatusIfNeeded()
            return
        }

        stopStatusRotation()

        currentStatusMessages = messages
        currentStatusIndex = 0

        // Set first message immediately
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.statusLabel?.text = messages[0]
            shareLog("Status: \(messages[0])")
        }

        // Only start timer if we have multiple messages
        guard messages.count > 1 else { return }

        DispatchQueue.main.async { [weak self] in
            self?.statusRotationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                guard let timer = self.statusRotationTimer, timer.isValid else {
                    self.stopStatusRotation()
                    return
                }

                // Safety check: Stop if messages array became empty
                guard !self.currentStatusMessages.isEmpty else {
                    self.stopStatusRotation()
                    return
                }

                // Move to next message
                if stopAtLast && self.currentStatusIndex >= self.currentStatusMessages.count - 1 {
                    // Already at last message, stop rotation
                    self.stopStatusRotation()
                    return
                }

                self.currentStatusIndex = stopAtLast
                    ? self.currentStatusIndex + 1
                    : (self.currentStatusIndex + 1) % self.currentStatusMessages.count

                // Safety check: Ensure index is within bounds
                guard self.currentStatusIndex < self.currentStatusMessages.count else {
                    shareLog("Status index out of bounds - stopping rotation")
                    self.stopStatusRotation()
                    return
                }

                let message = self.currentStatusMessages[self.currentStatusIndex]

                // Animate the text change
                UIView.transition(with: self.statusLabel ?? UILabel(),
                                duration: 0.3,
                                options: .transitionCrossDissolve,
                                animations: {
                    self.statusLabel?.text = message
                }, completion: nil)

                shareLog("Status rotated: \(message)")
            }
        }
    }

    private func stopStatusRotation() {
        statusRotationTimer?.invalidate()
        statusRotationTimer = nil
        currentStatusMessages.removeAll()
        currentStatusIndex = 0
    }

    private func startStatusPolling() {
        guard !appGroupId.isEmpty else { return }
        stopStatusPolling()

        statusPollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.refreshStatusLabel()
        }
        statusPollTimer?.tolerance = 0.1
        if let timer = statusPollTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        refreshStatusLabel()
    }

    private func stopStatusPolling() {
        statusPollTimer?.invalidate()
        statusPollTimer = nil
    }

    private func addShimmerAnimation(to label: UILabel) {
        // Remove any existing animations
        label.layer.removeAnimation(forKey: "shimmerAnimation")

        // Create a subtle pulsing opacity animation - similar to Claude's "breathing" text effect
        let pulseAnimation = CABasicAnimation(keyPath: "opacity")
        pulseAnimation.fromValue = 0.5
        pulseAnimation.toValue = 1.0
        pulseAnimation.duration = 1.5
        pulseAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulseAnimation.autoreverses = true
        pulseAnimation.repeatCount = .infinity

        label.layer.add(pulseAnimation, forKey: "shimmerAnimation")
    }

    private func refreshStatusLabel() {
        // Don't override the text - just ensure the shimmer animation is running
        // The actual text is managed by the status rotation system
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let label = self.statusLabel else { return }

            // Ensure shimmer animation is active
            if label.layer.animation(forKey: "shimmerAnimation") == nil {
                self.addShimmerAnimation(to: label)
            }
        }
    }

    private func hideLoadingUI() {
        loadingHideWorkItem?.cancel()
        loadingHideWorkItem = nil
        stopSmoothProgress()
        loadingView?.removeFromSuperview()
        loadingView = nil
        resultsHeaderContainerView?.removeFromSuperview()
        resultsHeaderContainerView = nil
        removeResultsHeader()
        activityIndicator?.stopAnimating()
        activityIndicator = nil
        stopStatusPolling()
        statusLabel = nil
        progressView = nil
    }

    // MARK: - Authentication Check

    private func isUserAuthenticated() -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            shareLog("[ERROR] Cannot access UserDefaults for authentication check")
            return false
        }

        // Check for our custom authentication flag
        // The main app will set this when user logs in
        let isAuthenticated = defaults.bool(forKey: "user_authenticated")

        if isAuthenticated {
            shareLog("[SUCCESS] User authenticated")
        } else {
            shareLog("[INFO] User not authenticated")
        }

        return isAuthenticated
    }

    private func hasAvailableCredits() -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            shareLog("[ERROR] Cannot access UserDefaults for credit check")
            return false
        }

        let availableCredits = defaults.integer(forKey: "user_available_credits")

        if availableCredits > 0 {
            shareLog("[SUCCESS] User has \(availableCredits) credits available")
            return true
        }

        shareLog("[INFO] User has 0 credits available")
        return false
    }

    private func resolveCreditAccess(completion: @escaping (Bool) -> Void) {
        if hasAvailableCredits() {
            completion(true)
            return
        }

        refreshCreditsFromServerIfNeeded(completion: completion)
    }

    private func refreshCreditsFromServerIfNeeded(completion: @escaping (Bool) -> Void) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            shareLog("[Credits] Cannot refresh from server - UserDefaults unavailable")
            DispatchQueue.main.async { completion(false) }
            return
        }

        let cachedCredits = defaults.integer(forKey: "user_available_credits")

        // Only attempt network fallback when local credits are exhausted.
        guard cachedCredits <= 0 else {
            DispatchQueue.main.async { completion(true) }
            return
        }

        guard let supabaseUrl = defaults.string(forKey: kSupabaseUrlKey),
              let supabaseAnonKey = defaults.string(forKey: kSupabaseAnonKeyKey) else {
            shareLog("[Credits] Cannot refresh from server - Supabase config missing")
            DispatchQueue.main.async { completion(false) }
            return
        }

        guard let accessToken = defaults.string(forKey: kSupabaseAccessTokenKey),
              !accessToken.isEmpty else {
            shareLog("[Credits] Cannot refresh from server - access token missing")
            DispatchQueue.main.async { completion(false) }
            return
        }

        let userId = getUserId()
        guard userId != "anonymous" else {
            shareLog("[Credits] Cannot refresh from server - anonymous user")
            DispatchQueue.main.async { completion(false) }
            return
        }

        var components = URLComponents(string: "\(supabaseUrl)/rest/v1/users")
        components?.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(userId)"),
            URLQueryItem(name: "select", value: "paid_credits_remaining,subscription_status,is_trial"),
            URLQueryItem(name: "limit", value: "1")
        ]

        guard let url = components?.url else {
            shareLog("[Credits] Cannot refresh from server - invalid users URL")
            DispatchQueue.main.async { completion(false) }
            return
        }

        shareLog("[Credits] Refreshing credit snapshot from Supabase")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            if let error = error {
                shareLog("[Credits] Server refresh failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(false) }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                shareLog("[Credits] Server refresh failed: invalid response")
                DispatchQueue.main.async { completion(false) }
                return
            }

            guard httpResponse.statusCode == 200, let data = data else {
                shareLog("[Credits] Server refresh failed with status \(httpResponse.statusCode)")
                DispatchQueue.main.async { completion(false) }
                return
            }

            do {
                guard
                    let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                    let row = rows.first
                else {
                    shareLog("[Credits] Server refresh returned empty user payload")
                    DispatchQueue.main.async { completion(false) }
                    return
                }

                let refreshedCredits = self.intFromAny(row["paid_credits_remaining"]) ?? 0
                let subscriptionStatus = (row["subscription_status"] as? String ?? "free").lowercased()
                let isTrial = row["is_trial"] as? Bool ?? false
                let refreshedHasActiveSubscription = subscriptionStatus == "active" || isTrial

                DispatchQueue.main.async {
                    defaults.set(refreshedCredits, forKey: "user_available_credits")
                    defaults.set(refreshedHasActiveSubscription, forKey: "user_has_active_subscription")
                    defaults.synchronize()

                    shareLog("[Credits] Server refresh success - credits: \(refreshedCredits), active: \(refreshedHasActiveSubscription)")
                    completion(refreshedCredits > 0)
                }
            } catch {
                shareLog("[Credits] Server refresh parse error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(false) }
            }
        }.resume()
    }

    private func intFromAny(_ value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let numberValue = value as? NSNumber {
            return numberValue.intValue
        }
        if let stringValue = value as? String {
            return Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private func maybeShowPostAnalysisOutOfCreditsModal() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.maybeShowPostAnalysisOutOfCreditsModal()
            }
            return
        }

        guard shouldShowOutOfCreditsAfterAnalysis else { return }
        guard !hasShownPostAnalysisOutOfCreditsModal else { return }
        guard !didCompleteRequest, !hasQueuedRedirect else { return }
        guard isShowingDetectionResults || isShowingResults else { return }

        hasShownPostAnalysisOutOfCreditsModal = true
        shouldShowOutOfCreditsAfterAnalysis = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self else { return }
            guard !self.didCompleteRequest, !self.hasQueuedRedirect else { return }
            shareLog("[Credits] Showing out of credits modal after completed analysis")
            self.showOutOfCreditsModal()
        }
    }

    private func createBlockingModalOverlay() -> UIView {
        // Ensure previous interactive overlays are gone before presenting a blocking modal.
        hideLoadingUI()
        view.subviews
            .filter { $0.tag == 9999 || $0.tag == 9997 }
            .forEach { $0.removeFromSuperview() }

        let overlay = UIView(frame: view.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = UIColor.systemBackground
        overlay.tag = 9999
        overlay.isUserInteractionEnabled = true
        view.addSubview(overlay)
        view.bringSubviewToFront(overlay)
        loadingView = overlay
        hideDefaultUI()
        view.bringSubviewToFront(overlay)
        return overlay
    }

    private func showLoginRequiredModal() {
        // Haptic feedback
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.warning)

        let overlay = createBlockingModalOverlay()

        // Add logo and cancel button at top
        let headerContainer = UIView()
        headerContainer.translatesAutoresizingMaskIntoConstraints = false

        let logo = UIImageView(image: UIImage(named: "logo"))
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 16)
        cancelButton.addTarget(self, action: #selector(cancelLoginRequiredTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        headerContainer.addSubview(logo)
        headerContainer.addSubview(cancelButton)

        // Container for centered content
        let contentContainer = UIView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        // Title
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Sign in required"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.textColor = .label

        // Message
        let messageLabel = UILabel()
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.text = "Please sign in to Worthify to use the share extension"
        messageLabel.font = .systemFont(ofSize: 15, weight: .regular)
        messageLabel.textAlignment = .center
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0

        // Buttons stack
        let buttonStack = UIStackView()
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .vertical
        buttonStack.spacing = 16
        buttonStack.distribution = .fillEqually

        // "Open Worthify" button (pill-shaped)
        let openAppButton = UIButton(type: .system)
        openAppButton.setTitle("Open Worthify", for: .normal)
        openAppButton.titleLabel?.font = UIFont(name: "PlusJakartaSans-Bold", size: 16)
            ?? .systemFont(ofSize: 16, weight: .bold)
        openAppButton.setTitleColor(.white, for: .normal)
        openAppButton.backgroundColor = UIColor(red: 242/255, green: 0, blue: 60/255, alpha: 1.0)
        openAppButton.layer.cornerRadius = 28
        openAppButton.addTarget(self, action: #selector(openAppTapped), for: .touchUpInside)

        // "Cancel" button (pill-shaped with border)
        let cancelActionButton = UIButton(type: .system)
        cancelActionButton.setTitle("Cancel", for: .normal)
        cancelActionButton.titleLabel?.font = UIFont(name: "PlusJakartaSans-Bold", size: 16)
            ?? .systemFont(ofSize: 16, weight: .bold)
        cancelActionButton.setTitleColor(.black, for: .normal)
        cancelActionButton.backgroundColor = .clear
        cancelActionButton.layer.cornerRadius = 28
        cancelActionButton.layer.borderWidth = 1.5
        cancelActionButton.layer.borderColor = UIColor(red: 209/255, green: 213/255, blue: 219/255, alpha: 1.0).cgColor
        cancelActionButton.addTarget(self, action: #selector(cancelLoginRequiredTapped), for: .touchUpInside)

        // Add all subviews to button stack
        buttonStack.addArrangedSubview(openAppButton)
        buttonStack.addArrangedSubview(cancelActionButton)

        // Add all subviews to content container
        contentContainer.addSubview(titleLabel)
        contentContainer.addSubview(messageLabel)
        contentContainer.addSubview(buttonStack)

        // Add all subviews to overlay
        overlay.addSubview(headerContainer)
        overlay.addSubview(contentContainer)

        // Layout constraints
        NSLayoutConstraint.activate([
            // Header container
            headerContainer.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: -5),
            headerContainer.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -16),
            headerContainer.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 14),
            headerContainer.heightAnchor.constraint(equalToConstant: 48),

            // Logo - centered with offset
            logo.centerXAnchor.constraint(equalTo: headerContainer.centerXAnchor, constant: 12),
            logo.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            logo.heightAnchor.constraint(equalToConstant: 28),
            logo.widthAnchor.constraint(equalToConstant: 132),

            // Cancel button in header
            cancelButton.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            cancelButton.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),

            // Center content container
            contentContainer.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            contentContainer.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 32),
            contentContainer.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -32),

            // Title
            titleLabel.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),

            // Message
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),

            // Button stack
            buttonStack.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 32),
            buttonStack.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            // Button heights
            openAppButton.heightAnchor.constraint(equalToConstant: 56),
            cancelActionButton.heightAnchor.constraint(equalToConstant: 56),
        ])

        shareLog("[SUCCESS] Login required modal displayed")
    }

    private func showOutOfCreditsModal() {
        // Haptic feedback
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.warning)

        // Freeze interactive state while this blocking modal is visible.
        shouldAttemptDetection = false
        deferredShareAction = nil
        isShowingPreview = false
        isShowingResults = false
        isShowingDetectionResults = false

        let overlay = createBlockingModalOverlay()

        // Add logo and cancel button at top
        let headerContainer = UIView()
        headerContainer.translatesAutoresizingMaskIntoConstraints = false

        let logo = UIImageView(image: UIImage(named: "logo"))
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 16)
        cancelButton.addTarget(self, action: #selector(cancelOutOfCreditsTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        headerContainer.addSubview(logo)
        headerContainer.addSubview(cancelButton)

        // Container for centered content
        let contentContainer = UIView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        // Title
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Out of credits"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.textColor = .label

        // Message
        let messageLabel = UILabel()
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.text = "You've used all your credits. Upgrade to get 100 credits/month and continue discovering fashion."
        messageLabel.font = .systemFont(ofSize: 15, weight: .regular)
        messageLabel.textAlignment = .center
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0

        // Buttons stack
        let buttonStack = UIStackView()
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .vertical
        buttonStack.spacing = 16
        buttonStack.distribution = .fillEqually

        // "Open Worthify" button (pill-shaped)
        let openAppButton = UIButton(type: .system)
        openAppButton.setTitle("Open Worthify", for: .normal)
        openAppButton.titleLabel?.font = UIFont(name: "PlusJakartaSans-Bold", size: 16)
            ?? .systemFont(ofSize: 16, weight: .bold)
        openAppButton.setTitleColor(.white, for: .normal)
        openAppButton.backgroundColor = UIColor(red: 242/255, green: 0, blue: 60/255, alpha: 1.0)
        openAppButton.layer.cornerRadius = 28
        openAppButton.addTarget(self, action: #selector(openAppFromCreditsModalTapped), for: .touchUpInside)

        // "Cancel" button (pill-shaped with border)
        let cancelActionButton = UIButton(type: .system)
        cancelActionButton.setTitle("Cancel", for: .normal)
        cancelActionButton.titleLabel?.font = UIFont(name: "PlusJakartaSans-Bold", size: 16)
            ?? .systemFont(ofSize: 16, weight: .bold)
        cancelActionButton.setTitleColor(.black, for: .normal)
        cancelActionButton.backgroundColor = .clear
        cancelActionButton.layer.cornerRadius = 28
        cancelActionButton.layer.borderWidth = 1.5
        cancelActionButton.layer.borderColor = UIColor(red: 209/255, green: 213/255, blue: 219/255, alpha: 1.0).cgColor
        cancelActionButton.addTarget(self, action: #selector(cancelOutOfCreditsTapped), for: .touchUpInside)

        buttonStack.addArrangedSubview(openAppButton)
        buttonStack.addArrangedSubview(cancelActionButton)

        contentContainer.addSubview(titleLabel)
        contentContainer.addSubview(messageLabel)
        contentContainer.addSubview(buttonStack)

        overlay.addSubview(headerContainer)
        overlay.addSubview(contentContainer)

        // Layout constraints
        NSLayoutConstraint.activate([
            // Header container
            headerContainer.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: -5),
            headerContainer.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -16),
            headerContainer.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 14),
            headerContainer.heightAnchor.constraint(equalToConstant: 48),

            // Logo - centered with offset
            logo.centerXAnchor.constraint(equalTo: headerContainer.centerXAnchor, constant: 12),
            logo.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            logo.heightAnchor.constraint(equalToConstant: 28),
            logo.widthAnchor.constraint(equalToConstant: 132),

            // Cancel button
            cancelButton.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            cancelButton.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),

            // Center content container
            contentContainer.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            contentContainer.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 32),
            contentContainer.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -32),

            // Title
            titleLabel.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),

            // Message
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),

            // Button stack
            buttonStack.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 32),
            buttonStack.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            // Button heights
            openAppButton.heightAnchor.constraint(equalToConstant: 56),
            cancelActionButton.heightAnchor.constraint(equalToConstant: 56),
        ])

        shareLog("[SUCCESS] Out of credits modal displayed")
    }

    @objc private func openAppFromCreditsModalTapped() {
        shareLog("Open App tapped from credits modal")

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // Set flag to tell Flutter to navigate to paywall/subscription page
        if let defaults = UserDefaults(suiteName: appGroupId) {
            defaults.set(true, forKey: "needs_credits_from_share_extension")
            defaults.synchronize()
            shareLog("Set needs_credits_from_share_extension flag")
        }

        // Open app to paywall/subscription page
        loadIds()
        guard let url = URL(string: "\(kSchemePrefix)-\(hostAppBundleIdentifier):share") else {
            shareLog("ERROR: Failed to create app URL")
            cancelOutOfCreditsTapped()
            return
        }

        // Use responder chain to open the app (same as working Analyze in app flow)
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.open(url, options: [:]) { success in
                    if success {
                        shareLog("[SUCCESS] Opened Worthify from credits modal")
                    } else {
                        shareLog("[ERROR] Failed to open Worthify from credits modal")
                    }
                }
                break
            }
            responder = responder?.next
        }

        finishExtensionRequest()
    }

    @objc private func cancelOutOfCreditsTapped() {
        shareLog("Cancel tapped from credits modal")

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        finishExtensionRequest()
    }

    @objc private func openAppTapped() {
        shareLog("Open App tapped from login modal")

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // Save a flag that user needs to sign in
        if let defaults = UserDefaults(suiteName: appGroupId) {
            defaults.set(true, forKey: "needs_signin_from_share_extension")
            defaults.synchronize()
        }

        // Use the same URL scheme that works for "Analyze in app"
        loadIds()
        guard let url = URL(string: "\(kSchemePrefix)-\(hostAppBundleIdentifier):share") else {
            shareLog("ERROR: Failed to create app URL")
            cancelLoginRequiredTapped()
            return
        }

        // Use responder chain to open the app (same as working Analyze in app flow)
        shareLog("Opening app with URL: \(url.absoluteString)")

        var responder: UIResponder? = self
        if #available(iOS 18.0, *) {
            while let current = responder {
                if let application = current as? UIApplication {
                    application.open(url, options: [:], completionHandler: nil)
                    break
                }
                responder = current.next
            }
        } else {
            let selectorOpenURL = sel_registerName("openURL:")
            while let current = responder {
                if current.responds(to: selectorOpenURL) {
                    _ = current.perform(selectorOpenURL, with: url)
                    break
                }
                responder = current.next
            }
        }

        // Close the extension after opening app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.finishExtensionRequest()
        }
    }

    @objc private func cancelLoginRequiredTapped() {
        shareLog("Cancel tapped from login modal")

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // Cancel the extension
        let error = NSError(
            domain: "com.worthify.shareExtension",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
        )
        extensionContext?.cancelRequest(withError: error)
    }

    private func openURLViaResponderChain(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        let selector = NSSelectorFromString("openURL:")
        while let currentResponder = responder {
            if currentResponder.responds(to: selector) {
                currentResponder.perform(selector, with: url)
                return true
            }
            responder = currentResponder.next
        }
        return false
    }

    @objc private func cancelImportTapped() {
        shareLog("Cancel tapped")

        // Cancel any pending work items
        loadingHideWorkItem?.cancel()
        loadingHideWorkItem = nil

        // Stop any ongoing processes
        endExtendedExecution()

        // Clear data without touching UI (let system handle dismissal animation)
        clearSharedData()

        // Cancel the extension request - iOS will handle the dismissal animation
        let error = NSError(
            domain: "com.worthify.shareExtension",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "User cancelled import"]
        )
        didCompleteRequest = true
        extensionContext?.cancelRequest(withError: error)
    }

    @objc private func backButtonTapped() {
        // If results are showing, reuse existing flow to return to preview
        if isShowingResults {
            backToPreviewTapped()
            return
        }

        // If we're on the preview screen, go back to the initial choice UI
        if isShowingPreview {
            shareLog("Back button tapped - returning to choice screen")

            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()

            showInitialChoiceScreen()
        }
    }

    private func showInitialChoiceScreen() {
        // Reset state flags
        isShowingPreview = false
        isShowingResults = false

        // Remove any existing overlays/header UI
        hideLoadingUI()

        // Recreate blank overlay for the choice buttons
        let blankOverlay = UIView(frame: view.bounds)
        blankOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blankOverlay.backgroundColor = UIColor.systemBackground
        blankOverlay.tag = 9999
        view.addSubview(blankOverlay)

        addLogoAndCancel()
        showChoiceButtons()
        hideDefaultUI()
    }

    @objc private func backToPreviewTapped() {
        shareLog("Back button tapped - returning to image preview")

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // Clear results UI
        clearResultsUI()

        // Show the image preview again
        guard let imageData = analyzedImageData else {
            shareLog("ERROR: No image data available to show preview")
            return
        }

        showImagePreview(imageData: imageData)
    }

    private func clearResultsUI() {
        shareLog("Clearing results UI")

        // Mark that we're no longer showing results
        isShowingResults = false

        // Remove table view
        resultsTableView?.removeFromSuperview()
        resultsTableView = nil

        // Remove category filter view
        categoryFilterView?.removeFromSuperview()
        categoryFilterView = nil

        // Remove image comparison view
        resultsHeaderContainerView?.removeFromSuperview()
        resultsHeaderContainerView = nil
        imageComparisonContainerView?.removeFromSuperview()
        imageComparisonContainerView = nil
        imageComparisonThumbnailImageView = nil
        imageComparisonFullImageView = nil
        isImageComparisonExpanded = false

        // Remove all subviews from loading view except header
        if let loadingView = loadingView {
            for subview in loadingView.subviews {
                if subview != headerContainerView {
                    subview.removeFromSuperview()
                }
            }
        }

        // Clear detection results data
        filteredResults = []
        selectedGroup = nil

        shareLog("Results UI cleared")
    }

    @objc private func analyzeInAppTapped() {
        shareLog("Analyze in app tapped")

        // Check if user is authenticated first
        if !isUserAuthenticated() {
            shareLog("User not authenticated - showing login required modal")
            showLoginRequiredModal()
            return
        }

        // Check if user has available credits
        if !hasAvailableCredits() {
            shareLog("Local credits unavailable - attempting server verification before blocking analyze-in-app")
            resolveCreditAccess { [weak self] hasCredits in
                guard let self = self else { return }
                if hasCredits {
                    shareLog("Server verification succeeded - retrying analyze-in-app")
                    self.analyzeInAppTapped()
                } else {
                    shareLog("User has no credits - showing out of credits modal")
                    self.showOutOfCreditsModal()
                }
            }
            return
        }

        if deferActionIfAttachmentsStillLoading(.analyzeInApp) {
            return
        }

        // Keep extension alive while network/download work is running.
        requestExtendedExecution()

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // Remove choice UI
        hideLoadingUI()

        // Check if user already analyzed via "Analyze now" - if so, just pass the search_id
        if let searchId = currentSearchId {
            shareLog("User already analyzed - opening app with search_id: \(searchId)")

            // Save search_id to UserDefaults so Flutter can read it
            let userDefaults = UserDefaults(suiteName: appGroupId)
            userDefaults?.set(searchId, forKey: "search_id")
            userDefaults?.set("pending", forKey: kProcessingStatusKey)
            let sessionId = UUID().uuidString
            userDefaults?.set(sessionId, forKey: kProcessingSessionKey)
            userDefaults?.synchronize()
            shareLog("Saved search_id to UserDefaults: \(searchId)")

            // Redirect to host app without file paths
            loadIds()
            guard let redirectURL = URL(string: "\(kSchemePrefix)-\(hostAppBundleIdentifier):share") else {
                shareLog("ERROR: Failed to build redirect URL")
                dismissWithError()
                return
            }

            enqueueRedirect(to: redirectURL, minimumDuration: 0.5) { [weak self] in
                self?.finishExtensionRequest()
            }
            return
        }

        // Check if this is a URL (before download) or direct image (after download)
        if let socialUrl = pendingInstagramUrl {
            let platformName = getPlatformDisplayName(pendingPlatformType)

            // Download media and save to app (cache checking disabled)
            shareLog("Downloading \(platformName) media and saving to app")

            // Start download process
            updateProcessingStatus("processing")
            setupLoadingUI()

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.startSmoothProgress()
                self.targetProgress = 0.92
                self.updateProgress(0.0, status: "Opening Worthify...")
            }

            let downloadFunction = getDownloadFunction(for: pendingPlatformType)
            downloadFunction(socialUrl) { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .success(let downloaded):
                    if downloaded.isEmpty {
                        shareLog("\(platformName) download succeeded but returned no files")
                        self.dismissWithError()
                    } else {
                        self.sharedMedia.append(contentsOf: downloaded)
                        shareLog("Downloaded and saved \(downloaded.count) \(platformName) file(s)")

                        // Update progress to completion
                        self.targetProgress = 1.0
                        self.updateProgress(1.0, status: "Opening Worthify...")

                        // Delay to allow progress bar to complete fully before redirecting
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                            // Stop smooth progress to lock at 100%
                            self.stopSmoothProgress()
                            self.saveAndRedirect(message: self.pendingInstagramUrl)
                        }
                    }

                    // DON'T call pendingInstagramCompletion - we're handling redirect ourselves
                    self.pendingInstagramCompletion = nil
                    self.pendingInstagramUrl = nil

                case .failure(let error):
                    shareLog("ERROR: \(platformName) download failed - \(error.localizedDescription)")
                    self.dismissWithError()
                }
            }
        } else if let imageData = pendingImageData,
                  let sharedFile = pendingSharedFile,
                  let fileURL = URL(string: sharedFile.path) {
            shareLog("Saving direct image to app")

            // Start UI setup for direct image shares
            updateProcessingStatus("processing")
            setupLoadingUI()

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                // Start smooth progress animation
                self.stopStatusPolling()
                self.startSmoothProgress()
                self.targetProgress = 0.98
                self.updateProgress(0.0, status: "Opening Worthify...")

                // Complete after brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.targetProgress = 1.0
                }
            }

            do {
                // Write the file to shared container
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                try imageData.write(to: fileURL, options: .atomic)
                shareLog("Saved image to shared container: \(fileURL.path)")

                // Add to shared media array
                sharedMedia.append(sharedFile)

                // Delay to allow progress bar to complete fully before redirecting
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
                    guard let self = self else { return }
                    // Stop smooth progress to lock at 100%
                    self.stopSmoothProgress()
                    self.saveAndRedirect(message: self.pendingImageUrl)
                }

            } catch {
                shareLog("ERROR: Failed to save image - \(error.localizedDescription)")
            }
        } else if !sharedMedia.isEmpty {
            // Fallback: We have media in sharedMedia (e.g., from a non-social-media URL)
            shareLog("Using already-processed media from sharedMedia array")

            // Start UI setup
            updateProcessingStatus("processing")
            setupLoadingUI()

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                // Start smooth progress animation
                self.stopStatusPolling()
                self.startSmoothProgress()
                self.targetProgress = 0.98
                self.updateProgress(0.0, status: "Opening Worthify...")

                // Complete and redirect
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    guard let self = self else { return }
                    self.targetProgress = 1.0

                    // Delay to allow progress bar to complete fully before redirecting
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.stopSmoothProgress()
                        self?.saveAndRedirect(message: nil)
                    }
                }
            }
        } else {
            shareLog("ERROR: No pending URL, image data, or shared media")
        }
    }

    @objc private func analyzeNowTapped() {
        shareLog("Analyze now tapped - starting detection")
        shareLog("DEBUG: pendingInstagramUrl=\(pendingInstagramUrl != nil ? "SET" : "NIL"), pendingPlatformType=\(pendingPlatformType ?? "NIL"), sharedMedia.count=\(sharedMedia.count)")

        // Check if user is authenticated first
        if !isUserAuthenticated() {
            shareLog("User not authenticated - showing login required modal")
            showLoginRequiredModal()
            return
        }

        // Check if user has available credits
        if !hasAvailableCredits() {
            shareLog("Local credits unavailable - attempting server verification before blocking analyze-now")
            resolveCreditAccess { [weak self] hasCredits in
                guard let self = self else { return }
                if hasCredits {
                    shareLog("Server verification succeeded - retrying analyze-now")
                    self.analyzeNowTapped()
                } else {
                    shareLog("User has no credits - showing out of credits modal")
                    self.showOutOfCreditsModal()
                }
            }
            return
        }

        if deferActionIfAttachmentsStillLoading(.analyzeNow) {
            return
        }

        // Keep extension alive while network/download work is running.
        requestExtendedExecution()

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // Remove choice UI
        hideLoadingUI()

        // Check if this is a URL (before download) or direct image (after download)
        if let socialUrl = pendingInstagramUrl {
            let platformName = getPlatformDisplayName(pendingPlatformType)

            // Start UI setup early
            updateProcessingStatus("processing")
            setupLoadingUI()

            let proceedToDownload: () -> Void = { [weak self] in
                guard let self = self else { return }

                // Instagram gets special treatment with rotating messages
                let isInstagram = (self.pendingPlatformType == "instagram")
                let isX = (self.pendingPlatformType == "x")
                let isPinterest = (self.pendingPlatformType == "pinterest")
                let isFacebook = (self.pendingPlatformType == "facebook")
                let isReddit = (self.pendingPlatformType == "reddit")
                let isSnapchat = (self.pendingPlatformType == "snapchat")

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.startSmoothProgress()
                    // Default speed unless overridden per-platform
                    self.progressRateMultiplier = isX ? 0.5 : 1.0

                    if isInstagram {
                        // Instagram: rotating messages for more engaging UX
                        let instagramMessages = [
                            "Getting image...",
                            "Downloading photo...",
                            "Fetching photo...",
                            "Almost there..."
                        ]
                        self.startStatusRotation(messages: instagramMessages, interval: 2.0)

                        // Slow down progress rate for Instagram to match 4-5 second download time
                        // Normal rate is 1.0, we use 0.35 to make it reach 92% in ~4-5 seconds
                        self.progressRateMultiplier = 0.35
                        self.targetProgress = 0.92
                    } else {
                        // TikTok, Pinterest, etc.: simple single message
                        self.targetProgress = 0.92
                        self.updateProgress(0.0, status: "Loading preview...")
                    }
                }

                let downloadFunction = self.getDownloadFunction(for: self.pendingPlatformType)
                downloadFunction(socialUrl) { [weak self] result in
                    guard let self = self else { return }

                    switch result {
                    case .success(let downloaded):
                        if downloaded.isEmpty {
                            shareLog("\(platformName) download succeeded but returned no files")
                            self.dismissWithError()
                        } else {
                            // Get the first downloaded file and show preview
                            if let firstFile = downloaded.first {
                                let fileURL: URL
                                if let url = URL(string: firstFile.path), url.scheme != nil {
                                    fileURL = url
                                } else {
                                    fileURL = URL(fileURLWithPath: firstFile.path)
                                }

                                if let imageData = try? Data(contentsOf: fileURL) {
                                    shareLog("Downloaded \(platformName) image (\(imageData.count) bytes) - showing preview")

                                    // Update progress to completion
                                    if isInstagram {
                                        self.stopStatusRotation()
                                    }
                                    self.targetProgress = 1.0
                                    self.updateProgress(1.0, status: "Loading preview...")

                                    // Delay to allow progress bar to complete fully before showing preview
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                                        // Stop smooth progress to lock at 100%
                                        self.stopSmoothProgress()
                                        self.showImagePreview(imageData: imageData, resetOriginal: true)
                                    }
                                } else {
                                    shareLog("ERROR: Could not read downloaded \(platformName) file")
                                    self.dismissWithError()
                                }
                            }
                        }

                        // DON'T call completion - we're showing preview, not redirecting
                        self.pendingInstagramCompletion = nil
                        // Keep pendingInstagramUrl so it can be sent to backend for Instagram cache storage

                    case .failure(let error):
                        shareLog("ERROR: \(platformName) download failed - \(error.localizedDescription)")
                        self.dismissWithError()
                    }
                }
            }

            // Proceed with download (cache checking disabled)
            proceedToDownload()
        } else if let imageData = pendingImageData {
            shareLog("Showing preview for direct image with \(imageData.count) bytes")

            // Start UI setup for direct image shares
            updateProcessingStatus("processing")
            setupLoadingUI()

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                // Start smooth progress animation
                self.stopStatusPolling()
                self.startSmoothProgress()
                self.targetProgress = 0.98
                self.updateProgress(0.0, status: "Loading preview...")

                // Complete and show preview
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    guard let self = self else { return }
                    self.targetProgress = 1.0

                    // Show preview after progress completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.stopSmoothProgress()
                        self?.showImagePreview(imageData: imageData, resetOriginal: true)
                    }
                }
            }
        } else if !sharedMedia.isEmpty {
            // Fallback: For non-social-media URLs, we can't analyze directly
            // Just redirect to the app with the URL
            shareLog("Non-social-media URL - redirecting to app for analysis")
            if pendingPlatformType == nil {
                pendingPlatformType = inferredPlatformType ?? "photos"
            }
            if let platformType = pendingPlatformType {
                let userDefaults = UserDefaults(suiteName: appGroupId)
                userDefaults?.set(platformType, forKey: "pending_platform_type")
                userDefaults?.synchronize()
                shareLog("Saved pending platform type for redirect: \(platformType)")
            }
            saveAndRedirect(message: nil)
        } else {
            shareLog("ERROR: No pending URL, image data, or shared media")
        }
    }

    private func clearSharedData() {
        sharedMedia.removeAll()
        analyzedImageData = nil
        originalImageData = nil
        previewImageView = nil
        revertCropButton?.removeFromSuperview()
        revertCropButton = nil
        if let defaults = UserDefaults(suiteName: appGroupId) {
            defaults.removeObject(forKey: kUserDefaultsKey)
            defaults.removeObject(forKey: kUserDefaultsMessageKey)
            defaults.removeObject(forKey: kProcessingStatusKey)
            defaults.removeObject(forKey: kProcessingSessionKey)
            defaults.synchronize()
        }
    }

    // Request extended execution time from iOS to prevent extension termination
    private func requestExtendedExecution() {
        endExtendedExecution() // Clean up any existing activity first

        let reason = "Share extension processing"
        shareLog("Requesting extended execution time from iOS")
        backgroundActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: reason
        )
        ProcessInfo.processInfo.performExpiringActivity(withReason: reason) { [weak self] expired in
            guard expired else { return }
            shareLog("Extended execution time expired - iOS is requesting termination")
            // iOS is asking us to wrap up - keep extension alive if the user is still interacting
            DispatchQueue.main.async {
                shareLog("Extended time expired but keeping extension alive for user interaction")
                self?.endExtendedExecution()
            }
        }
        shareLog("Extended execution time granted")
    }

    // End extended execution time
    private func endExtendedExecution() {
        guard let activity = backgroundActivity else { return }
        shareLog("Ending extended execution time")
        ProcessInfo.processInfo.endActivity(activity)
        backgroundActivity = nil
    }

    deinit {
        shareLog("RSIShareViewController deinit")
    }

}

// MARK: - Table View Delegate & DataSource
extension RSIShareViewController: UITableViewDelegate, UITableViewDataSource {
    public func numberOfSections(in tableView: UITableView) -> Int {
        return resultsHeaderContainerView == nil ? 1 : 2
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if resultsHeaderContainerView != nil && section == 0 {
            return 1
        }
        return filteredResults.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if resultsHeaderContainerView != nil && indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ResultsHeaderCell", for: indexPath)
            cell.selectionStyle = .none
            cell.backgroundColor = .systemBackground
            cell.contentView.backgroundColor = .systemBackground
            cell.separatorInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: .greatestFiniteMagnitude)

            if let headerView = resultsHeaderContainerView {
                if headerView.superview !== cell.contentView {
                    headerView.removeFromSuperview()
                    cell.contentView.addSubview(headerView)
                    headerView.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        headerView.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                        headerView.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                        headerView.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                        headerView.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor)
                    ])
                }
            }

            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "ResultCell", for: indexPath) as! ResultCell
        let result = filteredResults[indexPath.row]
        let isFavorited = favoritedProductIds.contains(result.id)
        cell.configure(with: result, isFavorited: isFavorited)

        // Set favorite toggle callback
        let currentIndexPath = indexPath
        cell.onFavoriteToggle = { [weak self] product, isFavorite in
            guard let self = self else { return }

            if isFavorite {
                self.favoritedProductIds.insert(product.id)
                self.addFavoriteToBackend(product: product) { success in
                    if !success {
                        shareLog("Failed to add favorite to backend")
                        self.favoritedProductIds.remove(product.id)
                        if let tableView = self.resultsTableView,
                           currentIndexPath.row < self.filteredResults.count {
                            tableView.reloadRows(at: [currentIndexPath], with: .none)
                        }
                    }
                }
            } else {
                self.favoritedProductIds.remove(product.id)
                self.removeFavoriteFromBackend(product: product) { success in
                    if success {
                        shareLog("Removed favorite for product \(product.id)")
                    } else {
                        shareLog("Failed to remove favorite from backend")
                        self.favoritedProductIds.insert(product.id)
                        if let tableView = self.resultsTableView,
                           currentIndexPath.row < self.filteredResults.count {
                            tableView.reloadRows(at: [currentIndexPath], with: .none)
                        }
                    }
                }
            }
        }

        // Hide separator for last cell
        if indexPath.row == filteredResults.count - 1 {
            cell.separatorInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: .greatestFiniteMagnitude)
        } else {
            cell.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        }

        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if resultsHeaderContainerView != nil && indexPath.section == 0 {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }

        tableView.deselectRow(at: indexPath, animated: true)
        let selectedResult = filteredResults[indexPath.row]
        shareLog("User selected result: \(selectedResult.product_name)")

        // Open the product URL in a WKWebView inside the modal
        guard let urlString = selectedResult.purchase_url,
              let url = URL(string: urlString) else {
            shareLog("ERROR: Invalid product URL: \(selectedResult.purchase_url ?? "nil")")
            return
        }

        // Create WebViewController
        let webVC = WebViewController(url: url, shareViewController: self)

        // Embed in a navigation controller
        let navController = UINavigationController(rootViewController: webVC)
        navController.modalPresentationStyle = .pageSheet
        navController.isNavigationBarHidden = true // WebViewController has its own toolbar
        navController.modalPresentationCapturesStatusBarAppearance = true // Let WebVC control status bar

        // Configure sheet presentation to match iOS 18 corner radius standards
        if #available(iOS 15.0, *) {
            if let sheet = navController.sheetPresentationController {
                sheet.prefersGrabberVisible = false
                sheet.preferredCornerRadius = 38 // Match iOS 18's larger corner radius
            }
        }

        // Present modally so it appears on top of the loadingView overlay
        present(navController, animated: true) {
            NSLog("[ShareExtension] Presented WebViewController for URL: \(url.absoluteString)")
        }
    }

    private func saveSelectedResultAndRedirect(_ result: DetectionResultItem) {
        shareLog("[SUCCESS] USER SELECTED RESULT - saving and redirecting")

        // NOW write the file to shared container
        if let data = pendingImageData, let file = pendingSharedFile {
            guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
                shareLog("[ERROR] Cannot get container URL")
                return
            }

            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let fileName = "instagram_image_\(timestamp)_selected.jpg"
            let fileURL = containerURL.appendingPathComponent(fileName)

            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                try data.write(to: fileURL, options: .atomic)
                shareLog("[SAVED] SELECTED RESULT: Wrote file to shared container: \(fileURL.path)")

                // Update the shared file path
                var updatedFile = file
                updatedFile.path = fileURL.absoluteString

                // Save the selected result to UserDefaults
                if let defaults = UserDefaults(suiteName: appGroupId) {
                    var resultData: [String: Any] = [
                        "product_name": result.product_name,
                        "brand": result.brand ?? "",
                        "price": result.priceValue ?? 0,
                        "image_url": result.image_url,
                        "purchase_url": result.purchase_url ?? "",
                        "category": result.category
                    ]

                    if let priceDisplay = result.priceDisplay {
                        resultData["price_display"] = priceDisplay
                    }

                    if let jsonData = try? JSONSerialization.data(withJSONObject: resultData),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        defaults.set(jsonString, forKey: "SelectedDetectionResult")
                        defaults.synchronize()
                        shareLog("[SAVED] SELECTED RESULT: Saved result metadata to UserDefaults")
                    }

                    // Save the file
                    defaults.set(toData(data: [updatedFile]), forKey: kUserDefaultsKey)
                    defaults.synchronize()
                    shareLog("[SAVED] SELECTED RESULT: Saved file to UserDefaults")
                }
            } catch {
                shareLog("[ERROR] writing file with selected result: \(error.localizedDescription)")
            }
        }

        // Redirect to app
        loadIds()
        guard let redirectURL = URL(string: "\(kSchemePrefix)-\(hostAppBundleIdentifier):detection") else {
            shareLog("[ERROR] Failed to build redirect URL")
            return
        }

        hasQueuedRedirect = true
        shareLog("🚀 Redirecting to app with selected result")
        let minimumDuration = isPhotosSourceApp ? 2.0 : 0.0
        enqueueRedirect(to: redirectURL, minimumDuration: minimumDuration) { [weak self] in
            self?.finishExtensionRequest()
        }
    }
}

// MARK: - Result Cell
class ResultCell: UITableViewCell {
    private let productImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 8
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let brandLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont(name: "PlusJakartaSans-Bold", size: 16)
            ?? .systemFont(ofSize: 16, weight: .bold)
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let productNameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont(name: "PlusJakartaSans-Medium", size: 12)
            ?? .systemFont(ofSize: 12, weight: .medium)
        // Match Flutter onSurface color (0xFF1c1c25) for consistency with in-app results
        label.textColor = UIColor(red: 0x1c/255.0, green: 0x1c/255.0, blue: 0x25/255.0, alpha: 1.0)
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let priceLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont(name: "PlusJakartaSans-Bold", size: 16)
            ?? .systemFont(ofSize: 16, weight: .bold)
        label.textColor = UIColor(red: 242/255, green: 0, blue: 60/255, alpha: 1.0)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let favoriteButton: UIButton = {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        button.setImage(UIImage(systemName: "heart", withConfiguration: config), for: .normal)
        button.setImage(UIImage(systemName: "heart.fill", withConfiguration: config), for: .selected)
        button.tintColor = .black
        button.backgroundColor = UIColor(white: 1.0, alpha: 0.75)
        button.layer.cornerRadius = 14
        button.layer.masksToBounds = false
        button.layer.shadowColor = UIColor.black.withAlphaComponent(0.1).cgColor
        button.layer.shadowOpacity = 1
        button.layer.shadowRadius = 3
        button.layer.shadowOffset = CGSize(width: 0, height: 1.5)
        button.adjustsImageWhenHighlighted = false
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        button.imageEdgeInsets = .zero
        return button
    }()

    private let chevronImageView: UIImageView = {
        let iv = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        iv.image = UIImage(systemName: "chevron.right", withConfiguration: config)
        iv.tintColor = UIColor.tertiaryLabel
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private var isFavorite = false
    private var product: DetectionResultItem?
    var onFavoriteToggle: ((DetectionResultItem, Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        // Create a vertical stack for the text labels (with spacer to keep price anchored at bottom)
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let textStackView = UIStackView(arrangedSubviews: [brandLabel, productNameLabel, spacer, priceLabel])
        textStackView.axis = .vertical
        textStackView.spacing = 4
        textStackView.distribution = .fill
        textStackView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(productImageView)
        contentView.addSubview(favoriteButton)
        contentView.addSubview(textStackView)
        contentView.addSubview(chevronImageView)
        favoriteButton.addTarget(self, action: #selector(favoriteTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            productImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            productImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            productImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            productImageView.widthAnchor.constraint(equalToConstant: 80),
            productImageView.heightAnchor.constraint(equalToConstant: 80),

            favoriteButton.bottomAnchor.constraint(equalTo: productImageView.bottomAnchor, constant: -6),
            favoriteButton.trailingAnchor.constraint(equalTo: productImageView.trailingAnchor, constant: -6),
            favoriteButton.widthAnchor.constraint(equalToConstant: 28),
            favoriteButton.heightAnchor.constraint(equalToConstant: 28),

            chevronImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            chevronImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevronImageView.widthAnchor.constraint(equalToConstant: 16),
            chevronImageView.heightAnchor.constraint(equalToConstant: 16),

            textStackView.leadingAnchor.constraint(equalTo: productImageView.trailingAnchor, constant: 12),
            textStackView.trailingAnchor.constraint(equalTo: chevronImageView.leadingAnchor, constant: -18),
            textStackView.topAnchor.constraint(equalTo: productImageView.topAnchor),
            textStackView.bottomAnchor.constraint(equalTo: productImageView.bottomAnchor),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 110)
        ])
    }

    func configure(with result: DetectionResultItem, isFavorited: Bool = false) {
        // Store product for favorite callback
        self.product = result
        let brandText: String
        if let brand = result.brand, !brand.isEmpty {
            brandText = brand
        } else {
            brandText = "Worthify match"
        }
        // Match in-app behavior: always show brand in uppercase
        brandLabel.text = brandText.uppercased()
        productNameLabel.text = result.product_name

        // Only show priceDisplay if available, otherwise "See store"
        if let displayPrice = result.priceDisplay {
            priceLabel.text = displayPrice
        } else {
            priceLabel.text = "See store"
        }

        // Load image asynchronously
        productImageView.image = nil
        if let url = URL(string: result.image_url) {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                if let data = data, let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self?.productImageView.image = image
                    }
                }
            }.resume()
        }

        // Set favorite state (checking if already favorited)
        isFavorite = isFavorited
        updateFavoriteAppearance(animated: false)
    }

    @objc private func favoriteTapped() {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()

        isFavorite.toggle()
        updateFavoriteAppearance(animated: true)

        // Call backend API via callback
        if let product = product {
            onFavoriteToggle?(product, isFavorite)
        }
    }

    private func updateFavoriteAppearance(animated: Bool) {
        let applyAppearance = {
            self.favoriteButton.isSelected = self.isFavorite
            self.favoriteButton.tintColor = self.isFavorite
                ? UIColor(red: 242/255, green: 0, blue: 60/255, alpha: 1.0)
                : .black
        }

        if animated {
            applyAppearance()
            let expandTransform = CGAffineTransform(scaleX: 1.12, y: 1.12)
            UIView.animate(withDuration: 0.1, animations: {
                self.favoriteButton.transform = expandTransform
            }, completion: { _ in
                UIView.animate(
                    withDuration: 0.25,
                    delay: 0,
                    usingSpringWithDamping: 0.55,
                    initialSpringVelocity: 3.5,
                    options: [.allowUserInteraction, .beginFromCurrentState],
                    animations: {
                        self.favoriteButton.transform = .identity
                    },
                    completion: nil
                )
            })
        } else {
            applyAppearance()
            favoriteButton.transform = .identity
        }
    }
}

extension RSIShareViewController: TOCropViewControllerDelegate {
    public func cropViewController(_ cropViewController: TOCropViewController, didCropTo image: UIImage, with cropRect: CGRect, angle: Int) {
        shareLog("Image cropped successfully - size: \(image.size)")

        // Convert cropped image to JPEG data with high quality
        guard let croppedImageData = image.jpegData(compressionQuality: 0.9) else {
            shareLog("ERROR: Failed to convert cropped image to data")
            cropViewController.dismiss(animated: true, completion: nil)
            return
        }

        shareLog("Cropped image data: \(croppedImageData.count) bytes")

        // Update the stored image data with cropped version
        analyzedImageData = croppedImageData

        // Update the preview image
        if let previewImageView = previewImageView {
            UIView.transition(with: previewImageView, duration: 0.3, options: .transitionCrossDissolve, animations: {
                previewImageView.image = image
            }, completion: nil)
            shareLog("Updated preview with cropped image")
        }
        updateRevertButtonVisibility()

        // Dismiss crop view controller
        cropViewController.dismiss(animated: true) {
            shareLog("Crop view controller dismissed")
        }
    }

    public func cropViewController(_ cropViewController: TOCropViewController, didFinishCancelled cancelled: Bool) {
        shareLog("Crop cancelled by user")
        cropViewController.dismiss(animated: true, completion: nil)
    }
}

extension URL {
    func mimeType() -> String {
        if #available(iOS 14.0, *) {
            if let mimeType = UTType(filenameExtension: self.pathExtension)?.preferredMIMEType {
                return mimeType
            }
        } else {
            if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, self.pathExtension as NSString, nil)?.takeRetainedValue() {
                if let mimetype = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() {
                    return mimetype as String
                }
            }
        }
        return "application/octet-stream"
    }

    /// Resolve a relative URL string against this base URL
    func resolve(_ relativeString: String) -> String? {
        if relativeString.hasPrefix("http://") || relativeString.hasPrefix("https://") {
            return relativeString
        }

        if relativeString.hasPrefix("//") {
            return "\(self.scheme ?? "https"):\(relativeString)"
        }

        if let resolved = URL(string: relativeString, relativeTo: self) {
            return resolved.absoluteString
        }

        return nil
    }
}

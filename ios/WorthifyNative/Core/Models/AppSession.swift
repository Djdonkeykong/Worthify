import Foundation

struct AppSession: Codable, Equatable {
    let userID: String
    let email: String?
    let isAnonymous: Bool
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    var isExpired: Bool {
        expiresAt <= Date().addingTimeInterval(30)
    }
}

struct SubscriptionSnapshot: Equatable {
    let isActive: Bool
    let isTrial: Bool
    let productIdentifier: String?
    let availableCredits: Int

    static let inactive = SubscriptionSnapshot(
        isActive: false,
        isTrial: false,
        productIdentifier: nil,
        availableCredits: 0
    )
}

struct UserProfile: Codable, Equatable {
    let id: String
    let email: String?
    let fullName: String?
    let avatarURL: String?
    let subscriptionStatus: String?
    let subscriptionProductID: String?
    let availableCredits: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName = "full_name"
        case avatarURL = "avatar_url"
        case subscriptionStatus = "subscription_status"
        case subscriptionProductID = "subscription_product_id"
        case availableCredits = "paid_credits_remaining"
    }
}

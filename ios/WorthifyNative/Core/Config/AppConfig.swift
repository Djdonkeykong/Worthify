import Foundation

struct AppConfig {
    let supabaseURL: String
    let supabaseAnonKey: String
    let artworkEndpoint: String
    let detectEndpoint: String
    let detectAndSearchEndpoint: String
    let searchAPIKey: String
    let apifyAPIToken: String
    let cloudinaryCloudName: String
    let cloudinaryAPIKey: String
    let cloudinaryAPISecret: String
    let amplitudeAPIKey: String
    let revenueCatAPIKey: String
    let superwallAPIKey: String
    let appGroupID: String

    var supabaseProjectURL: URL {
        URL(string: supabaseURL)!
    }

    var authBaseURL: URL {
        supabaseProjectURL.appendingPathComponent("auth/v1")
    }

    var restBaseURL: URL {
        supabaseProjectURL.appendingPathComponent("rest/v1")
    }

    var startupValidationMessage: String? {
        var missingKeys: [String] = []
        if supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missingKeys.append("SUPABASE_URL")
        }
        if supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missingKeys.append("SUPABASE_ANON_KEY")
        }

        guard !missingKeys.isEmpty else {
            return nil
        }

        return "Missing startup config: \(missingKeys.joined(separator: ", "))."
    }

    static func load(bundle: Bundle = .main) -> AppConfig {
        func value(_ key: String) -> String {
            bundle.object(forInfoDictionaryKey: key) as? String ?? ""
        }

        return AppConfig(
            supabaseURL: value("SUPABASE_URL"),
            supabaseAnonKey: value("SUPABASE_ANON_KEY"),
            artworkEndpoint: value("ARTWORK_ENDPOINT"),
            detectEndpoint: value("DETECT_ENDPOINT"),
            detectAndSearchEndpoint: value("DETECT_AND_SEARCH_ENDPOINT"),
            searchAPIKey: value("SEARCHAPI_KEY"),
            apifyAPIToken: value("APIFY_API_TOKEN"),
            cloudinaryCloudName: value("CLOUDINARY_CLOUD_NAME"),
            cloudinaryAPIKey: value("CLOUDINARY_API_KEY"),
            cloudinaryAPISecret: value("CLOUDINARY_API_SECRET"),
            amplitudeAPIKey: value("AMPLITUDE_API_KEY"),
            revenueCatAPIKey: value("REVENUECAT_IOS_API_KEY"),
            superwallAPIKey: value("SUPERWALL_IOS_API_KEY"),
            appGroupID: value("APP_GROUP_ID")
        )
    }
}

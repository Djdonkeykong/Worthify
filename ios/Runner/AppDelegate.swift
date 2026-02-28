import UIKit
import Flutter
import receive_sharing_intent
import AVKit
import AVFoundation
import FirebaseCore
import FirebaseMessaging
import LinkPresentation

// Custom activity item source for sharing with thumbnail via LPLinkMetadata
private class ShareItemWithThumbnail: NSObject, UIActivityItemSource {
    let imageURL: URL
    let thumbnailImage: UIImage?
    let subject: String

    init(imageURL: URL, thumbnailImage: UIImage?, subject: String) {
        self.imageURL = imageURL
        self.thumbnailImage = thumbnailImage
        self.subject = subject
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return imageURL
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return imageURL
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return subject
    }

    @available(iOS 13.0, *)
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = subject

        if let thumbnail = thumbnailImage {
            metadata.imageProvider = NSItemProvider(object: thumbnail)
            metadata.iconProvider = NSItemProvider(object: thumbnail)
        }

        return metadata
    }
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let shareStatusChannelName = "com.worthify.worthify/share_status"
  private let shareConfigChannelName = "worthify/share_config"
  private let authChannelName = "worthify/auth"
  private let processingStatusKey = "ShareProcessingStatus"
  private let processingSessionKey = "ShareProcessingSession"
  private let serpApiKeyKey = "SerpApiKey"
  private let detectorEndpointKey = "DetectorEndpoint"
  private let apifyApiTokenKey = "ApifyApiToken"
  private let supabaseUrlKey = "SupabaseUrl"
  private let supabaseAnonKeyKey = "SupabaseAnonKey"
  private let shareLogsChannelName = "worthify/share_extension_logs"
  private let shareLogsKey = "ShareExtensionLogEntries"
  private let authFlagKey = "user_authenticated"
  private let authUserIdKey = "supabase_user_id"
  private let authAccessTokenKey = "supabase_access_token"
  private let authSubscriptionKey = "user_has_active_subscription"
  private let authCreditsKey = "user_available_credits"
  private let pipTutorialChannelName = "pip_tutorial"
  private var pipTutorialManager: PipTutorialManager?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Set window background to black (shows when app is backgrounded)
    window?.backgroundColor = UIColor.black

    if let controller = window?.rootViewController as? FlutterViewController {
      // Share status channel
      let shareStatusChannel = FlutterMethodChannel(
        name: shareStatusChannelName,
        binaryMessenger: controller.binaryMessenger
      )

      // Share config channel
      let shareConfigChannel = FlutterMethodChannel(
        name: shareConfigChannelName,
        binaryMessenger: controller.binaryMessenger
      )

      let shareLogsChannel = FlutterMethodChannel(
        name: shareLogsChannelName,
        binaryMessenger: controller.binaryMessenger
      )

      let authChannel = FlutterMethodChannel(
        name: authChannelName,
        binaryMessenger: controller.binaryMessenger
      )

      let pipTutorialChannel = FlutterMethodChannel(
        name: pipTutorialChannelName,
        binaryMessenger: controller.binaryMessenger
      )

      let nativeShareChannel = FlutterMethodChannel(
        name: "worthify/native_share",
        binaryMessenger: controller.binaryMessenger
      )

      // Notification channel for triggering APNS registration
      let notificationChannel = FlutterMethodChannel(
        name: "worthify/notifications",
        binaryMessenger: controller.binaryMessenger
      )

      notificationChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(FlutterError(code: "UNAVAILABLE", message: "AppDelegate released", details: nil))
          return
        }

        switch call.method {
        case "registerForRemoteNotifications":
          NSLog("[APNS] Flutter requested remote notification registration")
          DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
            NSLog("[APNS] Called UIApplication.shared.registerForRemoteNotifications()")
          }
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      // Handle auth method calls
      authChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(FlutterError(code: "UNAVAILABLE", message: "AppDelegate released", details: nil))
          return
        }

        switch call.method {
        case "setAuthFlag":
          NSLog("[Auth] setAuthFlag called from Flutter")

          guard let args = call.arguments as? [String: Any],
                let isAuthenticated = args["isAuthenticated"] as? Bool else {
            NSLog("[Auth] ERROR: Invalid arguments - isAuthenticated missing")
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
            return
          }

          guard let defaults = self.sharedUserDefaults() else {
            NSLog("[Auth] ERROR: Could not get sharedUserDefaults")
            result(FlutterError(code: "NO_DEFAULTS", message: "Cannot access UserDefaults", details: nil))
            return
          }

          // Log which app group we're using
          let groupId = self.getAppGroupId()
          NSLog("[Auth] Using app group: \(groupId ?? "nil")")

          defaults.set(isAuthenticated, forKey: self.authFlagKey)
          // Legacy alias used by older extension paths.
          defaults.set(isAuthenticated, forKey: "is_authenticated")

          // Store user ID if authenticated
          if let userId = args["userId"] as? String, !userId.isEmpty {
            defaults.set(userId, forKey: self.authUserIdKey)
            // Legacy alias used by older extension paths.
            defaults.set(userId, forKey: "user_id")
          } else if !isAuthenticated {
            // Only clear IDs when explicitly unauthenticated.
            defaults.removeObject(forKey: self.authUserIdKey)
            defaults.removeObject(forKey: "user_id")
          } else {
            // Preserve the last known user ID if auth is true but userId was omitted.
            NSLog("[Auth] WARNING: setAuthFlag called with isAuthenticated=true but missing userId; preserving existing ID")
          }

          // Store current Supabase access token for share-extension verification calls.
          if !isAuthenticated {
            defaults.removeObject(forKey: self.authAccessTokenKey)
          } else if let accessToken = args["accessToken"] as? String, !accessToken.isEmpty {
            defaults.set(accessToken, forKey: self.authAccessTokenKey)
          } else {
            NSLog("[Auth] INFO: accessToken missing while authenticated; preserving existing token")
          }

          // Store subscription status
          let hasActiveSubscription = args["hasActiveSubscription"] as? Bool ?? false
          defaults.set(hasActiveSubscription, forKey: self.authSubscriptionKey)

          // Store available credits
          let availableCredits = args["availableCredits"] as? Int ?? 0
          defaults.set(availableCredits, forKey: self.authCreditsKey)

          defaults.synchronize()

          // Verify it was written
          let readBackUserId = defaults.string(forKey: self.authUserIdKey)
          let readBackSubscription = defaults.bool(forKey: self.authSubscriptionKey)
          let readBackCredits = defaults.integer(forKey: self.authCreditsKey)
          let hasAccessToken = (defaults.string(forKey: self.authAccessTokenKey)?.isEmpty == false)
          NSLog("[Auth] Set auth flag to: \(isAuthenticated), userId: \(readBackUserId ?? "nil"), token: \(hasAccessToken), subscription: \(readBackSubscription), credits: \(readBackCredits)")

          result(nil)
        case "getNeedsCreditsFlag":
          NSLog("[Auth] getNeedsCreditsFlag called from Flutter")

          guard let defaults = self.sharedUserDefaults() else {
            NSLog("[Auth] ERROR: Could not get sharedUserDefaults")
            result(false)
            return
          }

          let needsCredits = defaults.bool(forKey: "needs_credits_from_share_extension")
          NSLog("[Auth] needs_credits_from_share_extension: \(needsCredits)")

          // Clear the flag after reading it
          if needsCredits {
            defaults.removeObject(forKey: "needs_credits_from_share_extension")
            defaults.synchronize()
            NSLog("[Auth] Cleared needs_credits_from_share_extension flag")
          }

          result(needsCredits)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      // Handle share config method calls
      shareConfigChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(FlutterError(code: "UNAVAILABLE", message: "AppDelegate released", details: nil))
          return
        }

        switch call.method {
        case "saveSharedConfig":
          guard let args = call.arguments as? [String: Any],
                let appGroupId = args["appGroupId"] as? String,
                let serpKey = args["serpApiKey"] as? String,
                let endpoint = args["detectorEndpoint"] as? String,
                let defaults = UserDefaults(suiteName: appGroupId) else {
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
            return
          }

          defaults.set(serpKey, forKey: self.serpApiKeyKey)
          defaults.set(endpoint, forKey: self.detectorEndpointKey)

          // Save Apify token if provided
          if let apifyToken = args["apifyApiToken"] as? String {
            defaults.set(apifyToken, forKey: self.apifyApiTokenKey)
            NSLog("[ShareConfig] âœ… Saved ApifyApiToken: \(apifyToken.prefix(12))...")
          }

          // Save Supabase URL and anon key if provided
          if let supabaseUrl = args["supabaseUrl"] as? String {
            defaults.set(supabaseUrl, forKey: self.supabaseUrlKey)
            NSLog("[ShareConfig] âœ… Saved Supabase URL: \(supabaseUrl)")
          }
          if let supabaseAnonKey = args["supabaseAnonKey"] as? String {
            defaults.set(supabaseAnonKey, forKey: self.supabaseAnonKeyKey)
            NSLog("[ShareConfig] âœ… Saved Supabase Anon Key: \(supabaseAnonKey.prefix(20))...")
          }

          defaults.synchronize()

          NSLog("[ShareConfig] âœ… Saved to app group \(appGroupId)")
          NSLog("[ShareConfig] âœ… SerpApiKey: \(serpKey.prefix(8))...")
          NSLog("[ShareConfig] âœ… DetectorEndpoint: \(endpoint)")

          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      shareStatusChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(
            FlutterError(
              code: "UNAVAILABLE",
              message: "AppDelegate released",
              details: nil
            )
          )
          return
        }

        switch call.method {
        case "updateShareProcessingStatus":
          guard
            let args = call.arguments as? [String: Any],
            let status = args["status"] as? String,
            let defaults = self.sharedUserDefaults()
          else {
            result(nil)
            return
          }
          defaults.set(status, forKey: self.processingStatusKey)
          defaults.synchronize()
          result(nil)
        case "markShareProcessingComplete":
          guard let defaults = self.sharedUserDefaults() else {
            result(nil)
            return
          }
          defaults.set("completed", forKey: self.processingStatusKey)
          defaults.synchronize()
          result(nil)
        case "getShareProcessingSession":
          guard let defaults = self.sharedUserDefaults() else {
            result(nil)
            return
          }
          let session = defaults.string(forKey: self.processingSessionKey)
          let status = defaults.string(forKey: self.processingStatusKey)
          var response: [String: Any] = [:]
          response["sessionId"] = session ?? NSNull()
          response["status"] = status ?? NSNull()
          result(response)
        case "getPendingSearchId":
          guard let defaults = self.sharedUserDefaults() else {
            result(nil)
            return
          }
          let searchId = defaults.string(forKey: "search_id")
          if let searchId = searchId {
            NSLog("[ShareExtension] Found pending search_id: \(searchId)")
            defaults.removeObject(forKey: "search_id")
            defaults.synchronize()
          }
          result(searchId)
        case "getPendingPlatformType":
          guard let defaults = self.sharedUserDefaults() else {
            result(nil)
            return
          }
          let platformType = defaults.string(forKey: "pending_platform_type")
          if let platformType = platformType {
            NSLog("[ShareExtension] Found pending platform_type: \(platformType)")
            defaults.removeObject(forKey: "pending_platform_type")
            defaults.synchronize()
          }
          result(platformType)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      nativeShareChannel.setMethodCallHandler { [weak self] call, result in
        guard let _ = self else {
          result(FlutterError(code: "UNAVAILABLE", message: "AppDelegate released", details: nil))
          return
        }

        switch call.method {
        case "shareImageWithText":
          guard let args = call.arguments as? [String: Any],
                let path = args["path"] as? String,
                let text = args["text"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing path or text", details: nil))
            return
          }

          let subject = (args["subject"] as? String) ?? ""
          let origin = args["origin"] as? [String: Double]
          let thumbnailPath = args["thumbnailPath"] as? String
          let fileURL = URL(fileURLWithPath: path)

          guard FileManager.default.fileExists(atPath: fileURL.path) else {
            result(FlutterError(code: "FILE_MISSING", message: "File does not exist at path", details: path))
            return
          }

          DispatchQueue.main.async {
            var items: [Any] = []

            // Use custom share item if we have a thumbnail
            if let thumbPath = thumbnailPath,
               let thumbnailImage = UIImage(contentsOfFile: thumbPath) {
              let shareItem = ShareItemWithThumbnail(
                imageURL: fileURL,
                thumbnailImage: thumbnailImage,
                subject: subject
              )
              items.append(shareItem)
            } else {
              items.append(fileURL)
            }

            if !text.isEmpty {
              items.append(text)
            }

            let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
            if !subject.isEmpty && thumbnailPath == nil {
              activityVC.setValue(subject, forKey: "subject")
            }

            if let popover = activityVC.popoverPresentationController {
              popover.sourceView = controller.view
              if let origin = origin,
                 let x = origin["x"], let y = origin["y"],
                 let w = origin["w"], let h = origin["h"] {
                popover.sourceRect = CGRect(x: x, y: y, width: w, height: h)
              } else {
                popover.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
              }
            }

            controller.present(activityVC, animated: true) {
              result(nil)
            }
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      shareLogsChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(
            FlutterError(
              code: "UNAVAILABLE",
              message: "AppDelegate released",
              details: nil
            )
          )
          return
        }

        guard let defaults = self.sharedUserDefaults() else {
          result(FlutterError(code: "NO_APP_GROUP", message: "App group not configured", details: nil))
          return
        }

        switch call.method {
        case "getLogs":
          let logs = defaults.stringArray(forKey: self.shareLogsKey) ?? []
          result(logs)
        case "clearLogs":
          defaults.removeObject(forKey: self.shareLogsKey)
          defaults.synchronize()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      pipTutorialChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(
            FlutterError(
              code: "UNAVAILABLE",
              message: "AppDelegate released",
              details: nil
            )
          )
          return
        }

        switch call.method {
        case "start":
          self.appendShareLog("[PiP] Flutter requested tutorial start")
          guard let args = call.arguments as? [String: Any],
                let target = args["target"] as? String else {
            self.appendShareLog("[PiP] ERROR missing target argument")
            result(
              FlutterError(
                code: "INVALID_ARGS",
                message: "Missing target",
                details: nil
              )
            )
            return
          }
          let deepLink = (args["deepLink"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
          let videoName: String
          if let provided = args["video"] as? String {
            videoName = provided
          } else {
            videoName = (target == "instagram")
              ? "assets/videos/instagram-tutorial.mp4"
              : "assets/videos/pip-test.mp4"
          }
          let assetKey = controller.lookupKey(forAsset: videoName)
          if self.pipTutorialManager == nil {
            self.pipTutorialManager = PipTutorialManager()
            self.pipTutorialManager?.logHandler = { [weak self] msg in
              self?.appendShareLog(msg)
            }
          }
          self.pipTutorialManager?.start(
            assetKey: assetKey,
            targetApp: target,
            deepLink: deepLink
          ) { success, errorMsg in
            if success {
              self.appendShareLog("[PiP] Started successfully for target \(target)")
              result(true)
            } else {
              self.appendShareLog("[PiP] FAILED for target \(target): \(errorMsg ?? "unknown error")")
              result(
                FlutterError(
                  code: "PIP_FAILED",
                  message: errorMsg ?? "Unable to start PiP tutorial",
                  details: nil
                )
              )
            }
          }
        case "openTarget":
          self.appendShareLog("[PiP] Flutter requested open target without tutorial")
          guard let args = call.arguments as? [String: Any],
                let target = args["target"] as? String else {
            result(
              FlutterError(
                code: "INVALID_ARGS",
                message: "Missing target",
                details: nil
              )
            )
            return
          }
          let deepLink = (args["deepLink"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
          if self.pipTutorialManager == nil {
            self.pipTutorialManager = PipTutorialManager()
            self.pipTutorialManager?.logHandler = { [weak self] msg in
              self?.appendShareLog(msg)
            }
          }
          self.pipTutorialManager?.openTargetOnly(
            targetApp: target,
            deepLink: deepLink
          ) { success, errorMsg in
            if success {
              self.appendShareLog("[PiP] Opened target successfully for \(target)")
            } else {
              self.appendShareLog("[PiP] Failed to open target \(target): \(errorMsg ?? "unknown error")")
            }
            result(success)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    let sharingIntent = SwiftReceiveSharingIntentPlugin.instance
    if sharingIntent.hasMatchingSchemePrefix(url: url) {
      return sharingIntent.application(app, open: url, options: options)
    }
    return super.application(app, open: url, options: options)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    pipTutorialManager?.stopIfNeededOnReturn()
  }

  // MARK: - Push Notifications (APNS Token Handling)

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    NSLog("[APNS] Registered for remote notifications")
    NSLog("[APNS] Device token: \(deviceToken.map { String(format: "%02.2hhx", $0) }.joined())")

    // Forward APNS token to Firebase (required when FirebaseAppDelegateProxyEnabled is false)
    Messaging.messaging().apnsToken = deviceToken

    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("[APNS] Failed to register for remote notifications: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    NSLog("[APNS] Received remote notification")

    // Forward to Firebase
    if let messageID = userInfo["gcm.message_id"] {
      NSLog("[APNS] Message ID: \(messageID)")
    }

    super.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
  }

  private func getAppGroupId() -> String? {
    let defaultGroupId = "group.\(Bundle.main.bundleIdentifier ?? "")"
    if let customGroupId = Bundle.main.object(forInfoDictionaryKey: "AppGroupId") as? String,
       !customGroupId.isEmpty,
       customGroupId != "$(CUSTOM_GROUP_ID)" {
      return customGroupId
    }
    return defaultGroupId
  }

  private func sharedUserDefaults() -> UserDefaults? {
    return UserDefaults(suiteName: getAppGroupId())
  }

  private func appendShareLog(_ message: String) {
    guard let defaults = sharedUserDefaults() else {
      NSLog("[ShareLogs] Unable to append, missing app group defaults")
      return
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let timestamp = formatter.string(from: Date())
    var entries = defaults.stringArray(forKey: shareLogsKey) ?? []
    entries.append("[\(timestamp)] \(message)")
    if entries.count > 200 {
      entries.removeFirst(entries.count - 200)
    }
    defaults.set(entries, forKey: shareLogsKey)
  }
}

class PipTutorialManager: NSObject {
  private var player: AVPlayer?
  private var playerLayer: AVPlayerLayer?
  private var pipController: AVPictureInPictureController?
  private var stopOnReturn = false
  private var pendingCompletion: ((Bool, String?) -> Void)?
  private var pendingTargetApp: String?
  private var pendingDeepLink: String?
  private weak var hostView: UIView?
  private var pipHasStarted = false
  private var hasOpenedTarget = false
  var logHandler: ((String) -> Void)?

  func start(
    assetKey: String,
    targetApp: String,
    deepLink: String?,
    completion: @escaping (Bool, String?) -> Void
  ) {
    // Clean up any previous PiP attempt before starting a new one
    cleanup()

    guard let path = Bundle.main.path(forResource: assetKey, ofType: nil) else {
      logHandler?("[PiP] Video not found at key \(assetKey)")
      completion(false, "Video not found: \(assetKey)")
      return
    }
    let videoUrl = URL(fileURLWithPath: path)
    logHandler?("[PiP] Prepared asset \(assetKey) for target \(targetApp)")

    do {
      let session = AVAudioSession.sharedInstance()
      // Use playback so PiP can start reliably; keep us silent and non-intrusive by mixing with others.
      try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers, .duckOthers])
      try session.setActive(true, options: [.notifyOthersOnDeactivation])
    } catch {
      NSLog("[PiP] Failed to set audio session: \(error.localizedDescription)")
      logHandler?("[PiP] Audio session setup failed: \(error.localizedDescription)")
    }

    let item = AVPlayerItem(url: videoUrl)
    let player = AVPlayer(playerItem: item)
    player.isMuted = true
    self.player = player

    guard AVPictureInPictureController.isPictureInPictureSupported() else {
      logHandler?("[PiP] Device does not support Picture in Picture")
      completion(false, "Picture in Picture is not supported on this device/simulator.")
      cleanup()
      return
    }

    let layer = AVPlayerLayer(player: player)
    layer.videoGravity = .resizeAspect
    playerLayer = layer

    // Attach the layer to a tiny hosting view so PiP can start reliably
    if let rootView = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .flatMap({ $0.windows })
      .first(where: { $0.isKeyWindow })?.rootViewController?.view {
      let host = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
      host.isHidden = true
      rootView.addSubview(host)
      layer.frame = host.bounds
      host.layer.addSublayer(layer)
      hostView = host
    }

    guard let controller = AVPictureInPictureController(playerLayer: layer) else {
      logHandler?("[PiP] Could not create AVPictureInPictureController (nil)")
      completion(false, "Unable to create PiP controller")
      cleanup()
      return
    }
    controller.delegate = self
    if #available(iOS 14.2, *) {
      // Enable automatic PiP for tutorial videos
      // This allows PiP to continue when user switches to target app (Instagram, etc.)
      // Requires "audio" background mode for PiP to work when app is backgrounded
      controller.canStartPictureInPictureAutomaticallyFromInline = true
    }
    pipController = controller

    // Hold onto the completion and target; execute once PiP actually starts
    pendingCompletion = { success, error in
      DispatchQueue.main.async {
        completion(success, error)
      }
    }
    pendingTargetApp = targetApp
    let cleanedDeepLink = deepLink?.trimmingCharacters(in: .whitespacesAndNewlines)
    pendingDeepLink = cleanedDeepLink?.isEmpty == true ? nil : cleanedDeepLink

    logHandler?("[PiP] Starting PiP for target \(targetApp)")
    player.play()
    controller.startPictureInPicture()

    // Fallback: if the delegate doesn't fire quickly, still open the target app
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      self?.openTargetIfNeeded(reason: "fallback-after-start")
    }
  }

  func openTargetOnly(
    targetApp: String,
    deepLink: String?,
    completion: @escaping (Bool, String?) -> Void
  ) {
    let cleanedDeepLink = deepLink?.trimmingCharacters(in: .whitespacesAndNewlines)
    let allowedDeepLink = cleanedDeepLink?.isEmpty == true ? nil : cleanedDeepLink
    guard let appSchemeURL = urlForTarget(targetApp, deepLink: nil) else {
      completion(false, "Unsupported target")
      return
    }

    if UIApplication.shared.canOpenURL(appSchemeURL) {
      let finalURL = urlForTarget(targetApp, deepLink: allowedDeepLink) ?? appSchemeURL
      UIApplication.shared.open(finalURL, options: [:]) { opened in
        completion(opened, opened ? nil : "Unable to open target app")
      }
      return
    }

    if let appStoreURL = appStoreURLForTarget(targetApp) {
      UIApplication.shared.open(appStoreURL, options: [:]) { opened in
        completion(opened, opened ? nil : "Unable to open App Store")
      }
      return
    }

    guard targetApp == "safari" else {
      completion(false, "App not installed")
      return
    }

    let fallbackURL = urlForTarget(targetApp, deepLink: allowedDeepLink)
    guard let fallbackURL = fallbackURL else {
      completion(false, "Unable to resolve target URL")
      return
    }
    UIApplication.shared.open(fallbackURL, options: [:]) { opened in
      completion(opened, opened ? nil : "Unable to open target app")
    }
  }

  func stopIfNeededOnReturn() {
    if stopOnReturn {
      stop()
    }
  }

  private func stop() {
    pipController?.stopPictureInPicture()
    cleanup()
    stopOnReturn = false
  }

  private func cleanup() {
    player?.pause()
    player = nil
    playerLayer = nil
    pipController = nil
    pendingCompletion = nil
    pendingTargetApp = nil
    hostView?.removeFromSuperview()
    hostView = nil
    pipHasStarted = false
    hasOpenedTarget = false
  }

  private func complete(_ success: Bool, error: String? = nil) {
    guard let completion = pendingCompletion else { return }
    pendingCompletion = nil
    completion(success, error)
  }

  private func openTargetIfNeeded(reason: String) {
    guard !hasOpenedTarget, let target = pendingTargetApp else { return }
    hasOpenedTarget = true

    // First check if the app is installed using its URL scheme
    guard let appSchemeURL = urlForTarget(target, deepLink: nil) else {
      logHandler?("[PiP] No URL scheme for target \(target) (\(reason))")
      return
    }

    // Check if the target app is installed
    if UIApplication.shared.canOpenURL(appSchemeURL) {
      // App is installed - use deep link if available, otherwise use app scheme
      let finalURL = urlForTarget(target, deepLink: pendingDeepLink) ?? appSchemeURL
      logHandler?("[PiP] Opening target app \(target) (\(reason))")
      UIApplication.shared.open(finalURL, options: [:], completionHandler: nil)
    } else {
      logHandler?("[PiP] Cannot open target app \(target) - app not installed (\(reason))")
      // App not installed - open App Store page instead
      if let appStoreURL = appStoreURLForTarget(target) {
        logHandler?("[PiP] Opening App Store for \(target)")
        UIApplication.shared.open(appStoreURL, options: [:], completionHandler: nil)
      } else {
        logHandler?("[PiP] No App Store URL available for \(target)")
      }
    }
  }

  private func appStoreURLForTarget(_ target: String) -> URL? {
    // App Store URLs for each app
    let appStoreID: String?
    switch target {
    case "instagram":
      appStoreID = "389801252"
    case "pinterest":
      appStoreID = "429047995"
    case "tiktok":
      appStoreID = "835599320"
    case "x":
      appStoreID = "333903271"
    case "imdb":
      appStoreID = "342792525"
    case "facebook":
      appStoreID = "284882215"
    case "photos", "safari":
      // Built-in iOS apps - no App Store link needed
      return nil
    default:
      return nil
    }

    guard let id = appStoreID else { return nil }
    return URL(string: "https://apps.apple.com/app/id\(id)")
  }

  private func urlForTarget(_ target: String, deepLink: String?) -> URL? {
    if let deepLink = deepLink, let url = URL(string: deepLink.trimmingCharacters(in: .whitespacesAndNewlines)), !deepLink.isEmpty {
      return url
    }
    switch target {
    case "instagram":
      return URL(string: "instagram://app")
    case "pinterest":
      return URL(string: "pinterest://")
    case "tiktok":
      return URL(string: "tiktok://")
    case "photos":
      return URL(string: "photos-redirect://")
    case "facebook":
      return URL(string: "fb://")
    case "imdb":
      return URL(string: "imdb://")
    case "safari":
      return URL(string: "http://www.google.com")
    case "x":
      return URL(string: "twitter://")
    default:
      return nil
    }
  }
}

extension PipTutorialManager: AVPictureInPictureControllerDelegate {
  func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
    stopOnReturn = true
    pipHasStarted = true
    logHandler?("[PiP] PiP started by system")
    openTargetIfNeeded(reason: "delegate-didStart")
    pendingTargetApp = nil
    complete(true, error: nil)
  }

  func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
    logHandler?("[PiP] PiP failed to start: \(error.localizedDescription)")
    complete(false, error: error.localizedDescription)
    cleanup()
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
    stopOnReturn = false
    logHandler?("[PiP] PiP stopped by system")
    cleanup()
  }
}

package com.worthify.worthify

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.res.ResourcesCompat
import android.graphics.BitmapFactory

class MainActivity: FlutterActivity() {
    private val launchLogTag = "WorthifyLaunch"
    private val shareLogsChannel = "worthify/share_extension_logs"
    private val shareStatusChannelName = "com.worthify.worthify/share_status"
    private val authChannelName = "worthify/auth"
    private val pipTutorialChannel = "pip_tutorial"
    private val shareStatusPrefs by lazy {
        getSharedPreferences("worthify_share_status", MODE_PRIVATE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareLogsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLogs" -> result.success(emptyList<String>())
                    "clearLogs" -> result.success(null)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareStatusChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "configureShareExtension" -> result.success(null)
                    "updateShareProcessingStatus" -> {
                        val status = (call.arguments as? Map<*, *>)?.get("status") as? String
                        if (status != null) {
                            shareStatusPrefs.edit().putString("processing_status", status).apply()
                        }
                        result.success(null)
                    }
                    "markShareProcessingComplete" -> {
                        shareStatusPrefs.edit().putString("processing_status", "completed").apply()
                        result.success(null)
                    }
                    "getShareProcessingSession" -> {
                        val status = shareStatusPrefs.getString("processing_status", null)
                        result.success(mapOf("sessionId" to null, "status" to status))
                    }
                    "getPendingSearchId" -> {
                        result.success(null)
                    }
                    "getPendingPlatformType" -> {
                        val platform = shareStatusPrefs.getString("pending_platform_type", null)
                        if (platform != null) {
                            shareStatusPrefs.edit().remove("pending_platform_type").apply()
                        }
                        result.success(platform)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, authChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setAuthFlag" -> {
                        val args = call.arguments as? Map<*, *>
                        val isAuthenticated = args?.get("isAuthenticated") as? Boolean
                        if (isAuthenticated == null) {
                            result.error("INVALID_ARGS", "isAuthenticated missing", null)
                            return@setMethodCallHandler
                        }
                        val userId = args["userId"] as? String
                        shareStatusPrefs.edit()
                            .putBoolean("user_authenticated", isAuthenticated)
                            .apply()
                        if (userId != null) {
                            shareStatusPrefs.edit()
                                .putString("supabase_user_id", userId)
                                .apply()
                        } else {
                            shareStatusPrefs.edit()
                                .remove("supabase_user_id")
                                .apply()
                        }
                        Log.d("WorthifyAuth", "setAuthFlag -> authenticated=$isAuthenticated userId=${userId ?: "null"}")
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pipTutorialChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val args = call.arguments as? Map<*, *>
                        val target = args?.get("target") as? String
                        val deepLink = (args?.get("deepLink") as? String)?.trim()
                        val video = args?.get("video") as? String
                            ?: if (target == "instagram") {
                                "assets/videos/instagram-tutorial.mp4"
                            } else {
                                "assets/videos/pip-test.mp4"
                            }
                        if (target == null) {
                            result.error("INVALID_ARGS", "Missing target", null)
                            return@setMethodCallHandler
                        }
                        val intent = Intent(this, TutorialPipActivity::class.java).apply {
                            putExtra("assetKey", video)
                            putExtra("target", target)
                            putExtra("deepLink", deepLink)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    }
                    "openTarget" -> {
                        val args = call.arguments as? Map<*, *>
                        val target = args?.get("target") as? String
                        val deepLink = (args?.get("deepLink") as? String)?.trim()
                        if (target == null) {
                            result.error("INVALID_ARGS", "Missing target", null)
                            return@setMethodCallHandler
                        }
                        val opened = openTutorialTarget(target, deepLink)
                        result.success(opened)
                    }
                    "stop" -> {
                        TutorialPipActivity.stopActive()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openTutorialTarget(target: String, deepLink: String?): Boolean {
        val cleanedDeepLink = deepLink?.trim()
        val packageCandidates = getTutorialPackageCandidatesForTarget(target)
        val canonicalPackageName = packageCandidates.firstOrNull()

        if (target == "photos") {
            for (intent in buildSystemPhotosIntents()) {
                if (tryStartIntent(intent)) return true
            }
            return false
        }

        // Web browsers option can still open a URL in browser.
        if (target == "safari") {
            val webIntent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse(if (!cleanedDeepLink.isNullOrEmpty()) cleanedDeepLink else "https://www.google.com")
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (tryStartIntent(webIntent)) return true
            return false
        }

        // 1) Try package-scoped deep link against known package candidates.
        if (!cleanedDeepLink.isNullOrEmpty()) {
            for (pkg in packageCandidates) {
                val deepLinkIntent = Intent(Intent.ACTION_VIEW, Uri.parse(cleanedDeepLink)).apply {
                    setPackage(pkg)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                if (tryStartIntent(deepLinkIntent)) return true
            }
        }

        // 2) Open app directly for any installed candidate package.
        for (pkg in packageCandidates) {
            val launchIntent = packageManager.getLaunchIntentForPackage(pkg)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (launchIntent != null && tryStartIntent(launchIntent)) return true
        }

        // 3) If the app is not installed (or launch failed), open its Play Store page.
        if (canonicalPackageName != null) {
            openTutorialTargetPlayStore(target)
            return true
        }

        return false
    }

    private fun tryStartIntent(intent: Intent): Boolean {
        return try {
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun buildSystemPhotosIntents(): List<Intent> {
        val galleryIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_APP_GALLERY)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        val viewImagesIntent = Intent(
            Intent.ACTION_VIEW,
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        ).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        val pickImageIntent = Intent(
            Intent.ACTION_PICK,
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        ).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        return listOf(galleryIntent, viewImagesIntent, pickImageIntent)
    }

    private fun getTutorialPackageCandidatesForTarget(target: String): List<String> {
        return when (target) {
            "instagram" -> listOf(
                "com.instagram.android",
                "com.instagram.lite"
            )
            "pinterest" -> listOf("com.pinterest")
            "tiktok" -> listOf("com.zhiliaoapp.musically", "com.ss.android.ugc.trill")
            "facebook" -> listOf("com.facebook.katana", "com.facebook.lite")
            "imdb" -> listOf("com.imdb.mobile")
            "x" -> listOf("com.twitter.android")
            else -> emptyList()
        }
    }

    private fun openTutorialTargetPlayStore(target: String) {
        val packageName = getTutorialPackageCandidatesForTarget(target).firstOrNull() ?: return

        val playStoreIntent = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$packageName"))
        playStoreIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        try {
            startActivity(playStoreIntent)
        } catch (_: Exception) {
            val browserIntent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("https://play.google.com/store/apps/details?id=$packageName")
            )
            browserIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                startActivity(browserIntent)
            } catch (_: Exception) {
                Log.e("MainActivity", "Failed to open Play Store for $packageName")
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        logSplashResourceState()
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        intent?.let {
            Log.d("WorthifyShare", "Intent received:")
            Log.d("WorthifyShare", "Action: ${it.action}")
            Log.d("WorthifyShare", "Type: ${it.type}")
            Log.d("WorthifyShare", "Data: ${it.data}")
            Log.d("WorthifyShare", "ClipData: ${it.clipData}")
            Log.d("WorthifyShare", "Extras: ${it.extras}")

            // Log all extras
            it.extras?.let { bundle ->
                for (key in bundle.keySet()) {
                    Log.d("WorthifyShare", "Extra $key: ${bundle.get(key)}")
                }
            }

            // Log ClipData items
            it.clipData?.let { clipData ->
                Log.d("WorthifyShare", "ClipData item count: ${clipData.itemCount}")
                for (i in 0 until clipData.itemCount) {
                    val item = clipData.getItemAt(i)
                    Log.d("WorthifyShare", "ClipData item $i: uri=${item.uri}, text=${item.text}")
                }
            }

            storeBrowserPlatform(it)
        }
    }

    private fun storeBrowserPlatform(intent: Intent) {
        val packageName = detectReferrerPackage(intent) ?: return
        val platformType = when (packageName.lowercase()) {
            "com.android.chrome", "com.chrome.beta", "com.chrome.dev", "com.chrome.canary" -> "chrome"
            "org.mozilla.firefox", "org.mozilla.firefox_beta", "org.mozilla.focus", "org.mozilla.klar" -> "firefox"
            "com.brave.browser", "com.brave.browser_beta" -> "brave"
            else -> null
        } ?: return

        shareStatusPrefs.edit().putString("pending_platform_type", platformType).apply()
        Log.d("WorthifyShare", "Detected browser source: $platformType (package=$packageName)")
    }

    private fun detectReferrerPackage(intent: Intent): String? {
        var packageName: String? = null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            val parcelableReferrer: Uri? = intent.getParcelableExtra(Intent.EXTRA_REFERRER)
                ?: intent.getStringExtra(Intent.EXTRA_REFERRER_NAME)?.let { Uri.parse(it) }
                ?: referrer

            parcelableReferrer?.let { uri ->
                when {
                    uri.scheme == "android-app" -> packageName = uri.host
                    uri.scheme == "https" && uri.host == "android-app" && uri.pathSegments.isNotEmpty() -> {
                        packageName = uri.pathSegments.last()
                    }
                }
            }
        }

        if (packageName.isNullOrEmpty()) {
            val referrerName = intent.getStringExtra(Intent.EXTRA_REFERRER_NAME)
            if (!referrerName.isNullOrEmpty()) {
                packageName = referrerName.removePrefix("android-app://")
            }
        }

        return packageName
    }

    private fun logSplashResourceState() {
        val splashId = resources.getIdentifier("transparent_splash_icon", "drawable", packageName)
        if (splashId != 0) {
            val bmp = BitmapFactory.decodeResource(resources, splashId)
            Log.d(
                launchLogTag,
                "transparent_splash_icon -> resId=$splashId size=${bmp.width}x${bmp.height}"
            )
        } else {
            Log.w(launchLogTag, "transparent_splash_icon drawable not found at runtime")
        }
        val bgColorId = resources.getIdentifier("splash_background", "color", packageName)
        if (bgColorId != 0) {
            val color = ResourcesCompat.getColor(resources, bgColorId, theme)
            Log.d(launchLogTag, "splash_background -> color=#${Integer.toHexString(color)}")
        } else {
            Log.w(launchLogTag, "splash_background color not found at runtime")
        }
    }
}

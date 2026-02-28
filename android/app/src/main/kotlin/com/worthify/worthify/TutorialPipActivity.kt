package com.worthify.worthify

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.res.Configuration
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.util.Rational
import android.provider.MediaStore
import android.widget.FrameLayout
import android.widget.VideoView
import androidx.appcompat.app.AppCompatActivity
import io.flutter.FlutterInjector
import java.io.File
import java.lang.ref.WeakReference
import android.media.AudioAttributes

class TutorialPipActivity : AppCompatActivity() {
  private var videoView: VideoView? = null
  private var hasStartedPip = false
  private fun stopAndFinish() {
    hasStartedPip = false
    try {
      videoView?.stopPlayback()
    } catch (_: Exception) {
      // ignore stop errors
    }
    if (!isFinishing) {
      finishAndRemoveTask()
    }
  }

  companion object {
    private var currentInstance: WeakReference<TutorialPipActivity>? = null

    fun stopActive() {
      currentInstance?.get()?.let { activity ->
        activity.runOnUiThread {
          activity.stopAndFinish()
        }
      }
    }
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    currentInstance = WeakReference(this)

    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      finish()
      return
    }

        val container = FrameLayout(this)
        videoView = VideoView(this)
        container.addView(
            videoView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
        setContentView(container)

        val assetKey = intent.getStringExtra("assetKey") ?: run {
            finish()
            return
        }
        Log.d("TutorialPip", "assetKey=$assetKey")
        val target = intent.getStringExtra("target") ?: ""
        val deepLink = intent.getStringExtra("deepLink")

        val videoFile = copyAssetToCache(assetKey)
        if (videoFile == null) {
            finish()
            return
        }

        videoView?.setVideoURI(Uri.fromFile(videoFile))
        videoView?.setOnPreparedListener { mp: MediaPlayer ->
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                    .build()
            )
            mp.isLooping = true
            mp.setVolume(0f, 0f)
            videoView?.start()
            enterPipAndLaunch(target, deepLink, mp.videoWidth, mp.videoHeight)
        }
        videoView?.setOnErrorListener { _, _, _ ->
            finish()
            true
        }
    }

    private fun copyAssetToCache(assetKey: String): File? {
        return try {
            val lookup = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(assetKey)
            val input = assets.open(lookup)
            val outFile = File(cacheDir, "pip_tutorial_${System.currentTimeMillis()}.mp4")
            outFile.outputStream().use { output ->
                input.copyTo(output)
            }
            outFile
        } catch (e: Exception) {
            Log.e("TutorialPip", "copyAssetToCache failed: ${e.message}")
            null
        }
    }

    private fun enterPipAndLaunch(target: String, deepLink: String?, videoWidth: Int?, videoHeight: Int?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val builder = PictureInPictureParams.Builder()
            val width = videoWidth ?: 9
            val height = videoHeight ?: 16
            if (width > 0 && height > 0) {
                builder.setAspectRatio(Rational(width, height))
            }
            val params = builder.build()
            enterPictureInPictureMode(params)
            hasStartedPip = true
        }
        openTarget(target, deepLink)
    }

    private fun openTarget(target: String, deepLink: String?) {
        if (target == "photos") {
            for (intent in buildSystemPhotosIntents()) {
                if (tryStartIntent(intent)) return
            }
            return
        }

        val cleanedDeepLink = deepLink?.trim()
        val packageName = getPackageNameForTarget(target)

        // First check if the app is installed
        val isAppInstalled = packageName != null && try {
            packageManager.getPackageInfo(packageName, 0)
            true
        } catch (_: Exception) {
            false
        }

        if (!isAppInstalled && packageName != null) {
            // App not installed - open Play Store
            Log.d("TutorialPip", "App not installed for target $target, opening Play Store")
            openPlayStore(target)
            return
        }

        // App is installed or no package name (built-in apps) - proceed with opening
        val intent = if (!cleanedDeepLink.isNullOrEmpty() && isAppInstalled) {
            // Use deep link only if app is installed
            Intent(Intent.ACTION_VIEW, Uri.parse(cleanedDeepLink)).apply {
                if (packageName != null) {
                    setPackage(packageName)
                }
            }
        } else {
            when (target) {
                "instagram" -> packageIntent("com.instagram.android", "https://instagram.com")
                "pinterest" -> packageIntent("com.pinterest", "https://www.pinterest.com")
                "tiktok" -> packageIntent("com.zhiliaoapp.musically", "https://www.tiktok.com")
                "photos" -> packageIntent("com.google.android.apps.photos", "https://photos.google.com")
                "facebook" -> packageIntent("com.facebook.katana", "https://www.facebook.com")
                "imdb" -> packageIntent("com.imdb.mobile", "https://www.imdb.com")
                "safari" -> packageIntent(null, "https://www.google.com")
                "x" -> packageIntent("com.twitter.android", "https://twitter.com")
                else -> null
            }
        }

        if (intent != null) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            val started = tryStartIntent(intent)
            if (!started && packageName != null) {
                // If still fails and we have a package name, try opening Play Store
                openPlayStore(target)
            }
        }
    }

    private fun getPackageNameForTarget(target: String): String? {
        return when (target) {
            "instagram" -> "com.instagram.android"
            "pinterest" -> "com.pinterest"
            "tiktok" -> "com.zhiliaoapp.musically"
            "facebook" -> "com.facebook.katana"
            "imdb" -> "com.imdb.mobile"
            "x" -> "com.twitter.android"
            else -> null
        }
    }

    private fun openPlayStore(target: String) {
        val packageName = getPackageNameForTarget(target) ?: return

        // Try to open Play Store app first
        val playStoreIntent = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$packageName"))
        playStoreIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        try {
            startActivity(playStoreIntent)
            Log.d("TutorialPip", "Opened Play Store for $packageName")
        } catch (_: Exception) {
            // Play Store app not available - open web browser instead
            val browserIntent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("https://play.google.com/store/apps/details?id=$packageName")
            )
            browserIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                startActivity(browserIntent)
                Log.d("TutorialPip", "Opened Play Store web page for $packageName")
            } catch (_: Exception) {
                Log.e("TutorialPip", "Failed to open Play Store for $packageName")
            }
        }
    }

    private fun packageIntent(packageName: String?, fallbackUrl: String): Intent {
        return if (packageName != null) {
            Intent(Intent.ACTION_VIEW).setPackage(packageName).setData(Uri.parse(fallbackUrl))
        } else {
            Intent(Intent.ACTION_VIEW, Uri.parse(fallbackUrl))
        }
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

  override fun onPictureInPictureModeChanged(
    isInPictureInPictureMode: Boolean,
    newConfig: Configuration
  ) {
    super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
    if (!isInPictureInPictureMode && hasStartedPip) {
      stopAndFinish()
    }
  }

  override fun onResume() {
    super.onResume()
    if (hasStartedPip && !isInPictureInPictureMode) {
      stopAndFinish()
    }
  }

  override fun onDestroy() {
    super.onDestroy()
    if (currentInstance?.get() === this) {
      currentInstance = null
    }
  }
}

package tech.pavii.hyperox

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// local_auth (biometric app lock) needs a FragmentActivity.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Drop the system splash the moment Flutter draws: no system exit
            // animation. The Flutter intro is drawn on the same pixels and is
            // the only transition.
            splashScreen.setOnExitAnimationListener { it.remove() }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hyperox/splash")
            .setMethodCallHandler { call, result ->
                if (call.method == "setTheme") {
                    // Android 13+ keeps this for the next cold start.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        val light = call.argument<Boolean>("light") ?: true
                        splashScreen.setSplashScreenTheme(
                            if (light) R.style.LaunchTheme_Light else R.style.LaunchTheme_Dark,
                        )
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}

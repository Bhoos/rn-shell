package com.reactnativeshell.updates

import android.content.Context
import android.content.pm.ApplicationInfo
import android.util.Log
import com.facebook.react.bridge.JSBundleLoader
import com.facebook.react.bridge.JSBundleLoaderDelegate
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Where a release build with "sources" (rn_shell_sources: a development
 * build, `rn-shell --variant`) loads its JavaScript from, chosen in the app
 * and kept in its preferences:
 *
 *   metro    a Metro server (`rn-shell start`), its URL: the bundle it serves
 *            as a release build would run it (dev=false), each launch and
 *            reload; when Metro isn't reachable, or the last bundle it served
 *            never rendered, the release source's bundle instead
 *   release  over the air updates from a release server, its URL (the
 *            build's rn_shell_updates_url unless another was chosen), else the
 *            bundle the app was built with
 */
object BundleSource {
  private const val TAG = "RNShellSource"
  private const val PREFS = "rn-shell-source"
  private const val METRO_LOADING = "metroLoading" // a Metro bundle loaded, not yet rendered

  /** Why the last load didn't use Metro although it was chosen, or null. */
  @Volatile var fallback: String? = null
    private set
  /** The running bundle came from Metro. */
  @Volatile var runningMetro = false
    private set

  /** This build chooses its source (rn_shell_sources), and isn't debuggable (those always use Metro). */
  fun enabled(context: Context): Boolean {
    if ((context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) return false
    val id = context.resources.getIdentifier("rn_shell_sources", "bool", context.packageName)
    return id != 0 && context.resources.getBoolean(id)
  }

  private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  /** "metro" or "release". */
  fun kind(context: Context) = if (prefs(context).getString("kind", null) == "metro") "metro" else "release"
  /** The Metro server's URL (http://host:port), or null. */
  fun metroUrl(context: Context) = prefs(context).getString("metroUrl", null)?.ifEmpty { null }
  /** The release server's URL chosen, or null for the build's. */
  fun releaseUrl(context: Context) = prefs(context).getString("releaseUrl", null)?.ifEmpty { null }

  /** Keeps the source (a URL of null or "" for the release source: the build's). */
  fun set(context: Context, kind: String, url: String?) {
    prefs(context).edit().apply {
      if (kind == "metro") {
        putString("kind", "metro")
        if (!url.isNullOrEmpty()) putString("metroUrl", url)
      } else {
        putString("kind", "release")
        putString("releaseUrl", url ?: "")
      }
      // A new choice is tried again, even if Metro's last bundle didn't render
      remove(METRO_LOADING)
    }.commit()
  }

  /** The running bundle rendered (a Metro bundle that didn't is skipped on the next launch). */
  fun ready(context: Context) {
    if (runningMetro) prefs(context).edit().remove(METRO_LOADING).commit()
  }

  /**
   * Metro's bundle, downloaded now: its URL and the file it's in, or null when
   * the source isn't Metro, Metro doesn't answer or fails to bundle, or its
   * last bundle didn't render (`fallback` says why). Blocks: it bundles.
   */
  @Synchronized
  fun metroBundle(context: Context): Pair<String, File>? {
    fallback = null
    runningMetro = false
    if (!enabled(context) || kind(context) != "metro") return null
    val metro = metroUrl(context) ?: run {
      fallback = "No Metro server was given"
      return null
    }
    val prefs = prefs(context)
    if (prefs.getBoolean(METRO_LOADING, false)) {
      // Its last bundle never rendered (it failed, or the app was killed): not again now,
      // so the app can start and another source be chosen; the next launch tries again
      prefs.edit().remove(METRO_LOADING).commit()
      fallback = "Metro's last bundle didn't start"
      return null
    }
    // The bundle a release build runs (no development tools), from the shell's index.js
    val url = "$metro/index.bundle?platform=android&dev=false&minify=false&app=${context.packageName}"
    val file = File(context.cacheDir, "rn-shell-metro.bundle")
    try {
      val connection = URL(url).openConnection() as HttpURLConnection
      connection.connectTimeout = 2_000
      connection.readTimeout = 300_000 // the first bundle takes a while
      try {
        val code = connection.responseCode
        if (code != 200) {
          val body = connection.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
          fallback = "Metro couldn't bundle (HTTP $code): ${body.take(300)}"
          return null
        }
        val tmp = File(context.cacheDir, "rn-shell-metro.bundle.tmp")
        connection.inputStream.use { input -> tmp.outputStream().use { input.copyTo(it) } }
        tmp.renameTo(file)
      } finally {
        connection.disconnect()
      }
    } catch (e: Exception) {
      Log.w(TAG, "Metro at $metro: ${e.message}")
      fallback = "Metro isn't running at $metro"
      return null
    }
    prefs.edit().putBoolean(METRO_LOADING, true).commit()
    runningMetro = true
    return url to file
  }

  /**
   * The release build's bundle loader (MainApplication): Metro's bundle when
   * it's the source, else a downloaded update for this build, else the one it
   * was built with. Each load chooses again, so a reload takes a new source.
   */
  @JvmStatic
  fun loader(context: Context, assetUrl: String = "assets://index.android.bundle"): JSBundleLoader =
    object : JSBundleLoader() {
      override fun loadScript(delegate: JSBundleLoaderDelegate): String {
        metroBundle(context)?.let { (url, file) ->
          // Its URL as the source: assets come from Metro, as in development
          delegate.loadScriptFromFile(file.absolutePath, url, false)
          return url
        }
        UpdatesStore.bundlePath(context)?.let { path ->
          delegate.loadScriptFromFile(path, path, false)
          return path
        }
        delegate.loadScriptFromAssets(context.assets, assetUrl, true)
        return assetUrl
      }
    }
}

package com.reactnativeshell.updates

import android.content.Context
import android.content.pm.ApplicationInfo
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.X509EncodedKeySpec

/**
 * Over the air updates. The app's resources hold what the build was made
 * with (android/app/build.gradle): rn_shell_updates_url, rn_shell_updates_key
 * (the publisher's P-256 public key, SPKI in base64), rn_shell_runtime_version
 * and rn_shell_embedded_id.
 *
 * Updates live in files/rn-shell-updates, one directory each (the bundle and
 * its assets), with state.json:
 *   binary, runtimeVersion  the build the updates below were downloaded for
 *   current   { id, message, status: new | launching | ok }: the update that runs
 *   previous  { id, message }: the last one that rendered, kept until current does
 *   pending   { id, message, embedded }: downloaded, started on the next launch
 *   lastId    the newest id taken (an older one is never taken again), at first
 *             the build's (rn_shell_embedded_id: when it was made)
 *   failed    ids that didn't render
 */
class UpdatesStore private constructor(context: Context) {
  private val root = File(context.filesDir, "rn-shell-updates")
  private val baseUrl: String?
  private val publicKey: ByteArray?
  private val runtimeVersion: String
  private val binary: String
  private val embeddedId: Long
  private val debuggable = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
  private var loaded: JSONObject? = null
  private val checks = Any()

  init {
    fun resource(name: String): String {
      val id = context.resources.getIdentifier(name, "string", context.packageName)
      return if (id == 0) "" else context.getString(id)
    }
    val url = resource("rn_shell_updates_url")
    val key = resource("rn_shell_updates_key")
    baseUrl = url.ifEmpty { null }?.let { if (it.endsWith("/")) it else "$it/" }
    publicKey = key.ifEmpty { null }?.let { Base64.decode(it, Base64.DEFAULT) }
    runtimeVersion = resource("rn_shell_runtime_version")
    // When the build was made: updates published before it are older than its own bundle
    embeddedId = resource("rn_shell_embedded_id").toLongOrNull() ?: 0
    @Suppress("DEPRECATION")
    val info = context.packageManager.getPackageInfo(context.packageName, 0)
    @Suppress("DEPRECATION")
    binary = "${info.versionName} (${info.versionCode}) $embeddedId"
  }

  /** Updates are configured (an URL and a key) and this isn't a debuggable build. */
  val enabled get() = !debuggable && baseUrl != null && publicKey != null && runtimeVersion.isNotEmpty()

  // State

  private fun dirOf(update: JSONObject) = File(root, update.getLong("id").toString())

  private fun remove(update: JSONObject?) {
    if (update != null && !update.optBoolean("embedded")) dirOf(update).deleteRecursively()
  }

  /** The state, loaded once; a different build starts over (its updates were for another one). */
  private val state: JSONObject
    get() {
      loaded?.let { return it }
      val saved = try {
        JSONObject(File(root, "state.json").readText())
      } catch (e: Exception) {
        null
      }
      val state = if (saved != null && saved.optString("binary") == binary && saved.optString("runtimeVersion") == runtimeVersion) {
        saved
      } else {
        root.deleteRecursively()
        JSONObject().put("binary", binary).put("runtimeVersion", runtimeVersion).put("lastId", embeddedId).put("failed", JSONArray())
      }
      loaded = state
      return state
    }

  private fun save() {
    root.mkdirs()
    val tmp = File(root, "state.json.tmp")
    tmp.writeText(state.toString())
    tmp.renameTo(File(root, "state.json"))
  }

  private fun failed(id: Long): Boolean {
    val failed = state.optJSONArray("failed") ?: return false
    return (0 until failed.length()).any { failed.getLong(it) == id }
  }

  // Launch

  /**
   * The bundle to start: the downloaded update for this build, or null for
   * the embedded one. Call once per launch: a new update is tried once, and
   * if the app doesn't call `ready` on it, the next launch goes back to the
   * one before.
   */
  @Synchronized
  fun launch(): String? {
    if (!enabled) return null
    val state = state
    state.optJSONObject("pending")?.let { pending ->
      state.remove("pending")
      if (pending.optBoolean("embedded")) {
        remove(state.optJSONObject("current"))
        remove(state.optJSONObject("previous"))
        state.remove("current")
        state.remove("previous")
      } else {
        val current = state.optJSONObject("current")
        if (current?.optString("status") == "ok") {
          remove(state.optJSONObject("previous"))
          state.put("previous", JSONObject().put("id", current.getLong("id")).put("message", current.opt("message")))
        } else {
          remove(current)
        }
        state.put("current", JSONObject().put("id", pending.getLong("id")).put("message", pending.opt("message")).put("status", "new"))
      }
    }

    var current = state.optJSONObject("current")
    if (current?.optString("status") == "launching") {
      // The last launch didn't render it: back to the one before
      Log.w(TAG, "update ${current.getLong("id")} didn't start, rolled back")
      state.getJSONArray("failed").put(current.getLong("id"))
      remove(current)
      current = state.optJSONObject("previous")?.put("status", "ok")
      state.remove("previous")
    }
    if (current != null && !File(dirOf(current), BUNDLE).exists()) current = null
    if (current?.optString("status") == "new") current.put("status", "launching")
    if (current != null) state.put("current", current) else state.remove("current")
    save()
    return current?.let { File(dirOf(it), BUNDLE).absolutePath }
  }

  @Synchronized
  fun ready() {
    if (!enabled) return
    val current = state.optJSONObject("current") ?: return
    if (current.optString("status") != "launching") return
    current.put("status", "ok")
    remove(state.optJSONObject("previous"))
    state.remove("previous")
    save()
  }

  @Synchronized
  fun info(): Map<String, Any?> {
    val current = if (enabled) state.optJSONObject("current") else null
    val pending = if (enabled) state.optJSONObject("pending") else null
    return mapOf(
      "enabled" to enabled,
      "runtimeVersion" to runtimeVersion,
      "updateId" to current?.getLong("id"),
      "message" to current?.optString("message")?.takeIf { !current.isNull("message") },
      "pending" to pending?.let { mapOf("id" to it.getLong("id"), "embedded" to it.optBoolean("embedded")) },
    )
  }

  // Check

  /** Looks for an update and downloads it (blocking: call it off the main thread). */
  fun check(): Map<String, Any?> {
    if (!enabled) return mapOf("status" to "disabled")
    synchronized(checks) { return checkOnce() }
  }

  private fun checkOnce(): Map<String, Any?> {
    val latest = get("$baseUrl$PLATFORM/$runtimeVersion/latest.json") ?: return mapOf("status" to "none")

    // { manifest: "<json>", signature: "<base64, DER>" }, signed by the publisher's key
    val signed = JSONObject(String(latest))
    val text = signed.getString("manifest")
    if (!verify(text.toByteArray(), Base64.decode(signed.getString("signature"), Base64.DEFAULT))) {
      throw IOException("The update's signature doesn't match the app's key")
    }
    val manifest = JSONObject(text)
    if (manifest.optString("platform") != PLATFORM || manifest.optString("runtimeVersion") != runtimeVersion || !manifest.has("id")) {
      throw IOException("The update isn't for this build")
    }
    val id = manifest.getLong("id")
    val embedded = manifest.optBoolean("embedded")
    val message = if (manifest.isNull("message")) null else manifest.optString("message")
    synchronized(this) {
      // An older update (replayed, or rolled back from) is never taken again
      if (id <= state.optLong("lastId") || failed(id)) return mapOf("status" to "upToDate")
    }

    if (!embedded) {
      val dir = File(root, id.toString())
      val tmp = File(root, "$id.download")
      tmp.deleteRecursively()
      try {
        val files = mutableListOf(BUNDLE to manifest.getString("bundle"))
        manifest.optJSONArray("assets")?.let { assets ->
          for (i in 0 until assets.length()) {
            val asset = assets.getJSONObject(i)
            files.add(asset.getString("path") to asset.getString("hash"))
          }
        }
        for ((path, hash) in files) {
          if (!safePath(path) || hash.length != 64) throw IOException("The update names a file it can't have")
          val content = get("${baseUrl}files/$hash")
          if (content == null || sha256(content) != hash.lowercase()) throw IOException("The update's $path didn't download")
          val target = File(tmp, path)
          target.parentFile?.mkdirs()
          target.writeBytes(content)
        }
        dir.deleteRecursively()
        if (!tmp.renameTo(dir)) throw IOException("The update couldn't be saved")
      } finally {
        tmp.deleteRecursively()
      }
    }

    synchronized(this) {
      remove(state.optJSONObject("pending"))
      state.put("pending", JSONObject().put("id", id).put("message", message ?: JSONObject.NULL).put("embedded", embedded))
      state.put("lastId", id)
      save()
    }
    return mapOf("status" to "downloaded", "id" to id, "embedded" to embedded, "message" to message)
  }

  // Plugins

  /** Downloaded plugin bundles, by SHA-256. */
  val pluginsDir get() = File(root, "plugins")

  /** A signed index's manifest, if it's the publisher's and for this build. */
  private fun pluginManifest(signed: String): JSONObject? = try {
    val outer = JSONObject(signed)
    val text = outer.getString("manifest")
    val manifest = JSONObject(text)
    if (verify(text.toByteArray(), Base64.decode(outer.getString("signature"), Base64.DEFAULT)) &&
      manifest.optString("platform") == PLATFORM && manifest.optString("runtimeVersion") == runtimeVersion
    ) manifest else null
  } catch (e: Exception) {
    null
  }

  /**
   * The plugin index's manifest (text): fetched when it's newer than the one
   * saved (which is kept, for launches offline), else the saved one; null if neither.
   */
  fun pluginIndex(): String? {
    if (!enabled) return null
    synchronized(this) { state }
    val saved = File(root, "plugins.json")
    val savedManifest = if (saved.exists()) pluginManifest(saved.readText()) else null
    val fetched = try {
      get("$baseUrl$PLATFORM/$runtimeVersion/plugins.json")?.let { String(it) }
    } catch (e: IOException) {
      null
    }
    val fetchedManifest = fetched?.let { pluginManifest(it) ?: throw IOException("The plugin index's signature doesn't match the app's key") }
    if (fetchedManifest != null && fetchedManifest.optLong("id") > (savedManifest?.optLong("id") ?: -1)) {
      root.mkdirs()
      val tmp = File(root, "plugins.json.tmp")
      tmp.writeText(fetched)
      tmp.renameTo(saved)
      return fetchedManifest.toString()
    }
    return savedManifest?.toString()
  }

  /** Downloads a plugin's bundle (named in the signed index by its SHA-256), unless it's here. */
  fun fetchPlugin(hash: String) {
    if (!enabled) throw IOException("Plugins load from the development server in debug builds")
    if (!Regex("^[0-9a-f]{64}$").matches(hash)) throw IOException("Not a plugin's hash: $hash")
    synchronized(this) { state }
    val file = File(pluginsDir, hash)
    if (file.exists()) return
    val content = get("${baseUrl}files/$hash")
    if (content == null || sha256(content) != hash) throw IOException("The plugin $hash didn't download")
    pluginsDir.mkdirs()
    val tmp = File(pluginsDir, "$hash.download")
    tmp.writeBytes(content)
    if (!tmp.renameTo(file)) throw IOException("The plugin $hash couldn't be saved")
  }

  /** ECDSA P-256 with SHA-256, the signature in DER; the key is SPKI. */
  private fun verify(message: ByteArray, signature: ByteArray): Boolean = try {
    val key = KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(publicKey))
    Signature.getInstance("SHA256withECDSA").run {
      initVerify(key)
      update(message)
      verify(signature)
    }
  } catch (e: Exception) {
    false
  }

  /** The body, or null on 404. */
  private fun get(url: String): ByteArray? {
    val connection = URL(url).openConnection() as HttpURLConnection
    connection.useCaches = false
    connection.connectTimeout = 30_000
    connection.readTimeout = 60_000
    try {
      return when (val code = connection.responseCode) {
        200 -> connection.inputStream.use { it.readBytes() }
        404 -> null
        else -> throw IOException("$url: HTTP $code")
      }
    } finally {
      connection.disconnect()
    }
  }

  companion object {
    private const val TAG = "RNShellUpdates"
    private const val PLATFORM = "android"
    private const val BUNDLE = "index.android.bundle"

    @Volatile private var instance: UpdatesStore? = null
    private var launched: Result<String?>? = null

    fun get(context: Context): UpdatesStore =
      instance ?: synchronized(this) { instance ?: UpdatesStore(context.applicationContext).also { instance = it } }

    /** The bundle to start (MainApplication's jsBundleFilePath): a downloaded update, or null for the embedded one. */
    @JvmStatic
    @Synchronized
    fun bundlePath(context: Context): String? {
      // Once per process: a second launch would take the update as one that didn't start
      launched?.let { return it.getOrNull() }
      val path = try {
        get(context).launch()
      } catch (e: Exception) {
        Log.e(TAG, "couldn't read the updates", e)
        null
      }
      launched = Result.success(path)
      return path
    }

    private fun safePath(path: String) =
      path.isNotEmpty() && !path.startsWith("/") && !path.contains('\\') &&
        path.split('/').none { it.isEmpty() || it == "." || it == ".." }

    private fun sha256(bytes: ByteArray) =
      MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
  }
}

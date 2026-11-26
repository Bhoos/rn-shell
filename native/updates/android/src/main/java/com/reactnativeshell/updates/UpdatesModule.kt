package com.reactnativeshell.updates

import com.facebook.proguard.annotations.DoNotStrip
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.ReactApplication
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.UiThreadUtil
import com.facebook.react.turbomodule.core.interfaces.BindingsInstallerHolder
import com.facebook.react.turbomodule.core.interfaces.TurboModuleWithJSIBindings
import kotlin.concurrent.thread

/**
 * Over the air updates for JavaScript: what's running, checking for a newer
 * one, keeping a new one; and plugins (their index, their bundles, and
 * global.__rnShellLoadPlugin, installed by the C++ in ../cpp).
 */
class UpdatesModule(reactContext: ReactApplicationContext) : NativeUpdatesSpec(reactContext), TurboModuleWithJSIBindings {
  override fun getName() = NAME

  private val store get() = UpdatesStore.get(reactApplicationContext)

  override fun info(promise: Promise) {
    promise.resolve(Arguments.makeNativeMap(store.info()))
  }

  override fun check(promise: Promise) {
    thread(name = "rn-shell-updates") {
      val result = try {
        store.check()
      } catch (e: Exception) {
        mapOf("status" to "failed", "error" to (e.message ?: "The update check failed"))
      }
      promise.resolve(Arguments.makeNativeMap(result))
    }
  }

  override fun ready() {
    store.ready()
    BundleSource.ready(reactApplicationContext)
  }

  override fun source(promise: Promise) {
    val context = reactApplicationContext
    if (!BundleSource.enabled(context)) {
      promise.resolve(null)
      return
    }
    val running = when {
      BundleSource.runningMetro -> "metro"
      store.info()["updateId"] != null -> "update"
      else -> "embedded"
    }
    promise.resolve(Arguments.makeNativeMap(mapOf(
      "kind" to BundleSource.kind(context),
      "metroUrl" to (BundleSource.metroUrl(context) ?: ""),
      "releaseUrl" to store.url,
      "buildReleaseUrl" to store.buildUrl,
      "running" to running,
      "fallback" to BundleSource.fallback,
    )))
  }

  override fun setSource(kind: String, url: String, promise: Promise) {
    val context = reactApplicationContext
    if (!BundleSource.enabled(context)) {
      promise.reject("source", "This build loads its own bundle (no \"sources\")")
      return
    }
    thread(name = "rn-shell-updates") {
      BundleSource.set(context, kind, url)
      if (kind != "metro") {
        // The release server's latest, started by the reload below
        store.useUrl(url)
        try {
          store.check()
        } catch (_: Exception) {
        }
        UpdatesStore.relaunch()
      }
      promise.resolve(null)
      UiThreadUtil.runOnUiThread {
        (context.applicationContext as? ReactApplication)?.reactHost?.reload("rn-shell: the bundle's source changed")
      }
    }
  }

  override fun pluginIndex(promise: Promise) {
    thread(name = "rn-shell-updates") {
      try {
        promise.resolve(store.pluginIndex())
      } catch (e: Exception) {
        promise.reject("plugins", e.message ?: "The plugin index couldn't be read", e)
      }
    }
  }

  override fun fetchPlugin(hash: String, promise: Promise) {
    thread(name = "rn-shell-updates") {
      try {
        store.fetchPlugin(hash)
        promise.resolve(null)
      } catch (e: Exception) {
        promise.reject("plugins", e.message ?: "The plugin didn't download", e)
      }
    }
  }

  /** Where plugin bundles are (the C++ loader reads them there). */
  @DoNotStrip
  fun pluginsDir(): String = store.pluginsDir.absolutePath

  @DoNotStrip
  external override fun getBindingsInstaller(): BindingsInstallerHolder

  companion object {
    const val NAME = "RNShellUpdates"

    init {
      System.loadLibrary("rnshellupdates")
    }
  }
}

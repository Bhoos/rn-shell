package com.reactnativeshell.updates

import com.facebook.proguard.annotations.DoNotStrip
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
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

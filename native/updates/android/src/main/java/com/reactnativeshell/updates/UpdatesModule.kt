package com.reactnativeshell.updates

import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import kotlin.concurrent.thread

/** Over the air updates for JavaScript: what's running, checking for a newer one, keeping a new one. */
class UpdatesModule(reactContext: ReactApplicationContext) : NativeUpdatesSpec(reactContext) {
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

  companion object {
    const val NAME = "RNShellUpdates"
  }
}

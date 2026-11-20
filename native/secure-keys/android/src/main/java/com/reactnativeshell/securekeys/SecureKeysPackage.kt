package com.reactnativeshell.securekeys

import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider

@Suppress("unused")
class SecureKeysPackage : BaseReactPackage() {
  override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? =
    if (name == SecureKeysModule.NAME) SecureKeysModule(reactContext) else null

  override fun getReactModuleInfoProvider() = ReactModuleInfoProvider {
    mapOf(
      SecureKeysModule.NAME to ReactModuleInfo(
        SecureKeysModule.NAME,
        SecureKeysModule::class.java.name,
        false, // canOverrideExistingModule
        false, // needsEagerInit
        false, // isCxxModule
        true, // isTurboModule
      ),
    )
  }
}

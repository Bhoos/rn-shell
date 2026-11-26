package com.reactnativeshell

import android.app.Application
import com.facebook.react.PackageList
import com.facebook.react.ReactApplication
import com.facebook.react.ReactHost
import com.facebook.react.ReactNativeApplicationEntryPoint.loadReactNative
import com.facebook.react.common.annotations.UnstableReactNativeAPI
import com.facebook.react.defaults.DefaultComponentsRegistry
import com.facebook.react.defaults.DefaultReactHost.getDefaultReactHost
import com.facebook.react.defaults.DefaultReactHostDelegate
import com.facebook.react.defaults.DefaultTurboModuleManagerDelegate
import com.facebook.react.fabric.ComponentFactory
import com.facebook.react.runtime.ReactHostImpl
import com.facebook.react.runtime.hermes.HermesInstance
import com.reactnativeshell.updates.BundleSource

@OptIn(UnstableReactNativeAPI::class)
class MainApplication : Application(), ReactApplication {

  override val reactHost: ReactHost by lazy {
    val packages =
      PackageList(this).packages.apply {
        // Packages that cannot be autolinked yet can be added manually here, for example:
        // add(MyReactNativePackage())
      }
    if (BuildConfig.DEBUG) {
      // Metro, with the development tools
      getDefaultReactHost(context = applicationContext, packageList = packages)
    } else {
      // getDefaultReactHost's, with the shell's bundle loader (native/updates): a
      // development build's Metro server (BundleSource), else a downloaded update for
      // this build, else the one it was built with; chosen again on each reload
      val delegate =
        DefaultReactHostDelegate(
          jsMainModulePath = "index",
          jsBundleLoader = BundleSource.loader(applicationContext),
          reactPackages = packages,
          jsRuntimeFactory = HermesInstance(),
          turboModuleManagerDelegateBuilder = DefaultTurboModuleManagerDelegate.Builder(),
        )
      val componentFactory = ComponentFactory()
      DefaultComponentsRegistry.register(componentFactory)
      ReactHostImpl(applicationContext, delegate, componentFactory, true, false)
    }
  }

  override fun onCreate() {
    super.onCreate()
    loadReactNative(this)
  }
}

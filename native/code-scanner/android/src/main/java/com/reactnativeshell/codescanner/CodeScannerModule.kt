package com.reactnativeshell.codescanner

import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning

/**
 * Scanning a QR code with Google's code scanner: Play services shows its
 * own camera screen (the app needs no camera permission) and gives the
 * code's text.
 */
class CodeScannerModule(reactContext: ReactApplicationContext) : NativeCodeScannerSpec(reactContext) {
  override fun getName() = NAME

  override fun isAvailable(promise: Promise) {
    val status = GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(reactApplicationContext)
    promise.resolve(status == ConnectionResult.SUCCESS)
  }

  override fun scan(promise: Promise) {
    val activity = reactApplicationContext.currentActivity
    if (activity == null) {
      promise.reject("no_view", "Nothing to show the scanner over")
      return
    }
    val options = GmsBarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build()
    GmsBarcodeScanning.getClient(activity, options)
      .startScan()
      .addOnSuccessListener { barcode -> promise.resolve(barcode.rawValue) }
      .addOnCanceledListener { promise.resolve(null) }
      .addOnFailureListener { error ->
        when {
          error is MlKitException && error.errorCode == MlKitException.CODE_SCANNER_CANCELLED -> promise.resolve(null)
          error is MlKitException && error.errorCode == MlKitException.UNAVAILABLE -> {
            // Its UI isn't downloaded yet: ask Play services for it now
            val scanner = GmsBarcodeScanning.getClient(activity, options)
            ModuleInstall.getClient(activity).installModules(ModuleInstallRequest.newBuilder().addApi(scanner).build())
            promise.reject("installing", "The scanner is being installed by Google Play: try again in a moment", error)
          }
          else -> promise.reject("scan_failed", error.message ?: "Couldn't scan", error)
        }
      }
  }

  companion object {
    const val NAME = "RNShellCodeScanner"
  }
}

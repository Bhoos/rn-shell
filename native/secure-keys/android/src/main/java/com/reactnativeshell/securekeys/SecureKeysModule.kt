package com.reactnativeshell.securekeys

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableMap
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import java.math.BigInteger
import java.security.AlgorithmParameters
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.ECPoint
import java.security.spec.ECPublicKeySpec
import javax.crypto.KeyAgreement

/**
 * Keys the platform holds: P-256 in Android's Keystore (StrongBox where
 * there is one), never exported; signing (DER), ECDH, and Play Integrity.
 */
class SecureKeysModule(reactContext: ReactApplicationContext) : NativeSecureKeysSpec(reactContext) {
  override fun getName() = NAME

  private fun keyStore(): KeyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }

  private fun entryOf(alias: String) = "plus.num.securekeys.$alias"

  private fun privateKey(alias: String): PrivateKey? = keyStore().getKey(entryOf(alias), null) as PrivateKey?

  private fun publicKeyOf(alias: String): ECPublicKey? = keyStore().getCertificate(entryOf(alias))?.publicKey as ECPublicKey?

  private fun base64(bytes: ByteArray) = Base64.encodeToString(bytes, Base64.NO_WRAP)

  private fun bytes(base64: String) = Base64.decode(base64, Base64.NO_WRAP)

  /** 32 bytes, big-endian, left-padded. */
  private fun fixed32(value: BigInteger): ByteArray {
    val raw = value.toByteArray().dropWhile { it == 0.toByte() }.toByteArray()
    return ByteArray(32 - raw.size) + raw
  }

  /** The raw public key: 0x04 ‖ X ‖ Y. */
  private fun raw(key: ECPublicKey) = byteArrayOf(4) + fixed32(key.w.affineX) + fixed32(key.w.affineY)

  private fun p256(): ECParameterSpec =
    AlgorithmParameters.getInstance("EC").apply { init(ECGenParameterSpec("secp256r1")) }.getParameterSpec(ECParameterSpec::class.java)

  override fun generateKey(alias: String, usage: String, hardware: Boolean, promise: Promise) {
    try {
      val store = keyStore()
      store.deleteEntry(entryOf(alias))
      val purposes = when (usage) {
        "agree" -> {
          if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) throw IllegalStateException("ECDH in the Keystore needs Android 12")
          KeyProperties.PURPOSE_AGREE_KEY
        }
        else -> KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
      }
      fun make(strongBox: Boolean) {
        val spec = KeyGenParameterSpec.Builder(entryOf(alias), purposes)
          .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
          .setDigests(KeyProperties.DIGEST_SHA256)
          .apply { if (strongBox) setIsStrongBoxBacked(true) }
          .build()
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, KEYSTORE).apply { initialize(spec) }.generateKeyPair()
      }
      // StrongBox where there is one; the Keystore's other (TEE, or software) otherwise
      if (hardware && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        try {
          make(true)
        } catch (e: StrongBoxUnavailableException) {
          make(false)
        }
      } else {
        make(false)
      }
      val key = privateKey(alias)!!
      val info = KeyFactory.getInstance(key.algorithm, KEYSTORE).getKeySpec(key, KeyInfo::class.java)
      val inHardware = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        info.securityLevel == KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT || info.securityLevel == KeyProperties.SECURITY_LEVEL_STRONGBOX
      } else {
        @Suppress("DEPRECATION") info.isInsideSecureHardware
      }
      promise.resolve(Arguments.createMap().apply {
        putString("publicKey", base64(raw(publicKeyOf(alias)!!)))
        putBoolean("hardware", inHardware)
      })
    } catch (e: Exception) {
      promise.reject("generate", "Couldn't make key $alias: ${e.message}", e)
    }
  }

  override fun publicKey(alias: String, promise: Promise) {
    try {
      promise.resolve(publicKeyOf(alias)?.let { base64(raw(it)) })
    } catch (e: Exception) {
      promise.reject("publicKey", e.message, e)
    }
  }

  override fun sign(alias: String, data: String, promise: Promise) {
    try {
      val key = privateKey(alias) ?: throw IllegalStateException("No key $alias")
      val signature = Signature.getInstance("SHA256withECDSA").apply {
        initSign(key)
        update(bytes(data))
      }.sign()
      promise.resolve(base64(signature))
    } catch (e: Exception) {
      promise.reject("sign", "Couldn't sign with $alias: ${e.message}", e)
    }
  }

  override fun agree(alias: String, peer: String, promise: Promise) {
    try {
      val key = privateKey(alias) ?: throw IllegalStateException("No key $alias")
      val raw = bytes(peer)
      if (raw.size != 65 || raw[0] != 4.toByte()) throw IllegalArgumentException("Not a raw P-256 public key")
      val point = ECPoint(BigInteger(1, raw.copyOfRange(1, 33)), BigInteger(1, raw.copyOfRange(33, 65)))
      val peerKey = KeyFactory.getInstance("EC").generatePublic(ECPublicKeySpec(point, p256()))
      val secret = KeyAgreement.getInstance("ECDH", KEYSTORE).apply {
        init(key)
        doPhase(peerKey, true)
      }.generateSecret()
      promise.resolve(base64(secret))
    } catch (e: Exception) {
      promise.reject("agree", "Couldn't agree with $alias: ${e.message}", e)
    }
  }

  override fun deleteKey(alias: String, promise: Promise) {
    try {
      val store = keyStore()
      val had = store.containsAlias(entryOf(alias))
      store.deleteEntry(entryOf(alias))
      promise.resolve(had)
    } catch (e: Exception) {
      promise.reject("deleteKey", e.message, e)
    }
  }

  override fun attestationSupported(promise: Promise) {
    // Play Integrity needs the Play Store; whether the app's recognized is the server's verdict
    promise.resolve(true)
  }

  override fun attest(challenge: String, options: ReadableMap, promise: Promise) {
    try {
      val project = if (options.hasKey("cloudProjectNumber")) options.getDouble("cloudProjectNumber").toLong() else 0L
      if (project == 0L) throw IllegalArgumentException("Play Integrity needs the app's cloudProjectNumber")
      // The nonce: the challenge as URL-safe base64 without padding (Play Integrity's form)
      val nonce = Base64.encodeToString(bytes(challenge), Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
      val request = IntegrityTokenRequest.builder().setNonce(nonce).setCloudProjectNumber(project).build()
      IntegrityManagerFactory.create(reactApplicationContext).requestIntegrityToken(request)
        .addOnSuccessListener { response ->
          promise.resolve(Arguments.createMap().apply {
            putString("kind", "google")
            putString("attestation", base64(response.token().toByteArray(Charsets.UTF_8)))
          })
        }
        .addOnFailureListener { e -> promise.reject("attest", "Couldn't get a Play Integrity token: ${e.message}", e) }
    } catch (e: Exception) {
      promise.reject("attest", e.message, e)
    }
  }

  companion object {
    const val NAME = "RNShellSecureKeys"
    private const val KEYSTORE = "AndroidKeyStore"
  }
}

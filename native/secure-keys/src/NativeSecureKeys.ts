import type { CodegenTypes, TurboModule } from "react-native";
import { TurboModuleRegistry } from "react-native";

/**
 * Keys the platform holds: P-256, made and used where they stay (the
 * Secure Enclave, or the keychain where there's none, e.g. the simulator;
 * Android's Keystore, StrongBox where there is one). Bytes are base64.
 */
export interface Spec extends TurboModule {
  /**
   * Make key `alias` (in place of any before) for `usage` ("sign" or
   * "agree"), in hardware if `hardware` and the device has it: its public
   * key (raw, 65 bytes) and whether it's in hardware.
   */
  generateKey(alias: string, usage: string, hardware: boolean): Promise<CodegenTypes.UnsafeObject>;
  /** Key `alias`'s public key (raw), or null if there's none. */
  publicKey(alias: string): Promise<string | null>;
  /** ECDSA (SHA-256) signature of `data` with key `alias`: DER (X9.62). */
  sign(alias: string, data: string): Promise<string>;
  /** ECDH of key `alias` with `peer` (a raw public key): the shared secret, 32 bytes. */
  agree(alias: string, peer: string): Promise<string>;
  /** Delete key `alias` (none: nothing happens). */
  deleteKey(alias: string): Promise<boolean>;
  /** Whether this device can attest the app (App Attest; Play Integrity). */
  attestationSupported(): Promise<boolean>;
  /**
   * Attest this app, covering `challenge` (32 bytes: App Attest's client
   * data hash; Play Integrity's nonce): `kind` ("apple", "google"),
   * `attestation` (App Attest's attestation object; Play Integrity's token,
   * UTF-8), and App Attest's `keyId`. `options`: Play Integrity's
   * `cloudProjectNumber`.
   */
  attest(challenge: string, options: CodegenTypes.UnsafeObject): Promise<CodegenTypes.UnsafeObject>;
}

export default TurboModuleRegistry.getEnforcing<Spec>("RNShellSecureKeys");

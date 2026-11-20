import type { TurboModule } from "react-native";
import { TurboModuleRegistry } from "react-native";

export interface Spec extends TurboModule {
  /** Whether this device can scan (a camera; on Android, Google Play services). */
  isAvailable(): Promise<boolean>;
  /** Scan one QR code: its text, or null if the person cancelled. Rejects if there's no camera or it's not allowed. */
  scan(): Promise<string | null>;
}

export default TurboModuleRegistry.getEnforcing<Spec>("RNShellCodeScanner");

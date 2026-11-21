import type { TurboModule } from "react-native";
import { TurboModuleRegistry } from "react-native";

export interface Spec extends TurboModule {
  /** What's running: see `UpdatesInfo` in index.ts. */
  info(): Promise<Object>;
  /** Looks for a newer update and downloads it, to start on the next launch: see `CheckResult`. */
  check(): Promise<Object>;
  /** The running bundle rendered: a new update is kept (until then, the next launch goes back to the one before). */
  ready(): void;
}

export default TurboModuleRegistry.get<Spec>("RNShellUpdates");

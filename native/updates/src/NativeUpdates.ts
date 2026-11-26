import type { TurboModule } from "react-native";
import { TurboModuleRegistry } from "react-native";

export interface Spec extends TurboModule {
  /** What's running: see `UpdatesInfo` in index.ts. */
  info(): Promise<Object>;
  /** Looks for a newer update and downloads it, to start on the next launch: see `CheckResult`. */
  check(): Promise<Object>;
  /** The running bundle rendered: a new update is kept (until then, the next launch goes back to the one before). */
  ready(): void;
  /** The plugin index's manifest (JSON), fetched, else the one saved; null without one. */
  pluginIndex(): Promise<string | null>;
  /** Downloads a plugin's bundle by its SHA-256 (kept for later launches); then global.__rnShellLoadPlugin(hash) runs it. */
  fetchPlugin(hash: string): Promise<void>;
  /** Where the bundle comes from (a build with "sources"): see `BundleSource` in source.ts; null for other builds. */
  source(): Promise<Object | null>;
  /** Loads the bundle from Metro ("metro", its URL) or a release server ("release", its URL, "" for the build's), then reloads. */
  setSource(kind: string, url: string): Promise<void>;
}

export default TurboModuleRegistry.get<Spec>("RNShellUpdates");

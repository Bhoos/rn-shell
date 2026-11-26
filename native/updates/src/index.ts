import Native from "./NativeUpdates";

export type UpdatesInfo = {
  /** Updates are configured and this is a release build. */
  enabled: boolean;
  /** The native build updates must be made for (`rn-shell updates fingerprint`). */
  runtimeVersion: string;
  /** The running update's id (its publish time, ms), or null for the bundle the app was built with. */
  updateId: number | null;
  /** The running update's message (`--message` when published). */
  message: string | null;
  /** An update downloaded, started on the next launch (`embedded`: going back to the built-in bundle). */
  pending: { id: number; embedded: boolean } | null;
};

export type CheckResult =
  | { status: "disabled" | "none" | "upToDate" }
  | { status: "downloaded"; id: number; embedded: boolean; message: string | null }
  | { status: "failed"; error: string };

const DISABLED: UpdatesInfo = { enabled: false, runtimeVersion: "", updateId: null, message: null, pending: null };

/** What's running, and what's waiting for the next launch. */
export async function info(): Promise<UpdatesInfo> {
  return Native ? ((await Native.info()) as UpdatesInfo) : DISABLED;
}

/** Looks for a newer update and downloads it; it starts on the next launch. Never rejects. */
export async function check(): Promise<CheckResult> {
  if (!Native) return { status: "disabled" };
  try {
    return (await Native.check()) as CheckResult;
  } catch (err) {
    return { status: "failed", error: err instanceof Error ? err.message : String(err) };
  }
}

/** The app rendered: a newly started update is kept. The shell calls it after its first render. */
export function ready(): void {
  Native?.ready();
}

export { configurePlugins, loadPlugin, pluginIndex, pluginNames, type PluginBuild, type PluginIndex } from './plugins';
export { metroUrl, setSource, source, type BundleSource } from './source';

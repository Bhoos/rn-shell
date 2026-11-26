import Native from "./NativeUpdates";

/**
 * Where a development build's JavaScript comes from: a release build with the
 * app's "sources" (a variant, `rn-shell run-ios --variant dev --mode Release`)
 * loads it from a Metro server or a release server's over the air updates,
 * chosen here. Other builds have no choice (`source()` is null).
 */
export type BundleSource = {
  /** What was chosen. */
  kind: "metro" | "release";
  /** The Metro server (http://host:port), "" before one is given. */
  metroUrl: string;
  /** The release server updates come from. */
  releaseUrl: string;
  /** The build's release server (the app's "updates.url"). */
  buildReleaseUrl: string;
  /** What runs now: Metro's bundle, a downloaded update, or the one the app was built with. */
  running: "metro" | "update" | "embedded";
  /** Why Metro was chosen but isn't running (it didn't answer, or its last bundle didn't start), else null. */
  fallback: string | null;
};

/** Where the bundle comes from, or null for a build without "sources". */
export async function source(): Promise<BundleSource | null> {
  if (!Native) return null;
  return (await Native.source()) as BundleSource | null;
}

/**
 * Loads the bundle from Metro (`host`, `host:port` or a URL; port 8081 if
 * none) or a release server (its URL, "" for the build's), then reloads the
 * app. Metro serves the bundle a release build runs (no development tools);
 * when it doesn't answer, the release server's runs instead.
 */
export async function setSource(kind: "metro" | "release", url: string): Promise<void> {
  if (!Native) throw new Error("This build loads its own bundle");
  await Native.setSource(kind, kind === "metro" ? metroUrl(url) : releaseUrl(url));
}

/** `192.168.1.5`, `192.168.1.5:8081`, `http://mac.local:8081/` → `http://host:port`. */
export function metroUrl(input: string): string {
  // React Native's URL has no host or port: by hand
  const match = /^(?:(https?):\/\/)?(\[[0-9a-fA-F:.]+\]|[^/:\s]+)(?::(\d+))?\/*$/.exec(input.trim());
  if (!match) throw new Error("Which Metro server? (host or host:port)");
  const [, scheme = "http", host, port] = match;
  return `${scheme}://${host}:${port ?? (scheme === "https" ? "443" : "8081")}`;
}

function releaseUrl(input: string): string {
  const text = input.trim();
  if (text && !/^https?:\/\/[^/]+/.test(text)) throw new Error("A release server's URL starts with https://");
  return text;
}

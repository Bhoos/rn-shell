/**
 * Plugins: parts of the app built as bundles of their own (the app's
 * "plugins" in its rn-shell config), loaded when the app asks for one.
 *
 * A plugin bundle has only its own modules: the app's (react, react-native,
 * its libraries) are the app's, by ids that don't change between builds
 * (scripts/plugins/moduleIds.js). The app's bundle says which modules it has
 * and a hash of each (globalThis.__rnShellModules); a plugin build lists the
 * modules it uses with their hashes, and loads only if those it doesn't carry
 * are here with the same hash. The signed index keeps a plugin's last few
 * builds: the newest that fits loads.
 *
 * Release builds download them (the index and bundles, signed and checked
 * natively, like updates); development builds load them from Metro.
 */
import { Platform } from 'react-native';
// @ts-ignore: React Native's own, untyped here
import NativeSourceCode from 'react-native/Libraries/NativeModules/specs/NativeSourceCode';
// @ts-ignore
import loadBundleFromServer from 'react-native/Libraries/Core/Devtools/loadBundleFromServer';
import Native from './NativeUpdates';

export type PluginBuild = {
  id: number;
  createdAt: string;
  /** Its bundle's SHA-256 (files/<hash>). */
  bundle: string;
  /** Its entry module's id. */
  entry: number;
  /** Every module it uses: id → hash of its code. */
  modules: Record<string, string>;
  /** The modules its bundle has (the others must be here). */
  bundled: number[];
};

export type PluginIndex = { id: number; plugins: Record<string, PluginBuild[]> };

type Config = { plugins?: Record<string, string>; directory?: string; workspaceRoot?: string };

let config: Config = {};
let index: Promise<PluginIndex | null> | null = null;
let known: Map<string, string> | null = null;
const loaded = new Map<string, Promise<unknown>>();

declare const __DEV__: boolean;
declare const globalThis: {
  __rnShellModules?: Record<string, string>;
  __rnShellLoadPlugin?: (hash: string) => unknown;
  __r: (id: number) => unknown;
};

/** The shell's runtime config (its plugins, and where the app is): App.tsx gives it at start. */
export function configurePlugins(runtime: Config) {
  config = runtime;
}

/** The plugin index (release builds): fetched once per launch, else the one saved; null without one. */
export function pluginIndex(refresh = false): Promise<PluginIndex | null> {
  if (!Native || __DEV__) return Promise.resolve(null);
  if (!index || refresh) {
    index = Native.pluginIndex()
      .then((text) => (text ? (JSON.parse(text) as PluginIndex) : null))
      .catch((err) => {
        index = null;
        throw err;
      });
  }
  return index;
}

/** The plugins this app has: from the index (release), or its config (development). */
export async function pluginNames(): Promise<string[]> {
  if (__DEV__) return Object.keys(config.plugins ?? {});
  return Object.keys((await pluginIndex())?.plugins ?? {});
}

/** What a module evaluates to, as `import x from` sees it. */
function defaultOf(exports: unknown): unknown {
  const value = exports as { __esModule?: boolean; default?: unknown } | null;
  return value && value.__esModule ? value.default : value;
}

/** The modules here (the app's, and of the plugins loaded): id → hash. */
function modulesHere() {
  known ??= new Map(Object.entries(globalThis.__rnShellModules ?? {}));
  return known;
}

/** A build loads if each module it uses and doesn't carry is here, and each one here is the one it was built with. */
function fits(build: PluginBuild, here: Map<string, string>) {
  const bundled = new Set(build.bundled.map(String));
  return Object.entries(build.modules).every(([id, hash]) => {
    const have = here.get(id);
    return have === undefined ? bundled.has(id) : have === hash;
  });
}

async function loadRelease(name: string): Promise<unknown> {
  const builds = (await pluginIndex())?.plugins[name];
  if (!builds?.length) throw new Error(`No plugin "${name}" is published for this build of the app`);
  const here = modulesHere();
  const build = builds.find((b) => fits(b, here));
  if (!build) throw new Error(`The "${name}" plugin needs a newer version of the app`);
  await Native!.fetchPlugin(build.bundle);
  const exports = globalThis.__rnShellLoadPlugin!(build.bundle);
  for (const [id, hash] of Object.entries(build.modules)) here.set(id, hash);
  return defaultOf(exports);
}

// Development: from Metro, as React Native loads a lazy bundle

function fnv1a(text: string, seed: number) {
  let hash = seed >>> 0;
  for (let i = 0; i < text.length; i += 1) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

/** A module's id (scripts/plugins/moduleIds.js). */
function idOf(key: string) {
  return fnv1a(key, 0x811c9dc5) * 0x10000 + (fnv1a(key, 0x050c5d1f) >>> 16);
}

/** The key of a file of the app (scripts/plugins/moduleIds.js): w: in a workspace, else a:. */
function appKey(entry: string) {
  const file = `${config.directory}/${entry}`.replace(/\/\.\//g, '/');
  const workspace = config.workspaceRoot;
  if (workspace && file.startsWith(workspace + '/')) return `w:${file.slice(workspace.length + 1)}`;
  return `a:${entry.replace(/^\.\//, '')}`;
}

async function loadDevelopment(name: string): Promise<unknown> {
  const entry = config.plugins?.[name];
  if (!entry) throw new Error(`No plugin "${name}" in the app's "plugins"`);
  const scriptURL: string = NativeSourceCode.getConstants().scriptURL;
  const query = new URLSearchParams(scriptURL.split('?')[1] ?? '');
  query.set('platform', Platform.OS);
  query.set('modulesOnly', 'true');
  query.set('runModule', 'false');
  // The entry's path from the app's folder (Metro's root), without its extension
  await loadBundleFromServer(`${entry.replace(/^\.\//, '').replace(/\.[jt]sx?$/, '')}.bundle?${query.toString()}`);
  return defaultOf(globalThis.__r(idOf(appKey(entry))));
}

/**
 * The plugin `name`: its entry's default export. Loads it once (downloading
 * it in a release build: the newest build that fits this app's modules).
 */
export function loadPlugin<T = unknown>(name: string): Promise<T> {
  let promise = loaded.get(name);
  if (!promise) {
    promise = (__DEV__ ? loadDevelopment(name) : loadRelease(name)).catch((err) => {
      loaded.delete(name);
      throw err;
    });
    loaded.set(name, promise);
  }
  return promise as Promise<T>;
}

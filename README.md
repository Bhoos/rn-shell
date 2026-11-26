# React Native Shell
A shell for developing and building React Native apps.

### Objectives:
1. To keep one copy of React Native modules for any number of react native applications.
   And run a react native app like web application
2. Make react native application configurable with a simple config file, allowing to change
   app icons, splash screens, bundle id, versions, etc. 
3. Link native dependencies automatically
4. Make it easier to update react-native version from a single source.

### Usage
1. Clone the repo in the local folder
2. Link repo globally with `npm link` command
3. Use `rn-shell` as a direct replacement for `react-native` commands. Ex: `rn-shell run`
   in your application folder.
4. Export a default `App` component from the application main.

### Over the air updates
`native/updates` (`rn-shell-updates`) lets a release build start a newer JavaScript
bundle (and its assets) than the one it was built with, downloaded from any static
host. Like CodePush, but just files: no service to run.

1. `rn-shell updates keygen` makes a signing key (`~/.rn-shell/updates/<id>.pem`) and
   prints its public key.
2. Configure the app:
   ```json
   "rn-shell": {
     "updates": {
       "url": "https://example.com/updates/com.example.app",
       "publicKey": "MFkwEwYH...",
       "out": ".updates"
     }
   }
   ```
3. Build and ship the app as usual: the build carries the URL, the key, its runtime
   version and when it was made.
4. `rn-shell updates publish [--platform ios,android] [--message "..."]` bundles the app
   as a release build does (Hermes bytecode) and writes a static tree to `out`; serve
   it at `url` as is (rsync, S3, nginx...).

Publishing writes `files/<sha256>` (bundles and assets, by content) and
`<platform>/<runtimeVersion>/latest.json` (and `<id>.json`, every one published). Each
is a manifest signed with the key (ECDSA P-256): the app takes nothing its key didn't
sign, nothing for another runtime version, and nothing older than its own build or
its last update.

On the phone: the shell's `App.tsx` calls `check()` at launch and back in the
foreground (at most every 15 minutes); a newer update downloads and starts on the next
launch. After it renders the shell calls `ready()`; if it never does (it crashed or was
killed first), the next launch goes back to the update before it (or the built-in
bundle) and never takes that one again. Debug builds always use Metro.

The runtime version says which builds can run an update: a hash of what's native per
platform (the shell's dependencies as installed, `native/*`, the iOS or Android
project; `rn-shell updates fingerprint`), or the app's `updates.runtimeVersion`. A JS
change that needs a native one waits for a new build.

- `rn-shell updates rollback [--to <id>]`: publishes an earlier update again, or
  (without `--to`) the built-in bundle, as a new id.
- `rn-shell updates list`: what was published for the current runtime version.

An app can ask what runs: `import { info, check } from 'rn-shell-updates'`.

### Variants and development builds
An app can have variants: `"variants"` entries laid over the rest of its config, picked with
`--variant <name>` (or `RN_SHELL_VARIANT`) on any command:
```json
"rn-shell": {
  "id": "com.example.app",
  "variants": { "dev": { "id": "com.example.dev", "name": "Example dev", "deepLink": "exampledev", "sources": true } }
}
```
```sh
rn-shell run-ios --variant dev --mode Release
```
`"sources": true` makes a release build that loads its JavaScript from where the app says
(`native/updates`: `RNShellSource` on iOS, `BundleSource` on Android), kept on the device:
```ts
import { source, setSource } from 'rn-shell-updates';
await source();                              // { kind, metroUrl, releaseUrl, buildReleaseUrl, running, fallback }, null without "sources"
await setSource('metro', '192.168.1.5');     // Metro's bundle as a release build runs it (dev=false), port 8081 if none; then reloads
await setSource('release', '');              // over the air updates from a server ("": the build's "updates.url"); then reloads
```
Metro is asked each launch and reload; when it doesn't answer, or the last bundle it served
never rendered (`ready()`), the release source's bundle starts instead and `fallback` says why.
Another release server's updates start over (its latest). Android builds with `"sources"` allow
cleartext traffic (Metro is http). Debug builds always use Metro, as before.

### Plugins (code splitting)
Parts of an app can be bundles of their own, downloaded when the app loads them:
```json
"rn-shell": { "plugins": { "orders": "src/plugins/orders.tsx" } }
```
```ts
import { loadPlugin } from 'rn-shell-updates';
const orders = await loadPlugin<OrdersPlugin>('orders'); // the entry's default export
```
Module ids don't change between builds (`scripts/plugins/moduleIds.js`), so a plugin
bundle carries only its own modules and uses the app's (React, React Native, the app's
libraries). The app's release bundle lists a hash of each of its modules
(`scripts/plugins/serializer.js`); a plugin loads only if the app modules it uses are the
ones it was built with. `rn-shell updates publish` builds the plugins too (or alone:
`--plugins-only`, `--plugin a,b`) into a signed `<platform>/<runtimeVersion>/plugins.json`
that keeps each plugin's last 5 builds: the newest that fits loads. The bundle runs in the
app's runtime (`global.__rnShellLoadPlugin`, JSI, `native/updates/cpp`), with everything
the app can reach: plugins are the app's own code, signed with its key. Debug builds load
plugins from Metro. A plugin's images aren't published: keep them in the app.

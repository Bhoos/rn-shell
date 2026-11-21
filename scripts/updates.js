/**
 * Over the air updates (native/updates): `rn-shell updates <command>`, run in
 * the application folder. Configured in its package.json:
 *
 *   "rn-shell": {
 *     "updates": {
 *       "url": "https://example.com/updates/com.example.app",  // where the app looks
 *       "publicKey": "MFkwEwYH...",       // `rn-shell updates keygen` prints it
 *       "out": "../updates",              // optional: publish's default --out
 *       "runtimeVersion": "3"             // optional: instead of the native fingerprint
 *     }
 *   }
 *
 * Publishing writes a static tree (served as is, at "url"):
 *
 *   files/<sha256>                          bundles and assets, by content
 *   <platform>/<runtimeVersion>/latest.json the update the app takes
 *   <platform>/<runtimeVersion>/<id>.json   every one published (for rollback)
 *
 * Each JSON is { manifest: "<json text>", signature } (ECDSA P-256, SHA-256,
 * DER), the manifest { app, platform, runtimeVersion, id, message, createdAt,
 * bundle: <sha256>, assets: [{ path, hash }] } or, to go back to the bundle
 * the app was built with, { ..., embedded: true }. The id is the publish time
 * in ms: an app takes only an id newer than its own build and its last update.
 *
 * The runtime version says which builds can run an update: by default a hash
 * of what's native per platform (the shell's dependencies as installed, its
 * native modules, the iOS or Android project), so a JS update never reaches a
 * build whose native side it doesn't match.
 *
 * The private key: --key, RN_SHELL_UPDATES_KEY, or ~/.rn-shell/updates/<id>.pem.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const shellRoot = path.resolve(__dirname, '..');
const PLATFORMS = ['ios', 'android'];
const BUNDLE_NAMES = { ios: 'main.jsbundle', android: 'index.android.bundle' };

// The fingerprint

/** Files under `dir` (recursive, sorted), but build output and dependencies. */
function listFiles(dir) {
  if (!fs.existsSync(dir)) return [];
  if (fs.statSync(dir).isFile()) return [dir];
  const skip = new Set(['node_modules', 'build', '.gradle', '.cxx', 'Pods', '.DS_Store', 'xcuserdata']);
  return fs.readdirSync(dir).sort().flatMap((name) => (skip.has(name) ? [] : listFiles(path.join(dir, name))));
}

/** What's native for a platform: an update runs only on builds with the same. */
function fingerprint(platform) {
  const hash = crypto.createHash('sha256');
  const pkg = JSON.parse(fs.readFileSync(path.join(shellRoot, 'package.json')));
  // The dependencies as installed (a range can resolve to another version)
  for (const name of Object.keys(pkg.dependencies).sort()) {
    const file = path.join(shellRoot, 'node_modules', name, 'package.json');
    const version = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file)).version : pkg.dependencies[name];
    hash.update(`${name}@${version}\n`);
  }
  hash.update(JSON.stringify(pkg['op-sqlite'] || {}));
  const sources = [
    // Native modules of the shell: their code and their JS specs (codegen)
    ...fs.readdirSync(path.join(shellRoot, 'native')).flatMap((name) => {
      const dir = path.join('native', name);
      return platform === 'ios'
        ? [path.join(dir, 'ios'), path.join(dir, 'src'), path.join(dir, 'package.json'), ...fs.readdirSync(path.join(shellRoot, dir)).filter((f) => f.endsWith('.podspec')).map((f) => path.join(dir, f))]
        : [path.join(dir, 'android'), path.join(dir, 'src'), path.join(dir, 'package.json')];
    }),
    ...(platform === 'ios'
      ? ['ios/Podfile', 'ios/ReactNativeShell/AppDelegate.swift']
      : ['android/build.gradle', 'android/gradle.properties', 'android/app/build.gradle', 'android/app/src/main/java']),
  ];
  for (const file of sources.flatMap((s) => listFiles(path.join(shellRoot, s)))) {
    hash.update(path.relative(shellRoot, file) + '\n');
    hash.update(fs.readFileSync(file));
  }
  return hash.digest('hex').slice(0, 16);
}

/** The runtime version of each platform: the app's "runtimeVersion", or the fingerprint. */
function runtimeVersions(updates) {
  const fixed = updates && updates.runtimeVersion;
  return Object.fromEntries(PLATFORMS.map((p) => [p, fixed ? String(fixed) : fingerprint(p)]));
}

// Signing

function keyPath(config, args) {
  return path.resolve(
    args.key || process.env.RN_SHELL_UPDATES_KEY || path.join(os.homedir(), '.rn-shell', 'updates', `${config.id}.pem`),
  );
}

function signManifest(manifest, privateKey, publicKey) {
  const text = JSON.stringify(manifest);
  const signature = crypto.sign('sha256', Buffer.from(text), privateKey);
  // The app's key must take it: a key that isn't the app's fails here, not on phones
  const key = crypto.createPublicKey({ key: Buffer.from(publicKey, 'base64'), format: 'der', type: 'spki' });
  if (!crypto.verify('sha256', Buffer.from(text), key, signature)) {
    throw new Error(`The key isn't the one in the app's "updates.publicKey"`);
  }
  return JSON.stringify({ manifest: text, signature: signature.toString('base64') }, undefined, 2) + '\n';
}

// Commands

function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg.startsWith('--')) {
      const [name, value] = arg.slice(2).split('=');
      args[name] = value !== undefined ? value : argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : true;
    } else {
      args._.push(arg);
    }
  }
  return args;
}

function requireUpdates(config) {
  const updates = config.updates;
  if (!updates || !updates.url || !updates.publicKey) {
    throw new Error('Missing "updates": { "url", "publicKey" } in the "rn-shell" configuration (`rn-shell updates keygen` makes the key)');
  }
  return updates;
}

function platformsOf(args) {
  const platforms = args.platform ? String(args.platform).split(',') : PLATFORMS;
  for (const p of platforms) if (!PLATFORMS.includes(p)) throw new Error(`Unknown platform "${p}" (ios, android)`);
  return platforms;
}

function outOf(config, args) {
  const out = args.out || (config.updates && config.updates.out);
  if (!out) throw new Error('Where to write the updates: --out <dir> (or "updates.out")');
  return path.resolve(config.directory, out);
}

function keygen(config, args) {
  const file = keyPath(config, args);
  if (fs.existsSync(file) && !args.force) throw new Error(`${file} exists (--force to replace it)`);
  const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, privateKey.export({ type: 'pkcs8', format: 'pem' }), { mode: 0o600 });
  console.log(`Private key: ${file} (keep it safe: whoever has it can update the app)`);
  console.log(`"updates": { "publicKey": "${publicKey.export({ type: 'spki', format: 'der' }).toString('base64')}" }`);
}

/** The bundle and assets a release build would have (Hermes bytecode), in `dir`. */
function bundle(platform, dir) {
  const source = path.join(dir, 'bundle.js');
  const assets = path.join(dir, 'assets');
  fs.mkdirSync(assets, { recursive: true });
  console.log(`Bundling for ${platform}`);
  execFileSync(process.execPath, [
    path.join(shellRoot, 'node_modules', 'react-native', 'cli.js'), 'bundle',
    '--entry-file', path.join(shellRoot, 'index.js'),
    '--platform', platform,
    '--dev', 'false',
    '--minify', 'false', // Hermes doesn't need it
    '--reset-cache',
    '--bundle-output', source,
    '--assets-dest', assets,
  ], { cwd: shellRoot, stdio: 'inherit' });

  // The compiler the build uses: the iOS pods' (it matches their Hermes), else the npm one
  const podsHermesc = path.join(shellRoot, 'ios', 'Pods', 'hermes-engine', 'destroot', 'bin', 'hermesc');
  const os_ = { darwin: 'osx-bin', linux: 'linux64-bin', win32: 'win64-bin' }[process.platform];
  const npmHermesc = path.join(path.dirname(require.resolve('hermes-compiler/package.json', { paths: [path.join(shellRoot, 'node_modules', 'react-native')] })), 'hermesc', os_, 'hermesc');
  const hermesc = platform === 'ios' && fs.existsSync(podsHermesc) ? podsHermesc : npmHermesc;
  const output = path.join(dir, BUNDLE_NAMES[platform]);
  execFileSync(hermesc, ['-emit-binary', '-max-diagnostic-width=80', '-O', '-w', '-out', output, source], { stdio: 'inherit' });
  return { bundle: output, assets };
}

function saveFile(out, content) {
  const hash = crypto.createHash('sha256').update(content).digest('hex');
  const file = path.join(out, 'files', hash);
  if (!fs.existsSync(file)) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, content);
  }
  return hash;
}

/** The published ids of a platform's runtime version, oldest first. */
function history(out, platform, runtimeVersion) {
  const dir = path.join(out, platform, runtimeVersion);
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir)
    .filter((f) => /^\d+\.json$/.test(f))
    .map((f) => JSON.parse(JSON.parse(fs.readFileSync(path.join(dir, f))).manifest))
    .sort((a, b) => a.id - b.id);
}

function write(out, manifest, privateKey, publicKey) {
  const dir = path.join(out, manifest.platform, manifest.runtimeVersion);
  const signed = signManifest(manifest, privateKey, publicKey);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, `${manifest.id}.json`), signed);
  fs.writeFileSync(path.join(dir, 'latest.json'), signed);
  console.log(`${manifest.platform} ${manifest.runtimeVersion}: update ${manifest.id}${manifest.embedded ? ' (the built-in bundle)' : ''} → ${path.join(dir, 'latest.json')}`);
}

/** An id newer than now and than every one published. */
function nextId(out, platform, runtimeVersion) {
  const last = history(out, platform, runtimeVersion).pop();
  return Math.max(Date.now(), last ? last.id + 1 : 0);
}

function loadKey(config, args) {
  const file = keyPath(config, args);
  if (!fs.existsSync(file)) throw new Error(`No private key at ${file} (--key, RN_SHELL_UPDATES_KEY, or \`rn-shell updates keygen\`)`);
  return crypto.createPrivateKey(fs.readFileSync(file));
}

function publish(config, args) {
  const updates = requireUpdates(config);
  // Its values are built into the bundle (env.babel.plugin.js): a developer's own, not every phone's
  if (fs.existsSync(path.join(config.directory, '.env.local.json')) && !args['allow-local-env']) {
    throw new Error('.env.local.json would be built into the update (--allow-local-env if it should)');
  }
  const out = outOf(config, args);
  const privateKey = loadKey(config, args);
  const versions = runtimeVersions(updates);
  for (const platform of platformsOf(args)) {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'rn-shell-update-'));
    try {
      const built = bundle(platform, tmp);
      const assets = listFiles(built.assets).map((file) => ({
        // Relative to the bundle's folder: iOS's assets/..., Android's drawable-*/ and raw/
        path: path.relative(built.assets, file).split(path.sep).join('/'),
        hash: saveFile(out, fs.readFileSync(file)),
      }));
      const runtimeVersion = versions[platform];
      write(out, {
        app: config.id,
        platform,
        runtimeVersion,
        id: nextId(out, platform, runtimeVersion),
        message: typeof args.message === 'string' ? args.message : null,
        createdAt: new Date().toISOString(),
        bundle: saveFile(out, fs.readFileSync(built.bundle)),
        assets,
      }, privateKey, updates.publicKey);
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  }
}

/** Publishes an earlier update again (--to <id>), or the built-in bundle: as a new id, so apps take it. */
function rollback(config, args) {
  const updates = requireUpdates(config);
  const out = outOf(config, args);
  const privateKey = loadKey(config, args);
  const versions = runtimeVersions(updates);
  for (const platform of platformsOf(args)) {
    const runtimeVersion = args.runtimeVersion || versions[platform];
    const base = { app: config.id, platform, runtimeVersion, id: nextId(out, platform, runtimeVersion), createdAt: new Date().toISOString() };
    if (args.to) {
      const earlier = history(out, platform, runtimeVersion).find((m) => String(m.id) === String(args.to));
      if (!earlier) throw new Error(`No update ${args.to} for ${platform} ${runtimeVersion} (\`rn-shell updates list\`)`);
      write(out, { ...base, message: earlier.message, rolledBackTo: earlier.id, bundle: earlier.bundle, assets: earlier.assets }, privateKey, updates.publicKey);
    } else {
      write(out, { ...base, message: null, embedded: true }, privateKey, updates.publicKey);
    }
  }
}

function list(config, args) {
  const out = outOf(config, args);
  const versions = runtimeVersions(config.updates);
  for (const platform of platformsOf(args)) {
    const runtimeVersion = args.runtimeVersion || versions[platform];
    console.log(`${platform} ${runtimeVersion}`);
    for (const m of history(out, platform, runtimeVersion)) {
      const what = m.embedded ? 'the built-in bundle' : m.rolledBackTo ? `again ${m.rolledBackTo}` : m.bundle.slice(0, 12);
      console.log(`  ${m.id}  ${m.createdAt}  ${what}${m.message ? `  ${m.message}` : ''}`);
    }
  }
}

function run(config, argv) {
  const args = parseArgs(argv);
  const command = args._[0];
  const commands = {
    keygen,
    publish,
    rollback,
    list,
    fingerprint: () => {
      for (const [platform, version] of Object.entries(runtimeVersions(config.updates))) console.log(`${platform} ${version}`);
    },
  };
  if (!commands[command]) {
    console.log(`rn-shell updates <command>
  keygen [--key <file>] [--force]                  a signing key; prints the public key for "updates.publicKey"
  fingerprint                                      the runtime version of each platform's build
  publish [--platform ios,android] [--message <text>] [--out <dir>] [--key <file>] [--allow-local-env]
  rollback [--platform ...] [--to <id>] [--out <dir>]   an earlier update again, or (without --to) the built-in bundle
  list [--platform ...] [--out <dir>]`);
    process.exit(command ? 1 : 0);
  }
  try {
    commands[command](config, args);
  } catch (err) {
    console.error(err.message);
    process.exit(1);
  }
}

module.exports = { run, runtimeVersions, fingerprint };

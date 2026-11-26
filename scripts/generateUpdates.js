/**
 * Over the air updates for iOS (native/updates, scripts/updates.js): runs as
 * an Xcode build phase and writes into the built Info.plist what the app
 * checks updates with: RNShellUpdatesURL, RNShellUpdatesKey,
 * RNShellRuntimeVersion and RNShellEmbeddedId (when the build was made: an
 * update published before it is older than the bundle it has); and
 * RNShellSources (the app's "sources": the release build loads its JavaScript
 * from Metro or a release server, chosen in the app: RNShellSource).
 *
 * Every key is always written, so removing "updates" turns them off.
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

function plist(infoPlist, ...args) {
  execFileSync('plutil', [...args, infoPlist]);
}

function generateUpdates(infoPlist, config) {
  const updates = config.updates || {};
  const runtimeVersion = (config.runtimeVersion && config.runtimeVersion.ios) || '';
  console.log(`Updates: ${updates.url || 'off'} (runtime version ${runtimeVersion})`);
  plist(infoPlist, '-replace', 'RNShellUpdatesURL', '-string', updates.url || '');
  plist(infoPlist, '-replace', 'RNShellUpdatesKey', '-string', updates.publicKey || '');
  plist(infoPlist, '-replace', 'RNShellRuntimeVersion', '-string', runtimeVersion);
  plist(infoPlist, '-replace', 'RNShellEmbeddedId', '-string', String(Date.now()));
  plist(infoPlist, '-replace', 'RNShellSources', '-bool', String(Boolean(config.sources)));
}

module.exports = { generateUpdates };

// Run as an Xcode build phase script
if (require.main === module) {
  const config = JSON.parse(fs.readFileSync(path.resolve(process.env.SRCROOT, '../.runtime.config.json')));
  const infoPlist = `${process.env.BUILT_PRODUCTS_DIR}/${process.env.INFOPLIST_PATH}`;
  try {
    generateUpdates(infoPlist, config);
  } catch (err) {
    console.error(`error: ${err.message}`);
    process.exit(1);
  }
}

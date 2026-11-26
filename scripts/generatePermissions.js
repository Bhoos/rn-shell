/**
 * Permission handling works differently in iOS and android
 * A manifest `permissions.manifest.json` file is used define the common name for
 * the permission, and the key used for that specific permission for ios and android
 * separately.
 *
 * The application declares the permissions it needs in its package.json:
 *
 *   "rn-shell": {
 *     "permissions": {
 *       "camera": "Scan QR codes to make a payment",  // description is required for iOS
 *       "notifications": true                         // android only, no description needed
 *     }
 *   }
 *
 * iOS requires a description, which should be provided in the runtime config with
 * the permission key defined in the manifest.
 *
 * The iOS script (this file) modifies the built Info.plist file during the build phase.
 * The android side runs via gradle (android/app/build.gradle), which generates a
 * manifest overlay that is merged with the main AndroidManifest.xml.
 *
 * These permissions will override anything perviously set directly on the ios and
 * android project, for every permission listed in the manifest. Permissions not
 * listed in the manifest are left untouched.
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const MANIFEST_FILE = path.resolve(__dirname, 'permissions.manifest.json');

function toArray(value) {
  if (!value) return [];
  return Array.isArray(value) ? value : [value];
}

/**
 * Resolve the requested permissions against the manifest for the given platform.
 * Returns { enabled: [{ key, description, name }], disabled: [key], errors: [string] }
 */
function resolvePermissions(platform, requested = {}, manifest = loadManifest()) {
  const enabled = [];
  const disabled = [];
  const errors = [];

  Object.keys(requested).forEach((name) => {
    if (!manifest[name]) {
      errors.push(`Unknown permission "${name}". Available permissions: ${Object.keys(manifest).join(', ')}`);
    }
  });

  Object.entries(manifest).forEach(([name, keys]) => {
    const platformKeys = toArray(keys[platform]);
    const value = requested[name];
    const isEnabled = value !== undefined && value !== false && value !== null;

    platformKeys.forEach((key) => {
      if (!isEnabled) {
        disabled.push(key);
        return;
      }

      const description = typeof value === 'string' ? value.trim() : '';
      if (platform === 'ios' && !description) {
        errors.push(`Permission "${name}" requires a description for iOS (${key})`);
        return;
      }
      enabled.push({ name, key, description });
    });
  });

  return { enabled, disabled, errors };
}

function loadManifest() {
  return JSON.parse(fs.readFileSync(MANIFEST_FILE, 'utf-8'));
}

/**
 * Update the given Info.plist with the usage descriptions of the requested permissions.
 * Any usage description from the manifest that is not requested is removed.
 */
function generatePermissions(infoPlist, requested) {
  const { enabled, disabled, errors } = resolvePermissions('ios', requested);
  if (errors.length) {
    // Xcode surfaces lines prefixed with `error:` in the build log
    errors.forEach(err => console.error(`error: ${err}`));
    throw new Error('Invalid permissions configuration');
  }

  disabled.forEach((key) => {
    try {
      execFileSync('plutil', ['-remove', key, infoPlist], { stdio: 'ignore' });
    } catch (err) {
      // key did not exist
    }
  });

  enabled.forEach(({ name, key, description }) => {
    console.log(`Adding permission ${name} (${key})`);
    execFileSync('plutil', ['-replace', key, '-string', description, infoPlist]);
  });
}

module.exports = { generatePermissions, resolvePermissions, loadManifest };

// Run as an Xcode build phase script
if (require.main === module) {
  const config = JSON.parse(fs.readFileSync(path.resolve(process.env.SRCROOT, '../.runtime.config.json')));
  const infoPlist = `${process.env.BUILT_PRODUCTS_DIR}/${process.env.INFOPLIST_PATH}`;
  try {
    generatePermissions(infoPlist, config.permissions);
  } catch (err) {
    console.error(`error: ${err.message}`);
    process.exit(1);
  }
}

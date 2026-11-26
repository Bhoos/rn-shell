/**
 * Module ids that don't depend on the build: a hash of where a module is
 * (a package's name, version and file; or a file of the workspace, the app
 * or the shell), so the app's bundle and a plugin bundle built another day
 * give the same module the same id. A plugin then uses the app's modules
 * (react, react-native, the app's libraries) instead of carrying them.
 *
 * Ids are 48-bit (two FNV-1a hashes): plugins.ts in native/updates computes a
 * plugin entry's id the same way in development.
 */
const fs = require('fs');
const path = require('path');

function fnv1a(text, seed) {
  let hash = seed >>> 0;
  for (let i = 0; i < text.length; i += 1) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

/** A module's id from its key. */
function idOf(key) {
  return fnv1a(key, 0x811c9dc5) * 0x10000 + (fnv1a(key, 0x050c5d1f) >>> 16);
}

const versions = new Map();
/** The name and version of the package `dir` (a folder inside node_modules/) belongs to. */
function packageOf(afterNodeModules) {
  const parts = afterNodeModules.split('/');
  const nameParts = parts[0].startsWith('@') ? 2 : 1;
  const name = parts.slice(0, nameParts).join('/');
  return { name, rest: parts.slice(nameParts).join('/') };
}

/**
 * A module's key: n:<package>@<version>/<file> inside node_modules (wherever
 * that is), w:<file> in the workspace, a:<file> in the app, s:<file> in the shell.
 */
function keyOf(file, roots) {
  const unix = file.split(path.sep).join('/');
  const at = unix.lastIndexOf('/node_modules/');
  if (at >= 0) {
    const { name, rest } = packageOf(unix.slice(at + '/node_modules/'.length));
    const root = unix.slice(0, at) + '/node_modules/' + name;
    let version = versions.get(root);
    if (version === undefined) {
      try {
        version = JSON.parse(fs.readFileSync(path.join(root, 'package.json'))).version || '';
      } catch {
        version = '';
      }
      versions.set(root, version);
    }
    return `n:${name}@${version}/${rest}`;
  }
  for (const [prefix, root] of [['w', roots.workspace], ['a', roots.app], ['s', roots.shell]]) {
    if (root && (unix + '/').startsWith(root.split(path.sep).join('/') + '/')) {
      return `${prefix}:${path.relative(root, file).split(path.sep).join('/')}`;
    }
  }
  return unix; // a virtual module (__prelude__) or somewhere else
}

/** Metro's serializer.createModuleIdFactory: a factory per build, refusing two keys with one id. */
function createModuleIdFactory(roots) {
  return () => {
    const keys = new Map();
    return (file) => {
      const key = keyOf(file, roots);
      const id = idOf(key);
      const other = keys.get(id);
      if (other !== undefined && other !== key) {
        throw new Error(`Two modules have the id ${id}: ${other} and ${key}`);
      }
      keys.set(id, key);
      return id;
    };
  };
}

module.exports = { createModuleIdFactory, keyOf, idOf };

/**
 * Metro's serializer.customSerializer, for plugins (native/updates, plugins.ts):
 *
 * - The app's release bundle ends with globalThis.__rnShellModules: each
 *   module's id and a hash of its code. A plugin checks it before it loads:
 *   the app's modules it uses must be the ones it was built with.
 *   RN_SHELL_MODULES_OUT=<file> also writes that map to a file (a plugin
 *   build reads it).
 * - RN_SHELL_PLUGIN_HOST=<the app's map> builds a plugin instead: its
 *   modules the app doesn't have, then `__r(<entry>)` (the bundle's value is
 *   the entry's exports); RN_SHELL_PLUGIN_OUT=<file> gets what it needs:
 *   { entry, modules: { id: hash } (every module it uses), bundled: [ids] }.
 *
 * Development bundles are Metro's own.
 */
const fs = require('fs');
const crypto = require('crypto');

const baseJSBundle = require('metro/private/DeltaBundler/Serializers/baseJSBundle').default;
const bundleToString = require('metro/private/lib/bundleToString').default;

const hashOf = (code) => crypto.createHash('sha256').update(code).digest('hex').slice(0, 12);

/** Before the trailing comments (//# sourceMappingURL=...), so they stay last. */
function append(code, statement) {
  const match = /(\n\/\/#[^\n]*)*\s*$/.exec(code);
  const at = match ? match.index : code.length;
  return `${code.slice(0, at)}\n${statement}${code.slice(at)}`;
}

async function customSerializer(entryPoint, preModules, graph, options) {
  const bundle = baseJSBundle(entryPoint, preModules, graph, options);
  if (options.dev) return bundleToString(bundle).code;

  const hosted = process.env.RN_SHELL_PLUGIN_HOST;
  if (!hosted) {
    const map = Object.fromEntries(bundle.modules.map(([id, code]) => [id, hashOf(code)]));
    if (process.env.RN_SHELL_MODULES_OUT) fs.writeFileSync(process.env.RN_SHELL_MODULES_OUT, JSON.stringify(map));
    return append(bundleToString(bundle).code, `globalThis.__rnShellModules=${JSON.stringify(map)};`);
  }

  // A plugin: the app's modules left out, its entry run last
  const host = JSON.parse(fs.readFileSync(hosted));
  const entry = options.createModuleId(entryPoint);
  const modules = {};
  const bundled = [];
  let code = '';
  for (const [id, moduleCode] of bundle.modules.sort((a, b) => a[0] - b[0])) {
    modules[id] = hashOf(moduleCode);
    if (host[id] === undefined) {
      bundled.push(id);
      code += moduleCode + '\n';
    }
  }
  if (process.env.RN_SHELL_PLUGIN_OUT) {
    fs.writeFileSync(process.env.RN_SHELL_PLUGIN_OUT, JSON.stringify({ entry, modules, bundled }));
  }
  // The bundle's value: what the entry exports
  return code + options.getRunModuleStatement(entry, options.globalPrefix) + '\n';
}

module.exports = { customSerializer, hashOf };

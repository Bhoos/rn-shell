const fs = require('fs');
const path = require('path');
const { getDefaultConfig } = require('@react-native/metro-config');
const { createModuleIdFactory } = require('./scripts/plugins/moduleIds.js');
const { customSerializer } = require('./scripts/plugins/serializer.js');

const runTimeConfig = JSON.parse(fs.readFileSync('./.runtime.config.json'));
// /**
//  * Metro configuration
//  * https://reactnative.dev/docs/metro
//  *
//  * @type {import('@react-native/metro-config').MetroConfig}
//  */
const defaultConfig = getDefaultConfig(__dirname);

const shellRoot = __dirname;
const workspaceRoot = runTimeConfig.workspaceRoot;
const applicationRoot = runTimeConfig.directory;

/** One copy of these for every module, the shell's: a workspace package may bring its own. */
const PINNED = /^(react|react-native)(\/|$)/;
const shellOrigin = path.resolve(shellRoot, 'index.js');

const config = {
  ...defaultConfig,

  projectRoot: applicationRoot,

  watchFolders: [
    shellRoot,
  ],
  resolver: {
    ...defaultConfig.resolver,
    resolveRequest: (context, moduleName, platform) => {
      if (moduleName === "./index") {
        if (!fs.existsSync(path.join(applicationRoot, 'index.js'))) {
          return {
            filePath: path.resolve(__dirname, 'index.js'),
            type: 'sourceFile',
          };
        }
      }
      // console.log('Resolve Request', moduleName, platform);
      if (PINNED.test(moduleName)) {
        return context.resolveRequest({ ...context, originModulePath: shellOrigin }, moduleName, platform);
      }
      try {
        return context.resolveRequest(context, moduleName, platform);
      } catch (err) {
        // In a workspace that doesn't hoist (pnpm's default), a package's own
        // dependencies are in its own node_modules: look them up from the
        // importing file, as Node does
        if (!workspaceRoot) throw err;
        return context.resolveRequest({ ...context, disableHierarchicalLookup: false }, moduleName, platform);
      }
    },
    disableHierarchicalLookup: true,
    nodeModulesPaths: [
      path.resolve(shellRoot, 'node_modules'),
      path.resolve(applicationRoot, 'node_modules'),
    ],
    extraNodeModules: {
      // Point to the project root to load the main App component
      '@@app': applicationRoot,
    },
  },
  serializer: {
    ...defaultConfig.serializer,
    // Plugins (scripts/plugins): ids that don't change between builds, and
    // the app's bundle saying which modules it has
    createModuleIdFactory: createModuleIdFactory({ workspace: workspaceRoot, app: applicationRoot, shell: shellRoot }),
    customSerializer,
  },
  transformer: {
    ...defaultConfig.transformer,

    // Disabel babel.config.js
    enableBabelRCLookup: false,

    // Use our custom babel transformer
    babelTransformerPath: require.resolve('./metro-transformer.js'),
  },
};

// If we have an workspace we will need to watch that as well
if (workspaceRoot) {
  // config.watchFolders.push(workspaceRoot);
  config.resolver.nodeModulesPaths.push(path.resolve(workspaceRoot, 'node_modules'));
  config.watchFolders.push(workspaceRoot);
} else {
  config.watchFolders.push(applicationRoot);
}


module.exports = config;

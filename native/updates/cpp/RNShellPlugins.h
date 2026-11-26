#pragma once

#include <jsi/jsi.h>
#include <string>

namespace rnshell {

/**
 * Installs global.__rnShellLoadPlugin(hash): runs the plugin bundle saved as
 * <dir>/<hash> (downloaded and checked by its SHA-256, signed in the plugin
 * index) in this runtime, and returns its value (the entry's exports).
 */
void installPluginLoader(facebook::jsi::Runtime &runtime, std::string dir);

} // namespace rnshell

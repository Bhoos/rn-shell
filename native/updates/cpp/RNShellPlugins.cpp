#include "RNShellPlugins.h"

#include <fstream>
#include <iterator>
#include <memory>

namespace rnshell {

using namespace facebook;

static bool isHash(const std::string &text) {
  if (text.size() != 64) return false;
  for (char c : text) {
    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return false;
  }
  return true;
}

void installPluginLoader(jsi::Runtime &runtime, std::string dir) {
  auto load = jsi::Function::createFromHostFunction(
      runtime,
      jsi::PropNameID::forAscii(runtime, "__rnShellLoadPlugin"),
      1,
      [dir](jsi::Runtime &rt, const jsi::Value &, const jsi::Value *args, size_t count) -> jsi::Value {
        if (count < 1 || !args[0].isString()) throw jsi::JSError(rt, "__rnShellLoadPlugin(hash)");
        std::string hash = args[0].asString(rt).utf8(rt);
        // Only a downloaded file, by its hash: never a path
        if (!isHash(hash)) throw jsi::JSError(rt, "Not a plugin's hash: " + hash);
        std::ifstream file(dir + "/" + hash, std::ios::binary);
        if (!file) throw jsi::JSError(rt, "The plugin " + hash + " isn't downloaded");
        std::string code((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
        // Hermes bytecode or source: evaluateJavaScript takes either
        return rt.evaluateJavaScript(std::make_shared<jsi::StringBuffer>(std::move(code)), "rn-shell-plugin:" + hash);
      });
  runtime.global().setProperty(runtime, "__rnShellLoadPlugin", std::move(load));
}

} // namespace rnshell

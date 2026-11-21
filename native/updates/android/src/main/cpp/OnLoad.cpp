#include <fbjni/fbjni.h>
#include <ReactCommon/BindingsInstallerHolder.h>

#include "RNShellPlugins.h"

using namespace facebook;

/** UpdatesModule's JSI bindings (TurboModuleWithJSIBindings): the plugin loader. */
struct UpdatesModuleJSI : jni::JavaClass<UpdatesModuleJSI> {
  static constexpr auto kJavaDescriptor = "Lcom/reactnativeshell/updates/UpdatesModule;";

  static jni::local_ref<react::BindingsInstallerHolder::javaobject> getBindingsInstaller(jni::alias_ref<UpdatesModuleJSI> self) {
    static const auto pluginsDir = javaClassStatic()->getMethod<jstring()>("pluginsDir");
    std::string dir = pluginsDir(self)->toStdString();
    return react::BindingsInstallerHolder::newObjectCxxArgs(
        [dir](jsi::Runtime &runtime, const std::shared_ptr<react::CallInvoker> &) { rnshell::installPluginLoader(runtime, dir); });
  }

  static void registerNatives() {
    javaClassLocal()->registerNatives({makeNativeMethod("getBindingsInstaller", UpdatesModuleJSI::getBindingsInstaller)});
  }
};

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *) {
  return jni::initialize(vm, [] { UpdatesModuleJSI::registerNatives(); });
}

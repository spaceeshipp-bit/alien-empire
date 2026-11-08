// Registers the sim core's classes with Godot. Entry point named in
// sim/aetd_sim.gdextension.
#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "godot/bindings.h"

using namespace godot;

namespace {

void initialize(ModuleInitializationLevel level) {
	if (level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_ABSTRACT_CLASS(aetd::SimNative);
	GDREGISTER_CLASS(aetd::SimNativeRng);
	GDREGISTER_CLASS(aetd::SimNativeHasher);
	GDREGISTER_CLASS(aetd::SimNativeLanePath);
	GDREGISTER_CLASS(aetd::SimNativeBattle);
}

void uninitialize(ModuleInitializationLevel) {}

} // namespace

extern "C" {

GDExtensionBool GDE_EXPORT aetd_sim_library_init(GDExtensionInterfaceGetProcAddress get_proc_address,
		GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
	GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
	init.register_initializer(initialize);
	init.register_terminator(uninitialize);
	init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init.init();
}
}

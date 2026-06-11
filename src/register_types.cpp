#include "register_types.h"
#include "crypto/keccak_wrapper.hpp"
#include "core/big_int.hpp"
#include "core/w3_abi.hpp"
#include "crypto/w3_crypto.hpp"
#include "core/rlp.hpp"
#include "core/w3_transaction.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>


using namespace godot;

void initialize_web3_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }

    ClassDB::register_class<W3Keccak>();
    ClassDB::register_class<W3BigInt>();
    ClassDB::register_class<W3ABI>();
    ClassDB::register_class<W3RLP>(); 
    ClassDB::register_class<W3Crypto>();
    ClassDB::register_class<W3Transaction>();
}

void uninitialize_web3_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
}

extern "C" {
    GDExtensionBool GDE_EXPORT web3_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
        godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

        init_obj.register_initializer(initialize_web3_module);
        init_obj.register_terminator(uninitialize_web3_module);
        init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

        return init_obj.init();
    }
}
#include "keccak_wrapper.hpp"
#include "../utils/hex_utils.hpp"

// Подключаем SHA3 из Trezor. 
// Trezor реализует keccak_256 с той же сигнатурой.
extern "C" {
#include "../vendor/trezor-crypto/sha3.h"
}

using namespace godot;

void W3Keccak::_bind_methods() {
    ClassDB::bind_static_method("W3Keccak", D_METHOD("hash", "data"), &W3Keccak::hash);
    ClassDB::bind_static_method("W3Keccak", D_METHOD("hash_to_hex", "data"), &W3Keccak::hash_to_hex);
}

W3Keccak::W3Keccak() {}
W3Keccak::~W3Keccak() {}

PackedByteArray W3Keccak::hash(const PackedByteArray& p_data) {
    PackedByteArray result;
    result.resize(32); 
    
    // Trezor signature: void keccak_256(const uint8_t *data, size_t len, uint8_t *digest);
    keccak_256(p_data.ptr(), p_data.size(), result.ptrw());
    
    return result;
}

String W3Keccak::hash_to_hex(const String& p_data) {
    PackedByteArray bytes = p_data.to_utf8_buffer();
    PackedByteArray hashed = hash(bytes);
    return HexUtils::bytes_to_hex(hashed, true);
}
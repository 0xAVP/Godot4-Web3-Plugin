#ifndef W3_KECCAK_WRAPPER_HPP
#define W3_KECCAK_WRAPPER_HPP

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class W3Keccak : public RefCounted {
    GDCLASS(W3Keccak, RefCounted)

protected:
    static void _bind_methods();

public:
    W3Keccak();
    ~W3Keccak();

    // Основной метод: принимает байты, возвращает байты (32 шт)
    static PackedByteArray hash(const PackedByteArray& p_data);
    
    // Вспомогательный метод: принимает строку, возвращает Hex-строку "0x..."
    static String hash_to_hex(const String& p_data);
};

}

#endif
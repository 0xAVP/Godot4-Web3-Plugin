#ifndef W3_ABI_HPP
#define W3_ABI_HPP

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/array.hpp> // Добавили для decode
#include "big_int.hpp"

namespace godot {

class W3ABI : public RefCounted {
    GDCLASS(W3ABI, RefCounted)

protected:
    static void _bind_methods();

public:
    W3ABI();
    ~W3ABI();

    // Вспомогательные методы для работы с типами (общее для enc/dec)
    static bool is_dynamic(const String& p_type);
    static PackedStringArray split_tuple_types(const String& p_type_str);
    static int get_static_size(const String& p_type);
    // --- ENCODERS (Implemented in w3_abi_encode.cpp) ---
    static PackedByteArray encode_uint256(const Ref<W3BigInt>& p_val);
    static PackedByteArray encode_address(const String& p_addr);
    static PackedByteArray encode_bool(bool p_val);
    static PackedByteArray encode_function_selector(const String& p_signature);
    static PackedByteArray encode_string(const String& p_val);
    static PackedByteArray encode_bytes(const PackedByteArray& p_val);
    static PackedByteArray encode_bytes_n(const PackedByteArray& p_val, int N);
    static PackedByteArray encode_params(const PackedStringArray& p_types, const Array& p_args);
    static PackedByteArray encode_packed(const PackedStringArray& p_types, const Array& p_args);
    // --- DECODERS (Implemented in w3_abi_decode.cpp) ---
    // Возвращает массив вариантов (W3BigInt, String, bool, PackedByteArray)
    static Array decode(const PackedStringArray& p_types, const PackedByteArray& p_data);
    static String decode_revert_reason(const PackedByteArray& p_data);
    
};

}

#endif
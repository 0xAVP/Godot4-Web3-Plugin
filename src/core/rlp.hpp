#ifndef W3_RLP_HPP
#define W3_RLP_HPP

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include "big_int.hpp" // Нужно для encode_uint

namespace godot {

class W3RLP : public RefCounted {
    GDCLASS(W3RLP, RefCounted)

protected:
    static void _bind_methods();

public:
    W3RLP();
    ~W3RLP();

    static PackedByteArray encode_bytes(const PackedByteArray& p_data);
    static PackedByteArray encode_list_payload(const PackedByteArray& p_list_payload);
    
    // NEW: Специализированный метод для Ethereum чисел
    // Обрабатывает 0 как пустую строку (0x80)
    // Убирает ведущие нули
    static PackedByteArray encode_uint(const Ref<W3BigInt>& p_val);
};

}

#endif
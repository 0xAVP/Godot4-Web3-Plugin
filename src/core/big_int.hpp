#ifndef W3_BIG_INT_HPP
#define W3_BIG_INT_HPP

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include "../vendor/uint256_t/uint256_t.h"

namespace godot {

    /**
 * @class W3BigInt
 * @brief Wrapper around uint256_t for Godot.
 * 
 * IMPORTANT: Arithmetic operations (add, sub, mul) follow EVM semantics with
 * silent overflow/underflow (wrap-around modulo 2^256).
 * 
 * This is equivalent to:
 * - Solidity < 0.8.0 (default behavior)
 * - Solidity >= 0.8.0 inside an `unchecked { ... }` block.
 * 
 * If you need overflow protection, you must implement checks manually before operation.
 */

class W3BigInt : public RefCounted {
    GDCLASS(W3BigInt, RefCounted)

private:
    uint256_t value;
    
    static bool _is_valid_decimal(const String& s);
    static bool _is_valid_hex(const String& s);

protected:
    static void _bind_methods();

public:
    W3BigInt();
    W3BigInt(const uint256_t& p_val); 
    ~W3BigInt();

    // --- Фабричные методы ---
    static Ref<W3BigInt> from_string(const String& p_val);
    static Ref<W3BigInt> from_hex(const String& p_val);
    static Ref<W3BigInt> from_int(int64_t p_val);
    static Ref<W3BigInt> from_bytes(const PackedByteArray& p_bytes);

    // --- Арифметика ---
    Ref<W3BigInt> add(const Ref<W3BigInt>& p_other);
    Ref<W3BigInt> sub(const Ref<W3BigInt>& p_other);
    Ref<W3BigInt> mul(const Ref<W3BigInt>& p_other);
    Ref<W3BigInt> div(const Ref<W3BigInt>& p_other);
    Ref<W3BigInt> mod(const Ref<W3BigInt>& p_other);

    void iadd(const Ref<W3BigInt>& p_other);
    void isub(const Ref<W3BigInt>& p_other);
    void imul(const Ref<W3BigInt>& p_other);

    // --- Сравнение (Unsigned) ---
    bool equals(const Ref<W3BigInt>& p_other);
    bool gt(const Ref<W3BigInt>& p_other);
    bool lt(const Ref<W3BigInt>& p_other);

    // --- Сравнение (Signed - NEW) ---
    bool gt_signed(const Ref<W3BigInt>& p_other);
    bool lt_signed(const Ref<W3BigInt>& p_other);

    // --- Конвертация ---
    String to_string_val() const;
    String to_int256_string() const;
    String to_hex(bool p_with_prefix = true);
    String _to_string() const;
    
    PackedByteArray get_bytes(bool p_pad_to_32 = false) const;
    
    uint256_t get_value() const { return value; }
    void set_value(const uint256_t& p_val) { value = p_val; }
};

}

#endif
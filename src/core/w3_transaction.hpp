#ifndef W3_TRANSACTION_HPP
#define W3_TRANSACTION_HPP

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/core/binder_common.hpp>
#include "big_int.hpp"

namespace godot {

class W3Transaction : public RefCounted {
    GDCLASS(W3Transaction, RefCounted)

public:
    enum TransactionType {
        TYPE_LEGACY = 0,
        TYPE_EIP1559 = 2
    };

private:
    bool is_contract_creation = false;
    TransactionType type = TYPE_LEGACY;
    
    Ref<W3BigInt> nonce;
    Ref<W3BigInt> gas_limit;
    String to; 
    Ref<W3BigInt> value;
    PackedByteArray data;
    Ref<W3BigInt> chain_id;
    
    // Legacy
    Ref<W3BigInt> gas_price;
    
    // EIP-1559
    Ref<W3BigInt> max_priority_fee_per_gas;
    Ref<W3BigInt> max_fee_per_gas;

    PackedByteArray _rlp_encode_fields(bool p_for_signing, const PackedByteArray& p_v = PackedByteArray(), const PackedByteArray& p_r = PackedByteArray(), const PackedByteArray& p_s = PackedByteArray());
    PackedByteArray _encode_address_field() const;
    

protected:
    static void _bind_methods();

public:
    W3Transaction();
    ~W3Transaction();

    // --- Setters ---
    void set_type(int p_type);
    void set_nonce(const Ref<W3BigInt>& p_val);
    void set_gas_limit(const Ref<W3BigInt>& p_val);
    bool set_to(const String& p_addr);
    void set_creation();
    void set_value(const Ref<W3BigInt>& p_val);
    void set_data(const PackedByteArray& p_data);
    void set_chain_id(const Ref<W3BigInt>& p_val);
    void set_gas_price(const Ref<W3BigInt>& p_val);
    void set_max_priority_fee_per_gas(const Ref<W3BigInt>& p_val);
    void set_max_fee_per_gas(const Ref<W3BigInt>& p_val);

    // --- Getters (NEW) ---
    int get_type() const;
    Ref<W3BigInt> get_nonce() const;
    Ref<W3BigInt> get_gas_limit() const;
    String get_to() const;
    Ref<W3BigInt> get_value() const;
    PackedByteArray get_data() const;
    Ref<W3BigInt> get_chain_id() const;
    Ref<W3BigInt> get_gas_price() const;
    Ref<W3BigInt> get_max_priority_fee_per_gas() const;
    Ref<W3BigInt> get_max_fee_per_gas() const;

    // --- Core Logic ---
    PackedByteArray get_sign_hash();
    PackedByteArray sign(const PackedByteArray& p_priv_key);
};

}

VARIANT_ENUM_CAST(godot::W3Transaction::TransactionType);

#endif
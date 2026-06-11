#include "w3_transaction.hpp"
#include "rlp.hpp"
#include "w3_abi.hpp"
#include "../crypto/keccak_wrapper.hpp"
#include "../crypto/w3_crypto.hpp"
#include "../utils/hex_utils.hpp"
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void W3Transaction::_bind_methods() {
    BIND_ENUM_CONSTANT(TYPE_LEGACY);
    BIND_ENUM_CONSTANT(TYPE_EIP1559);

    // Setters
    ClassDB::bind_method(D_METHOD("set_type", "type"), &W3Transaction::set_type);
    ClassDB::bind_method(D_METHOD("set_nonce", "value"), &W3Transaction::set_nonce);
    ClassDB::bind_method(D_METHOD("set_gas_limit", "value"), &W3Transaction::set_gas_limit);
    ClassDB::bind_method(D_METHOD("set_to", "address"), &W3Transaction::set_to);
    ClassDB::bind_method(D_METHOD("set_creation"), &W3Transaction::set_creation);
    ClassDB::bind_method(D_METHOD("set_value", "value"), &W3Transaction::set_value);
    ClassDB::bind_method(D_METHOD("set_data", "data"), &W3Transaction::set_data);
    ClassDB::bind_method(D_METHOD("set_chain_id", "value"), &W3Transaction::set_chain_id);
    ClassDB::bind_method(D_METHOD("set_gas_price", "value"), &W3Transaction::set_gas_price);
    ClassDB::bind_method(D_METHOD("set_max_priority_fee_per_gas", "value"), &W3Transaction::set_max_priority_fee_per_gas);
    ClassDB::bind_method(D_METHOD("set_max_fee_per_gas", "value"), &W3Transaction::set_max_fee_per_gas);

    // Getters
    ClassDB::bind_method(D_METHOD("get_type"), &W3Transaction::get_type);
    ClassDB::bind_method(D_METHOD("get_nonce"), &W3Transaction::get_nonce);
    ClassDB::bind_method(D_METHOD("get_gas_limit"), &W3Transaction::get_gas_limit);
    ClassDB::bind_method(D_METHOD("get_to"), &W3Transaction::get_to);
    ClassDB::bind_method(D_METHOD("get_value"), &W3Transaction::get_value);
    ClassDB::bind_method(D_METHOD("get_data"), &W3Transaction::get_data);
    ClassDB::bind_method(D_METHOD("get_chain_id"), &W3Transaction::get_chain_id);
    ClassDB::bind_method(D_METHOD("get_gas_price"), &W3Transaction::get_gas_price);
    ClassDB::bind_method(D_METHOD("get_max_priority_fee_per_gas"), &W3Transaction::get_max_priority_fee_per_gas);
    ClassDB::bind_method(D_METHOD("get_max_fee_per_gas"), &W3Transaction::get_max_fee_per_gas);

    // Logic
    ClassDB::bind_method(D_METHOD("get_sign_hash"), &W3Transaction::get_sign_hash);
    ClassDB::bind_method(D_METHOD("sign", "private_key"), &W3Transaction::sign);
}

W3Transaction::W3Transaction() {
    nonce = W3BigInt::from_int(0);
    gas_limit = W3BigInt::from_int(21000);
    value = W3BigInt::from_int(0);
    chain_id = W3BigInt::from_int(1);
    gas_price = W3BigInt::from_int(0);
    max_priority_fee_per_gas = W3BigInt::from_int(0);
    max_fee_per_gas = W3BigInt::from_int(0);
}

W3Transaction::~W3Transaction() {}

// Setters
void W3Transaction::set_type(int p_type) { type = (TransactionType)p_type; }
void W3Transaction::set_nonce(const Ref<W3BigInt>& p_val) { if(p_val.is_valid()) nonce = p_val; }
void W3Transaction::set_gas_limit(const Ref<W3BigInt>& p_val) { if(p_val.is_valid()) gas_limit = p_val; }

bool W3Transaction::set_to(const String& p_addr) { 
    is_contract_creation = false; 
    to = ""; 

    String clean_addr = p_addr.strip_edges();
    
    if (clean_addr.is_empty()) {
        ERR_PRINT("W3Transaction Error: 'set_to' cannot be empty.");
        return false;
    }
    
    if (clean_addr.begins_with("0x") || clean_addr.begins_with("0X")) {
        clean_addr = clean_addr.substr(2);
    }
    
    if (clean_addr.length() != 40) {
        ERR_PRINT("W3Transaction Error: Invalid address length.");
        return false;
    }
    
    if (!clean_addr.is_valid_hex_number(false)) { 
        ERR_PRINT("W3Transaction Error: Address contains invalid hex characters.");
        return false;
    }

    to = "0x" + clean_addr; 
    return true; // УСПЕХ
}

void W3Transaction::set_creation() {
    to = ""; // Очищаем адрес (для RLP это будет 0x80)
    is_contract_creation = true; // Явно ставим флаг
    // Можно также занулить value или проверить data, но это не обязательно
}

void W3Transaction::set_value(const Ref<W3BigInt>& p_val) { if(p_val.is_valid()) value = p_val; }
void W3Transaction::set_data(const PackedByteArray& p_data) { data = p_data; }
void W3Transaction::set_chain_id(const Ref<W3BigInt>& p_val) { if(p_val.is_valid()) chain_id = p_val; }
void W3Transaction::set_gas_price(const Ref<W3BigInt>& p_val) { if(p_val.is_valid()) gas_price = p_val; }
void W3Transaction::set_max_priority_fee_per_gas(const Ref<W3BigInt>& p_val) { if(p_val.is_valid()) max_priority_fee_per_gas = p_val; }
void W3Transaction::set_max_fee_per_gas(const Ref<W3BigInt>& p_val) { if(p_val.is_valid()) max_fee_per_gas = p_val; }

// Getters
int W3Transaction::get_type() const { return (int)type; }
Ref<W3BigInt> W3Transaction::get_nonce() const { return nonce; }
Ref<W3BigInt> W3Transaction::get_gas_limit() const { return gas_limit; }
String W3Transaction::get_to() const { return to; }
Ref<W3BigInt> W3Transaction::get_value() const { return value; }
PackedByteArray W3Transaction::get_data() const { return data; }
Ref<W3BigInt> W3Transaction::get_chain_id() const { return chain_id; }
Ref<W3BigInt> W3Transaction::get_gas_price() const { return gas_price; }
Ref<W3BigInt> W3Transaction::get_max_priority_fee_per_gas() const { return max_priority_fee_per_gas; }
Ref<W3BigInt> W3Transaction::get_max_fee_per_gas() const { return max_fee_per_gas; }

// Core
PackedByteArray W3Transaction::_encode_address_field() const {
    // Если это создание контракта или просто пустой адрес (что отловит sign), возвращаем пустоту
    if (to.is_empty()) return PackedByteArray(); 
    return HexUtils::hex_to_bytes(to);
}

PackedByteArray W3Transaction::_rlp_encode_fields(bool p_for_signing, const PackedByteArray& p_v, const PackedByteArray& p_r, const PackedByteArray& p_s) {
    PackedByteArray list_content;

    if (type == TYPE_LEGACY) {
        list_content.append_array(W3RLP::encode_uint(nonce));
        list_content.append_array(W3RLP::encode_uint(gas_price));
        list_content.append_array(W3RLP::encode_uint(gas_limit));
        list_content.append_array(W3RLP::encode_bytes(_encode_address_field()));
        list_content.append_array(W3RLP::encode_uint(value));
        list_content.append_array(W3RLP::encode_bytes(data));

        if (p_for_signing) {
            list_content.append_array(W3RLP::encode_uint(chain_id));
            list_content.append_array(W3RLP::encode_uint(W3BigInt::from_int(0)));
            list_content.append_array(W3RLP::encode_uint(W3BigInt::from_int(0)));
        } else {
            list_content.append_array(W3RLP::encode_uint(W3BigInt::from_bytes(p_v)));
            list_content.append_array(W3RLP::encode_uint(W3BigInt::from_bytes(p_r)));
            list_content.append_array(W3RLP::encode_uint(W3BigInt::from_bytes(p_s)));
        }
    } 
    else if (type == TYPE_EIP1559) {
        list_content.append_array(W3RLP::encode_uint(chain_id));
        list_content.append_array(W3RLP::encode_uint(nonce));
        list_content.append_array(W3RLP::encode_uint(max_priority_fee_per_gas));
        list_content.append_array(W3RLP::encode_uint(max_fee_per_gas));
        list_content.append_array(W3RLP::encode_uint(gas_limit));
        list_content.append_array(W3RLP::encode_bytes(_encode_address_field()));
        list_content.append_array(W3RLP::encode_uint(value));
        list_content.append_array(W3RLP::encode_bytes(data));
        
        PackedByteArray empty_list;
        list_content.append_array(W3RLP::encode_list_payload(empty_list));

        if (!p_for_signing) {
            list_content.append_array(W3RLP::encode_uint(W3BigInt::from_bytes(p_v))); 
            list_content.append_array(W3RLP::encode_uint(W3BigInt::from_bytes(p_r)));
            list_content.append_array(W3RLP::encode_uint(W3BigInt::from_bytes(p_s)));
        }
    }

    return W3RLP::encode_list_payload(list_content);
}

PackedByteArray W3Transaction::get_sign_hash() {
    PackedByteArray rlp_encoded = _rlp_encode_fields(true);
    if (type == TYPE_EIP1559) {
        PackedByteArray prefix;
        prefix.append(0x02);
        prefix.append_array(rlp_encoded);
        return W3Keccak::hash(prefix);
    } else {
        return W3Keccak::hash(rlp_encoded);
    }
}

PackedByteArray W3Transaction::sign(const PackedByteArray& p_priv_key) {
    if (p_priv_key.size() != 32) {
         ERR_PRINT("W3Transaction: Private key must be 32 bytes.");
         return PackedByteArray();
    }

    // ЗАЩИТА ОТ ОШИБОК
    // Если адрес пустой И флаг создания НЕ стоит -> это ошибка (забыли set_to или передали мусор)
    if (to.is_empty() && !is_contract_creation) {
        ERR_PRINT("W3Transaction Error: Destination address is missing. Call 'set_to(addr)' or 'set_creation()'.");
        return PackedByteArray();
    }

    PackedByteArray hash = get_sign_hash();
    PackedByteArray sig = W3Crypto::sign(hash, p_priv_key);
    
    if (sig.size() != 65) {
        ERR_PRINT("W3Transaction: Signature failed.");
        return PackedByteArray();
    }
    
    PackedByteArray r = sig.slice(0, 32);
    PackedByteArray s = sig.slice(32, 64);
    uint8_t rec_id = sig[64];
    
    if (rec_id > 1) {
        ERR_PRINT("W3Transaction: Recovery ID > 1. Signature invalid for Ethereum.");
        return PackedByteArray();
    }

    PackedByteArray v_bytes;
    
    if (type == TYPE_LEGACY) {
        Ref<W3BigInt> chain_id_mul_2 = chain_id->mul(W3BigInt::from_int(2));
        Ref<W3BigInt> constant = W3BigInt::from_int(35 + rec_id);
        Ref<W3BigInt> v_big = chain_id_mul_2->add(constant);
        v_bytes = v_big->get_bytes(false);
    } else {
        v_bytes.resize(1);
        v_bytes[0] = rec_id;
    }
    
    PackedByteArray res = _rlp_encode_fields(false, v_bytes, r, s);
    
    if (type == TYPE_EIP1559) {
        PackedByteArray typed_res;
        typed_res.append(0x02);
        typed_res.append_array(res);
        return typed_res;
    }
    
    return res;
}
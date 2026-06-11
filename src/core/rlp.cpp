#include "rlp.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <cstring> // <--- FIX: Обязательно для memcpy

using namespace godot;

void W3RLP::_bind_methods() {
    ClassDB::bind_static_method("W3RLP", D_METHOD("encode_bytes", "data"), &W3RLP::encode_bytes);
    ClassDB::bind_static_method("W3RLP", D_METHOD("encode_list_payload", "list_payload"), &W3RLP::encode_list_payload);
    ClassDB::bind_static_method("W3RLP", D_METHOD("encode_uint", "value"), &W3RLP::encode_uint);
}

W3RLP::W3RLP() {}
W3RLP::~W3RLP() {}

// --- Internals ---

// FIX: Используем int64_t для защиты от переполнения при сложении
int64_t get_prefix_length(uint64_t length) {
    if (length <= 55) {
        return 1;
    } else {
        uint64_t temp = length;
        int64_t len_bytes = 0;
        while (temp > 0) {
            len_bytes++;
            temp >>= 8;
        }
        return 1 + len_bytes;
    }
}

void write_prefix(uint8_t* ptr, uint64_t length, uint8_t offset) {
    if (length <= 55) {
        ptr[0] = offset + (uint8_t)length;
    } else {
        uint64_t temp = length;
        int len_bytes = 0;
        // Считаем байты (можно было бы передать, но пересчет дешев)
        uint64_t temp_count = length;
        while (temp_count > 0) {
            len_bytes++;
            temp_count >>= 8;
        }
        
        ptr[0] = (offset + 55) + len_bytes;
        
        // Записываем Big Endian
        for (int i = 0; i < len_bytes; i++) {
            ptr[len_bytes - i] = temp & 0xFF;
            temp >>= 8;
        }
    }
}

PackedByteArray W3RLP::encode_bytes(const PackedByteArray& p_data) {
    uint64_t len = p_data.size();
    
    // FIX: Защита от переполнения размера (2GB limit for Godot PackedByteArray safe usage)
    if (len > 0x7FFFFFFF) {
        ERR_PRINT("W3RLP: Data too large to encode");
        return PackedByteArray();
    }
    
    // Case 1: Single byte < 0x80
    if (len == 1 && p_data[0] < 0x80) {
        PackedByteArray res;
        res.resize(1);
        res[0] = p_data[0];
        return res;
    }
    
    int64_t prefix_size = get_prefix_length(len);
    int64_t total_size = prefix_size + (int64_t)len; // FIX: 64-bit math
    
    PackedByteArray res;
    res.resize(total_size);
    uint8_t* ptr = res.ptrw();
    
    // 1. Write Prefix
    write_prefix(ptr, len, 0x80);
    
    // 2. Copy Data
    if (len > 0) {
        // ptr + prefix_size - адресная арифметика
        std::memcpy(ptr + prefix_size, p_data.ptr(), len);
    }
    
    return res;
}

PackedByteArray W3RLP::encode_list_payload(const PackedByteArray& p_list_payload) {
    uint64_t len = p_list_payload.size();
    
    if (len > 0x7FFFFFFF) {
        ERR_PRINT("W3RLP: List payload too large");
        return PackedByteArray();
    }
    
    int64_t prefix_size = get_prefix_length(len);
    int64_t total_size = prefix_size + (int64_t)len;
    
    PackedByteArray res;
    res.resize(total_size);
    uint8_t* ptr = res.ptrw();
    
    write_prefix(ptr, len, 0xC0);
    
    if (len > 0) {
        std::memcpy(ptr + prefix_size, p_list_payload.ptr(), len);
    }
    
    return res;
}

PackedByteArray W3RLP::encode_uint(const Ref<W3BigInt>& p_val) {
    if (p_val.is_null()) {
        // Null -> RLP empty string (0x80)
        PackedByteArray res;
        res.resize(1);
        res[0] = 0x80;
        return res;
    }
    
    // ОПТИМИЗАЦИЯ: Теперь get_bytes(false) использует битовые сдвиги, а не строки.
    // Это быстро.
    PackedByteArray raw = p_val->get_bytes(false);
    
    // Edge Case: Число 0
    // Если get_bytes вернул [0x00] (один байт ноль), для RLP это должно быть 0x80 (пустая строка)
    // Ethereum: "The integer 0 is encoded as an empty byte array"
    if (raw.size() == 1 && raw[0] == 0) {
        PackedByteArray res;
        res.resize(1);
        res[0] = 0x80;
        return res;
    }
    
    // Для всех остальных чисел вызываем стандартный encode_bytes
    // raw уже без ведущих нулей (благодаря get_bytes(false))
    return encode_bytes(raw);
}
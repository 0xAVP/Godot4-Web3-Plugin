#include "w3_abi.hpp"
#include "../utils/hex_utils.hpp"
#include "../crypto/keccak_wrapper.hpp"
#include <godot_cpp/variant/utility_functions.hpp> // Для print/error
#include <cstring> // memcpy

using namespace godot;

// Вспомогательный хелпер
Ref<W3BigInt> _variant_to_bigint(const Variant& p_val) {
    if (p_val.get_type() == Variant::OBJECT) {
        Ref<W3BigInt> bi = p_val;
        if (bi.is_valid()) return bi;
    }
    if (p_val.get_type() == Variant::INT) {
        return W3BigInt::from_int((int64_t)p_val);
    }
    if (p_val.get_type() == Variant::STRING) {
        String s = p_val;
        if (s.begins_with("0x")) return W3BigInt::from_hex(s);
        return W3BigInt::from_string(s);
    }
    return W3BigInt::from_int(0);
}

// Хелпер для создания 32-байтового слова с расширением знака (или нулями)
PackedByteArray _encode_int_word(const Variant& arg, bool is_signed) {
    PackedByteArray word;
    word.resize(32);
    
    if (arg.get_type() == Variant::INT) {
        int64_t val = (int64_t)arg;
        // Если знаковое и отрицательное -> заполняем FF, иначе 00
        uint8_t padding = (is_signed && val < 0) ? 0xFF : 0x00;
        word.fill(padding);
        
        uint8_t* ptr = word.ptrw();
        for(int k=0; k<8; k++) {
            ptr[31-k] = (uint8_t)((val >> (k*8)) & 0xFF);
        }
    } else {
        Ref<W3BigInt> bi = _variant_to_bigint(arg);
        PackedByteArray raw = bi->get_bytes(true); // true = min required bytes
        
        if (raw.size() >= 32) {
            // Если переполнение, берем младшие 32 байта
            word = raw.slice(raw.size() - 32);
        } else {
            // Паддинг
            bool is_neg = is_signed && (raw.size() > 0) && ((raw[0] & 0x80) != 0);
            word.fill(is_neg ? 0xFF : 0x00);
            
            int offset = 32 - raw.size();
            uint8_t* dst = word.ptrw();
            const uint8_t* src = raw.ptr();
            memcpy(dst + offset, src, raw.size());
        }
    }
    return word;
}

PackedByteArray W3ABI::encode_packed(const PackedStringArray& p_types, const Array& p_args) {
    if (p_types.size() != p_args.size()) {
        ERR_PRINT("W3ABI: Types count does not match arguments count in encode_packed.");
        return PackedByteArray();
    }

    PackedByteArray res;

    for (int i = 0; i < p_types.size(); i++) {
        String type = p_types[i];
        Variant arg = p_args[i];

        // 1. INT / UINT (Любой размер)
        if (type.begins_with("int") || type.begins_with("uint")) {
            // Определяем размер в байтах
            int bytes_count = 32;
            String num_str;
            for(int k=type.length()-1; k>=0; k--) {
                if (is_digit(type[k])) num_str = type[k] + num_str;
                else break;
            }
            if (!num_str.is_empty()) bytes_count = num_str.to_int() / 8;

            // Генерируем полное 32-байтовое слово
            bool is_signed = type.begins_with("int");
            PackedByteArray word = _encode_int_word(arg, is_signed);
            
            // Для packed берем только последние N байт
            // Это гарантирует, что int32(0) будет 00 00 00 00, а не просто 00
            res.append_array(word.slice(32 - bytes_count));
        }
        else if (type == "address") {
            PackedByteArray addr_padded = encode_address((String)arg); 
            res.append_array(addr_padded.slice(12, 32));
        }
        else if (type == "bool") {
            res.append( (bool)arg ? 1 : 0 );
        }
        else if (type == "string" || type == "bytes") {
            if (type == "string") {
                res.append_array(((String)arg).to_utf8_buffer());
            } else {
                if (arg.get_type() == Variant::PACKED_BYTE_ARRAY) {
                    res.append_array(arg);
                } else if (arg.get_type() == Variant::STRING) {
                    res.append_array(HexUtils::hex_to_bytes((String)arg));
                }
            }
        }
        else {
             ERR_PRINT("W3ABI: Unsupported type in encode_packed: " + type);
        }
    }
    return res;
}


PackedByteArray W3ABI::encode_params(const PackedStringArray& p_types, const Array& p_args) {
    if (p_types.size() != p_args.size()) {
        ERR_PRINT("W3ABI: Types count does not match arguments count.");
        return PackedByteArray();
    }

    // 1. Сначала считаем размер "головной" части (head)
    int head_size = 0;
    for (int i = 0; i < p_types.size(); i++) {
        head_size += get_static_size(p_types[i]);
    }

    PackedByteArray head;
    head.resize(head_size);
    head.fill(0);
    uint8_t* head_ptr = head.ptrw();

    PackedByteArray tail;
    int current_head_pos = 0;
    int current_tail_offset = head_size;

    for (int i = 0; i < p_types.size(); i++) {
        String type = p_types[i].strip_edges();
        Variant arg = p_args[i];
        PackedByteArray encoded_part;

        // --- ЛОГИКА ОПРЕДЕЛЕНИЯ ТИПА ---
        if (type.begins_with("(") && type.ends_with(")")) {
            encoded_part = encode_params(split_tuple_types(type), arg);
        }
        else if (type.begins_with("uint") || type.begins_with("int")) {
            encoded_part = _encode_int_word(arg, type.begins_with("int"));
        }
        else if (type == "address") {
            encoded_part = encode_address((String)arg);
        }
        else if (type == "bool") {
            encoded_part = encode_bool((bool)arg);
        }
        else if (type == "string") {
            encoded_part = encode_string((String)arg);
        }
        else if (type == "bytes") {
            PackedByteArray b = (arg.get_type() == Variant::PACKED_BYTE_ARRAY) ? arg : HexUtils::hex_to_bytes((String)arg);
            encoded_part = encode_bytes(b);
        }
        else {
            ERR_PRINT("W3ABI: Unsupported type: " + type);
            return PackedByteArray();
        }

        // --- ЗАПИСЬ В HEAD / TAIL ---
        if (is_dynamic(type)) {
            // Пишем смещение в текущую позицию head
            Ref<W3BigInt> offset_bi = W3BigInt::from_int(current_tail_offset);
            PackedByteArray off_bytes = encode_uint256(offset_bi);
            
            memcpy(head_ptr + current_head_pos, off_bytes.ptr(), 32);
            current_head_pos += 32;

            // Сами данные в tail
            tail.append_array(encoded_part);
            current_tail_offset += encoded_part.size();
        } else {
            // Статические данные (примитивы или статические кортежи) пишем прямо в head
            memcpy(head_ptr + current_head_pos, encoded_part.ptr(), encoded_part.size());
            current_head_pos += encoded_part.size();
        }
    }

    head.append_array(tail);
    return head;
}

PackedByteArray W3ABI::encode_uint256(const Ref<W3BigInt>& p_val) {
    // Используем универсальный хелпер для совместимости
    return _encode_int_word(p_val, false);
}

PackedByteArray W3ABI::encode_address(const String& p_addr) {
    PackedByteArray res; 
    
    String clean_addr = p_addr;
    if (clean_addr.begins_with("0x")) clean_addr = clean_addr.substr(2);

    if (clean_addr.length() != 40) {
        ERR_PRINT("W3ABI Error: Address string must be exactly 40 hex characters. Got: " + clean_addr);
        return res; 
    }
    
    PackedByteArray addr_bytes = HexUtils::hex_to_bytes(clean_addr);
    
    if (addr_bytes.size() != 20) {
         ERR_PRINT("W3ABI Error: Failed to decode address hex bytes.");
         return res; 
    }
    
    res.resize(32);
    res.fill(0);
    
    int offset = 32 - 20; 
    const uint8_t* src = addr_bytes.ptr();
    uint8_t* dst = res.ptrw();
    
    for(int i=0; i < 20; i++) {
        dst[offset + i] = src[i];
    }
    
    return res;
}

PackedByteArray W3ABI::encode_bool(bool p_val) {
    PackedByteArray res;
    res.resize(32);
    res.fill(0);
    if (p_val) res[31] = 1;
    return res;
}

PackedByteArray W3ABI::encode_function_selector(const String& p_signature) {
    PackedByteArray hash = W3Keccak::hash(p_signature.to_utf8_buffer());
    return hash.slice(0, 4);
}

PackedByteArray W3ABI::encode_bytes_n(const PackedByteArray& p_val, int N) {
    if (N <= 0 || N > 32) {
        ERR_PRINT("W3ABI: bytesN size must be between 1 and 32");
        return PackedByteArray();
    }
    PackedByteArray res;
    res.resize(32);
    res.fill(0);
    int size = p_val.size();
    if (size > N) size = N;
    const uint8_t* src = p_val.ptr();
    uint8_t* dst = res.ptrw();
    for(int i=0; i < size; i++) {
        dst[i] = src[i];
    }
    return res;
}

PackedByteArray W3ABI::encode_bytes(const PackedByteArray& p_val) {
    int len = p_val.size();
    Ref<W3BigInt> len_bi = W3BigInt::from_int(len);
    PackedByteArray res = encode_uint256(len_bi);
    
    if (len > 0) {
        int padded_len = ((len + 31) / 32) * 32;
        PackedByteArray data_padded;
        data_padded.resize(padded_len);
        data_padded.fill(0);
        
        const uint8_t* src = p_val.ptr();
        uint8_t* dst = data_padded.ptrw();
        memcpy(dst, src, len);
        
        res.append_array(data_padded);
    }
    return res;
}

PackedByteArray W3ABI::encode_string(const String& p_val) {
    return encode_bytes(p_val.to_utf8_buffer());
}
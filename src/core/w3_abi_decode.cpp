#include "w3_abi.hpp"
#include "../utils/hex_utils.hpp"
#include <godot_cpp/variant/utility_functions.hpp>
#include <cstring> 

using namespace godot;

// --- CONFIG ---
const int MAX_RECURSION_DEPTH = 32; // БЕЗОПАСНОСТЬ: Лимит вложенности

// ============================================================================
// INTERNAL HELPERS
// ============================================================================

class ABIDecoderCtx {
private:
    const uint8_t* _data;
    size_t _size;

public:
    size_t cursor; 
    bool failed;

    ABIDecoderCtx(const PackedByteArray& p_data) {
        _data = p_data.ptr();
        _size = p_data.size();
        cursor = 0;
        failed = false;
    }

    ABIDecoderCtx jump(size_t absolute_offset) const {
        if (absolute_offset > _size) {
            static PackedByteArray dummy;
            ABIDecoderCtx broken(dummy);
            broken.failed = true;
            return broken;
        }
        
        static PackedByteArray dummy; 
        ABIDecoderCtx new_ctx(dummy); 
        
        new_ctx._data = _data; 
        new_ctx._size = _size;
        new_ctx.cursor = absolute_offset;
        new_ctx.failed = failed; 
        return new_ctx;
    }

    bool can_read(size_t n) {
        if (failed) return false;
        if (cursor + n > _size) {
            failed = true; 
            return false;
        }
        return true;
    }

    PackedByteArray read_word() {
        PackedByteArray res;
        res.resize(32);
        
        if (!can_read(32)) {
            res.fill(0); 
            return res;
        }
        
        memcpy(res.ptrw(), _data + cursor, 32);
        cursor += 32;
        return res;
    }
    
    // ОПТИМИЗАЦИЯ: Читаем uint64 напрямую из памяти без аллокации PackedByteArray
    int64_t read_uint64_word() {
        if (!can_read(32)) return -1;

        const uint8_t* word = _data + cursor;
        
        // Проверяем старшие 24 байта на 0 (защита от переполнения int64)
        for(int i=0; i<24; i++) {
            if (word[i] != 0) {
                cursor += 32;
                return -1; 
            }
        }
        
        uint64_t val = 0;
        for(int i=24; i<32; i++) {
            val = (val << 8) | word[i];
        }
        
        cursor += 32;
        return (int64_t)val;
    }

    PackedByteArray read_bytes(size_t n) {
        PackedByteArray res;
        if (!can_read(n)) {
            return res; 
        }
        res.resize(n);
        memcpy(res.ptrw(), _data + cursor, n);
        cursor += n;
        return res;
    }
};


// ============================================================================
// RECURSIVE DECODER
// ============================================================================

Variant _decode_recursive(const String& type, ABIDecoderCtx& ctx, int depth) {
    if (ctx.failed) return Variant();
    if (depth > MAX_RECURSION_DEPTH) { ctx.failed = true; return Variant(); }

    if (type.begins_with("(") && type.ends_with(")")) {
        // ИСПОЛЬЗУЕМ КЛАССНЫЙ МЕТОД
        PackedStringArray subtypes = W3ABI::split_tuple_types(type);
        Array tuple_result;
        size_t tuple_head_start = ctx.cursor;
        
        for (int i = 0; i < subtypes.size(); i++) {
            String subtype = subtypes[i];
            // ИСПОЛЬЗУЕМ КЛАССНЫЙ МЕТОД
            if (W3ABI::is_dynamic(subtype)) {
                int64_t rel_offset = ctx.read_uint64_word();
                if (ctx.failed || rel_offset < 0) return Variant(); 
                ABIDecoderCtx sub_ctx = ctx.jump(tuple_head_start + (size_t)rel_offset);
                tuple_result.append(_decode_recursive(subtype, sub_ctx, depth + 1));
                if (sub_ctx.failed) ctx.failed = true;
            } else {
                tuple_result.append(_decode_recursive(subtype, ctx, depth + 1));
            }
        }
        return tuple_result;
    }

    // --- STRING / BYTES ---
    if (type == "string" || type == "bytes") {
        int64_t len = ctx.read_uint64_word();
        if (ctx.failed || len < 0) return (type == "string" ? Variant("") : Variant(PackedByteArray()));
        
        PackedByteArray raw = ctx.read_bytes((size_t)len);
        if (ctx.failed) return Variant();
        
        size_t padding = (32 - (len % 32)) % 32;
        if (!ctx.can_read(padding)) return Variant(); 
        ctx.cursor += padding;
        
        if (type == "string") {
            return raw.get_string_from_utf8();
        } else {
            return raw;
        }
    }

    // --- PRIMITIVES ---
    PackedByteArray word = ctx.read_word();
    if (ctx.failed) return Variant(); 
    
    if (type == "address") {
        PackedByteArray addr = word.slice(12, 32);
        return "0x" + HexUtils::bytes_to_hex(addr);
    }
    else if (type == "bool") {
        return word[31] != 0;
    }
    else if (type == "uint256" || type.begins_with("uint")) {
        return W3BigInt::from_bytes(word); 
    }
    else if (type == "int256" || type.begins_with("int")) {
        return W3BigInt::from_bytes(word); 
    }
    
    ERR_PRINT("W3ABI Decode: Unknown type " + type);
    return Variant();
}

// ============================================================================
// MAIN ENTRY POINTS
// ============================================================================

Array W3ABI::decode(const PackedStringArray& p_types, const PackedByteArray& p_data) {
    Array result;
    ABIDecoderCtx ctx(p_data);
    if (p_data.size() == 0 && p_types.size() > 0) return Array();

    for (int i = 0; i < p_types.size(); i++) {
        String type = p_types[i];
        // ИСПОЛЬЗУЕМ КЛАССНЫЙ МЕТОД
        if (is_dynamic(type)) {
            int64_t offset = ctx.read_uint64_word();
            if (ctx.failed || offset < 0) return Array();
            ABIDecoderCtx sub_ctx = ctx.jump((size_t)offset);
            result.append(_decode_recursive(type, sub_ctx, 0));
            if (sub_ctx.failed) return Array(); 
        } else {
            result.append(_decode_recursive(type, ctx, 0));
        }
        if (ctx.failed) return Array(); 
    }
    return result;
}

String W3ABI::decode_revert_reason(const PackedByteArray& p_data) {
    if (p_data.size() < 4) return "Revert (No data)";
    
    const uint8_t* ptr = p_data.ptr();
    uint32_t selector = 0;
    selector |= (uint32_t)ptr[0] << 24;
    selector |= (uint32_t)ptr[1] << 16;
    selector |= (uint32_t)ptr[2] << 8;
    selector |= (uint32_t)ptr[3];
    
    PackedByteArray payload = p_data.slice(4);
    
    // Error(string)
    if (selector == 0x08c379a0) { 
        PackedStringArray t; t.push_back("string");
        Array res = decode(t, payload);
        if (res.size() > 0) return "execution reverted: " + String(res[0]);
    }
    
    // Panic(uint256)
    if (selector == 0x4e487b71) { 
        PackedStringArray t; t.push_back("uint256");
        Array res = decode(t, payload);
        if (res.size() > 0) {
            Ref<W3BigInt> code_bi = res[0];
            String code_str = code_bi->to_string_val();
            int64_t code = code_str.to_int();
            
            String desc = "Unknown Panic";
            switch (code) {
                case 0x01: desc = "Assertion failed"; break;
                case 0x11: desc = "Arithmetic overflow/underflow"; break;
                case 0x12: desc = "Division or modulo by zero"; break;
                case 0x21: desc = "Enum conversion failed"; break;
                case 0x22: desc = "Storage byte array incorrectly encoded"; break;
                case 0x31: desc = "Pop empty array"; break;
                case 0x32: desc = "Array index out of bounds"; break;
                case 0x41: desc = "Memory allocation too much"; break;
                case 0x51: desc = "Zero-initialized variable of internal function type"; break;
            }
            return "Panic(" + code_str + "): " + desc;
        }
    }
    
    return "execution reverted (unknown: " + HexUtils::bytes_to_hex(p_data, true) + ")";
}
#include "w3_abi.hpp"
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// --- Логика определения динамических типов по спецификации ABI ---
bool W3ABI::is_dynamic(const String& type) {
    if (type == "string" || type == "bytes" || type.ends_with("[]")) return true;
    if (type.begins_with("(") && type.ends_with(")")) {
        PackedStringArray components = split_tuple_types(type);
        for (int i = 0; i < components.size(); i++) {
            if (is_dynamic(components[i])) return true;
        }
    }
    return false;
}

PackedStringArray W3ABI::split_tuple_types(const String& p_type_str) {
    PackedStringArray res;
    String clean = p_type_str.strip_edges();
    if (clean.begins_with("(") && clean.ends_with(")")) {
        clean = clean.substr(1, clean.length() - 2);
    }
    String current;
    int depth = 0;
    for (int i = 0; i < clean.length(); i++) {
        char32_t c = clean[i];
        if (c == '(') depth++;
        else if (c == ')') depth--;
        if (c == ',' && depth == 0) {
            res.append(current.strip_edges());
            current = "";
        } else {
            current += c;
        }
    }
    if (!current.is_empty()) res.append(current.strip_edges());
    return res;
}

// Вычисляет, сколько байт тип занимает в "голове" (head) параметров
int W3ABI::get_static_size(const String& type) {
    if (is_dynamic(type)) return 32; // Динамические типы всегда занимают 32 байта (смещение)
    if (type.begins_with("(") && type.ends_with(")")) {
        PackedStringArray components = split_tuple_types(type);
        int total = 0;
        for (int i = 0; i < components.size(); i++) {
            total += get_static_size(components[i]);
        }
        return total;
    }
    return 32; // Примитивы (uint, address, bool)
}

void W3ABI::_bind_methods() {
    // Encoders
    ClassDB::bind_static_method("W3ABI", D_METHOD("encode_uint256", "value"), &W3ABI::encode_uint256);
    ClassDB::bind_static_method("W3ABI", D_METHOD("encode_address", "address"), &W3ABI::encode_address);
    ClassDB::bind_static_method("W3ABI", D_METHOD("encode_bool", "value"), &W3ABI::encode_bool);
    ClassDB::bind_static_method("W3ABI", D_METHOD("encode_function_selector", "signature"), &W3ABI::encode_function_selector);
    ClassDB::bind_static_method("W3ABI", D_METHOD("encode_string", "value"), &W3ABI::encode_string);
    ClassDB::bind_static_method("W3ABI", D_METHOD("encode_bytes", "value"), &W3ABI::encode_bytes);
    ClassDB::bind_static_method("W3ABI", D_METHOD("encode_bytes_n", "value", "N"), &W3ABI::encode_bytes_n);
    ClassDB::bind_static_method("W3ABI", D_METHOD("encode_params", "types", "args"), &W3ABI::encode_params);
    ClassDB::bind_static_method("W3ABI", D_METHOD("encode_packed", "types", "args"), &W3ABI::encode_packed);
    
    // Decoders (New)
    ClassDB::bind_static_method("W3ABI", D_METHOD("decode", "types", "data"), &W3ABI::decode);
    ClassDB::bind_static_method("W3ABI", D_METHOD("decode_revert_reason", "data"), &W3ABI::decode_revert_reason);
}

W3ABI::W3ABI() {}
W3ABI::~W3ABI() {}
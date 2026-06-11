#ifndef HEX_UTILS_HPP
#define HEX_UTILS_HPP

#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

using namespace godot;

class HexUtils {
public:
    static String bytes_to_hex(const PackedByteArray& p_bytes, bool p_add_prefix = false) {
        if (p_bytes.size() == 0) return p_add_prefix ? "0x" : "";
        String hex = p_bytes.hex_encode();
        if (p_add_prefix) return "0x" + hex;
        return hex;
    }

    static PackedByteArray hex_to_bytes(String p_hex) {
        if (p_hex.begins_with("0x")) {
            p_hex = p_hex.substr(2);
        }
        
        // Добавляем ведущий ноль для корректного декодирования, если длина нечетная
        if (p_hex.length() % 2 != 0) {
            p_hex = "0" + p_hex; 
        }
        
        // Используем встроенный метод Godot (быстрее и надежнее)
        return p_hex.hex_decode();
    }
};

#endif
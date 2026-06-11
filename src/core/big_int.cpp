#include "big_int.hpp"
#include "../utils/hex_utils.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <stdexcept>
#include <cstring>

using namespace godot;

// MAX UINT256 в десятичном виде (для валидации from_string)
// 2^256 - 1 = 115792089237316195423570985008687907853269984665640564039457584007913129639935
static const char* MAX_UINT256_DEC = "115792089237316195423570985008687907853269984665640564039457584007913129639935";

void W3BigInt::_bind_methods() {
    // Statics
    ClassDB::bind_static_method("W3BigInt", D_METHOD("from_string", "value"), &W3BigInt::from_string);
    ClassDB::bind_static_method("W3BigInt", D_METHOD("from_hex", "value"), &W3BigInt::from_hex);
    ClassDB::bind_static_method("W3BigInt", D_METHOD("from_int", "value"), &W3BigInt::from_int);
    ClassDB::bind_static_method("W3BigInt", D_METHOD("from_bytes", "bytes"), &W3BigInt::from_bytes);

    // Arithmetic
    ClassDB::bind_method(D_METHOD("add", "other"), &W3BigInt::add);
    ClassDB::bind_method(D_METHOD("sub", "other"), &W3BigInt::sub);
    ClassDB::bind_method(D_METHOD("mul", "other"), &W3BigInt::mul);
    ClassDB::bind_method(D_METHOD("div", "other"), &W3BigInt::div);
    ClassDB::bind_method(D_METHOD("mod", "other"), &W3BigInt::mod);
    
    ClassDB::bind_method(D_METHOD("iadd", "other"), &W3BigInt::iadd);
    ClassDB::bind_method(D_METHOD("isub", "other"), &W3BigInt::isub);
    ClassDB::bind_method(D_METHOD("imul", "other"), &W3BigInt::imul);

    // Comparison Unsigned
    ClassDB::bind_method(D_METHOD("equals", "other"), &W3BigInt::equals);
    ClassDB::bind_method(D_METHOD("gt", "other"), &W3BigInt::gt);
    ClassDB::bind_method(D_METHOD("lt", "other"), &W3BigInt::lt);

    // Comparison Signed
    ClassDB::bind_method(D_METHOD("gt_signed", "other"), &W3BigInt::gt_signed);
    ClassDB::bind_method(D_METHOD("lt_signed", "other"), &W3BigInt::lt_signed);

    // Conversion
    ClassDB::bind_method(D_METHOD("to_string_val"), &W3BigInt::to_string_val);
    ClassDB::bind_method(D_METHOD("to_int256_string"), &W3BigInt::to_int256_string);
    ClassDB::bind_method(D_METHOD("to_hex", "with_prefix"), &W3BigInt::to_hex, DEFVAL(true));
    ClassDB::bind_method(D_METHOD("get_bytes", "pad_to_32"), &W3BigInt::get_bytes, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("_to_string"), &W3BigInt::_to_string);
}

// --- Helpers ---

bool W3BigInt::_is_valid_decimal(const String& s) {
    if (s.is_empty()) return false;
    for (int i = 0; i < s.length(); i++) {
        if (!is_digit(s[i])) return false;
    }
    return true;
}

bool W3BigInt::_is_valid_hex(const String& s) {
    if (s.is_empty()) return false;
    for (int i = 0; i < s.length(); i++) {
        char32_t c = s[i];
        bool is_digit = (c >= '0' && c <= '9');
        bool is_lower = (c >= 'a' && c <= 'f');
        bool is_upper = (c >= 'A' && c <= 'F');
        if (!(is_digit || is_lower || is_upper)) return false;
    }
    return true;
}

bool is_negative_internal(const uint256_t& val) {
    return (val >> 255) == 1;
}

// --- Implementation ---

W3BigInt::W3BigInt() { value = 0; }
W3BigInt::W3BigInt(const uint256_t& p_val) { value = p_val; }
W3BigInt::~W3BigInt() {}

Ref<W3BigInt> W3BigInt::from_string(const String& p_val) {
    Ref<W3BigInt> res;
    res.instantiate();
    
    String s = p_val.strip_edges();
    if (s.is_empty()) {
        ERR_PRINT("W3BigInt: Empty string");
        res->value = 0;
        return res;
    }

    bool is_negative = false;
    if (s.begins_with("-")) {
        is_negative = true;
        s = s.substr(1);
    } else if (s.begins_with("+")) {
        s = s.substr(1);
    }
    
    // Удаляем ведущие нули для корректной проверки длины
    while (s.length() > 1 && s[0] == '0') {
        s = s.substr(1);
    }
    
    if (!_is_valid_decimal(s)) {
        ERR_PRINT("W3BigInt: Invalid character in decimal string: " + p_val);
        res->value = 0;
        return res;
    }

    // --- OVERFLOW CHECK (Decimal) ---
    // Max length of uint256 in decimal is 78 chars.
    if (s.length() > 78) {
        ERR_PRINT("W3BigInt: Value exceeds uint256 range (too many digits)");
        res->value = 0;
        return res;
    } else if (s.length() == 78) {
        // Лексикографическое сравнение с MAX_UINT256
        String max_s = String(MAX_UINT256_DEC);
        if (s > max_s) {
             ERR_PRINT("W3BigInt: Value exceeds uint256 range");
             res->value = 0;
             return res;
        }
    }
    // --------------------------------
    
    CharString cs = s.utf8();
    std::string std_s = cs.get_data();

    try {
        res->value = uint256_t(std_s, 10);
        if (is_negative) {
            uint256_t zero = 0;
            res->value = zero - res->value;
        }
    } catch (...) {
        ERR_PRINT("W3BigInt: Parsing exception: " + p_val);
        res->value = 0;
    }
    return res;
}

Ref<W3BigInt> W3BigInt::from_hex(const String& p_val) {
    Ref<W3BigInt> res;
    res.instantiate();
    
    String clean_hex = p_val.strip_edges();
    if (clean_hex.begins_with("0x") || clean_hex.begins_with("0X")) {
        clean_hex = clean_hex.substr(2);
    }
    
    // Удаляем ведущие нули
    while (clean_hex.length() > 0 && clean_hex[0] == '0') {
        clean_hex = clean_hex.substr(1);
    }
    
    // Обработка случая "0x00" или "0x" -> "0"
    if (clean_hex.length() == 0) {
        res->value = 0;
        return res;
    }

    if (!_is_valid_hex(clean_hex)) {
        ERR_PRINT("W3BigInt: Invalid character in hex string: " + p_val);
        res->value = 0;
        return res;
    }
    
    // --- OVERFLOW CHECK (Hex) ---
    // Max length of uint256 in hex is 64 chars (32 bytes * 2).
    if (clean_hex.length() > 64) {
        ERR_PRINT("W3BigInt: Hex value exceeds uint256 range (too many digits)");
        res->value = 0; // Возвращаем 0, а не "обрезанное" значение
        return res;
    }
    // ----------------------------
    
    CharString cs = clean_hex.utf8();
    std::string s = cs.get_data();
    try {
        res->value = uint256_t(s, 16);
    } catch (...) {
        ERR_PRINT("W3BigInt: Hex parsing exception");
        res->value = 0;
    }
    return res;
}

Ref<W3BigInt> W3BigInt::from_int(int64_t p_val) {
    Ref<W3BigInt> res;
    res.instantiate();
    if (p_val >= 0) {
        res->value = uint256_t(p_val);
    } else {
        uint256_t abs_val = uint256_t(-p_val);
        uint256_t zero = 0;
        res->value = zero - abs_val;
    }
    return res;
}

Ref<W3BigInt> W3BigInt::from_bytes(const PackedByteArray& p_bytes) {
    // bytes_to_hex вернет строку вида "0100..."
    // Если p_bytes > 32 байта, from_hex теперь проверит это (после удаления ведущих нулей)
    String hex = HexUtils::bytes_to_hex(p_bytes, false);
    return from_hex(hex);
}

// --- Comparisons (Signed Logic) ---

bool W3BigInt::gt_signed(const Ref<W3BigInt>& p_other) {
    if (p_other.is_null()) return false;
    bool sign_a = is_negative_internal(value);
    bool sign_b = is_negative_internal(p_other->value);
    if (sign_a != sign_b) return !sign_a;
    return value > p_other->value;
}

bool W3BigInt::lt_signed(const Ref<W3BigInt>& p_other) {
    if (p_other.is_null()) return false;
    bool sign_a = is_negative_internal(value);
    bool sign_b = is_negative_internal(p_other->value);
    if (sign_a != sign_b) return sign_a;
    return value < p_other->value;
}

// ... Arithmetic methods (Standard) ...

Ref<W3BigInt> W3BigInt::add(const Ref<W3BigInt>& p_other) { Ref<W3BigInt> r; r.instantiate(); if(p_other.is_valid()) r->value = value + p_other->value; return r; }
Ref<W3BigInt> W3BigInt::sub(const Ref<W3BigInt>& p_other) { Ref<W3BigInt> r; r.instantiate(); if(p_other.is_valid()) r->value = value - p_other->value; return r; }
Ref<W3BigInt> W3BigInt::mul(const Ref<W3BigInt>& p_other) { Ref<W3BigInt> r; r.instantiate(); if(p_other.is_valid()) r->value = value * p_other->value; return r; }
Ref<W3BigInt> W3BigInt::div(const Ref<W3BigInt>& p_other) { Ref<W3BigInt> r; r.instantiate(); if(p_other.is_valid() && p_other->value != 0) r->value = value / p_other->value; return r; }
Ref<W3BigInt> W3BigInt::mod(const Ref<W3BigInt>& p_other) { Ref<W3BigInt> r; r.instantiate(); if(p_other.is_valid() && p_other->value != 0) r->value = value % p_other->value; return r; }

void W3BigInt::iadd(const Ref<W3BigInt>& p_other) { if(p_other.is_valid()) value += p_other->value; }
void W3BigInt::isub(const Ref<W3BigInt>& p_other) { if(p_other.is_valid()) value -= p_other->value; }
void W3BigInt::imul(const Ref<W3BigInt>& p_other) { if(p_other.is_valid()) value *= p_other->value; }

bool W3BigInt::equals(const Ref<W3BigInt>& p_other) { if (p_other.is_null()) return false; return value == p_other->value; }
bool W3BigInt::gt(const Ref<W3BigInt>& p_other) { if (p_other.is_null()) return false; return value > p_other->value; }
bool W3BigInt::lt(const Ref<W3BigInt>& p_other) { if (p_other.is_null()) return false; return value < p_other->value; }

String W3BigInt::to_string_val() const {
    std::string s = value.str(10);
    return String(s.c_str());
}

String W3BigInt::to_int256_string() const {
    std::string hex = value.str(16, 64);
    char first_char = hex[0];
    bool is_negative = (first_char >= '8' && first_char <= '9') || (first_char >= 'a' && first_char <= 'f');
    if (!is_negative) return to_string_val();
    uint256_t zero = 0;
    uint256_t abs_val = zero - value;
    std::string s = abs_val.str(10);
    return "-" + String(s.c_str());
}

String W3BigInt::to_hex(bool p_with_prefix) {
    std::string s = value.str(16, 0); 
    String hex = String(s.c_str()).to_lower();
    if (p_with_prefix) return "0x" + hex;
    return hex;
}

String W3BigInt::_to_string() const { return to_string_val(); }

PackedByteArray W3BigInt::get_bytes(bool p_pad_to_32) const {
    // 1. Аллоцируем буфер на стеке (быстро)
    uint8_t buf[32];
    // Очищаем, так как будем заполнять не всё, если число маленькое?
    // Нет, мы будем заполнять всё или часть.
    // Для безопасности обнулим.
    std::memset(buf, 0, 32);
    
    // 2. Экстракция байтов из uint256_t напрямую (Big Endian)
    // uint256_t поддерживает побитовые операции.
    // Мы идем с конца (младшие байты) в начало.
    uint256_t temp = value;
    
    // Оптимизация: если число 0, можно сразу вернуть.
    if (temp == 0) {
        PackedByteArray res;
        if (p_pad_to_32) {
            res.resize(32);
            res.fill(0);
        } else {
            // Для "сырого" 0 возвращаем 1 байт [0x00], как это делает hex_decode("00")
            res.resize(1);
            res[0] = 0;
        }
        return res;
    }

    // Заполняем буфер с конца (31) к началу (0)
    for (int i = 31; i >= 0; --i) {
        buf[i] = (uint8_t)(temp & 0xFF);
        temp >>= 8;
    }
    
    // 3. Формируем результат
    if (p_pad_to_32) {
        PackedByteArray res;
        res.resize(32);
        std::memcpy(res.ptrw(), buf, 32);
        return res;
    } else {
        // Нужно найти первый ненулевой байт (strip leading zeros)
        int start = 0;
        while (start < 32 && buf[start] == 0) {
            start++;
        }
        
        // Если все нули (value=0), мы это обработали выше, но на всякий случай:
        if (start == 32) {
            PackedByteArray res; 
            res.resize(1); 
            res[0] = 0; 
            return res;
        }
        
        int len = 32 - start;
        PackedByteArray res;
        res.resize(len);
        std::memcpy(res.ptrw(), buf + start, len);
        return res;
    }
}
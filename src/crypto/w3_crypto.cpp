#include "w3_crypto.hpp"
#include "keccak_wrapper.hpp"
#include "../utils/hex_utils.hpp"
#include "../vendor/phc-winner-argon2/include/argon2.h"
#include "../vendor/qrcodegen/qrcodegen.h"
#include "../core/big_int.hpp"
#include <godot_cpp/classes/image.hpp>

extern "C" {
#include "ecdsa.h"
#include "secp256k1.h"
#include "pbkdf2.h"
#include "aes/aes.h"
int ecdsa_recover_pub_from_sig(const ecdsa_curve *curve, uint8_t *pub_key, const uint8_t *sig, const uint8_t *msg, int recid);
#undef aes_ctr_encrypt
#undef aes_ctr_decrypt
void memzero(void *s, size_t n);
void random_buffer(uint8_t *buf, size_t len);
}

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace {
    // Хеширует строку или байты для EIP-712 (keccak256)
    PackedByteArray hash_eip712_data(const Variant& p_var) {
        if (p_var.get_type() == Variant::STRING) {
            return W3Keccak::hash(p_var.operator String().to_utf8_buffer());
        }
        return W3Keccak::hash(p_var.operator PackedByteArray());
    }

    // Упаковывает адрес (20 байт) в 32-байтовое слово (left-padded)
    PackedByteArray pack_address_word(const String& p_addr) {
        PackedByteArray res;
        res.resize(32);
        res.fill(0);
        
        String clean_addr = p_addr.replace("0x", "").replace("0X", "");
        PackedByteArray bytes = clean_addr.hex_decode();
        
        if (bytes.size() == 20) {
            memcpy(res.ptrw() + 12, bytes.ptr(), 20);
        }
        return res;
    }

    // Упаковывает uint256/int256 в 32-байтовое слово
    PackedByteArray pack_uint256_word(const Variant& p_val) {
    if (p_val.get_type() == Variant::OBJECT) {
        Ref<W3BigInt> bi = p_val;
        if (bi.is_valid()) return bi->get_bytes(true);
    }
    if (p_val.get_type() == Variant::STRING) {
        // Поддержка строк "123" или "0xabc"
        return W3BigInt::from_string(p_val)->get_bytes(true);
    }
    // Fallback для обычных int64
    return W3BigInt::from_int((int64_t)p_val)->get_bytes(true);
}
}
// --- КОНЕЦ БЛОКА ХЕЛПЕРОВ ---

void W3Crypto::_bind_methods() {
    ClassDB::bind_static_method("W3Crypto", D_METHOD("get_eip712_forward_request_hash", "domain", "message"), &W3Crypto::get_eip712_forward_request_hash);
    ClassDB::bind_static_method("W3Crypto", D_METHOD("generate_qr_code", "data", "scale"), &W3Crypto::generate_qr_code, DEFVAL(10));
    ClassDB::bind_static_method("W3Crypto", D_METHOD("generate_private_key"), &W3Crypto::generate_private_key);
    ClassDB::bind_static_method("W3Crypto", D_METHOD("get_public_key", "private_key", "compressed"), &W3Crypto::get_public_key);
    ClassDB::bind_static_method("W3Crypto", D_METHOD("sign", "hash", "private_key"), &W3Crypto::sign);
    ClassDB::bind_static_method("W3Crypto", D_METHOD("get_address_from_pubkey", "public_key"), &W3Crypto::get_address_from_pubkey);
    ClassDB::bind_static_method("W3Crypto", D_METHOD("recover_address", "hash", "signature"), &W3Crypto::recover_address);
    ClassDB::bind_static_method("W3Crypto", D_METHOD("secure_wipe", "data"), &W3Crypto::secure_wipe);
    ClassDB::bind_static_method("W3Crypto", D_METHOD("secure_compare", "a", "b"), &W3Crypto::secure_compare);
    ClassDB::bind_static_method("W3Crypto", D_METHOD("pbkdf2", "password", "salt", "iterations", "key_length"), &W3Crypto::pbkdf2);
    ClassDB::bind_static_method("W3Crypto", D_METHOD("aes_ctr_encrypt", "data", "key", "iv"), &W3Crypto::aes_ctr_encrypt);
    ClassDB::bind_static_method("W3Crypto", D_METHOD("aes_ctr_decrypt", "data", "key", "iv"), &W3Crypto::aes_ctr_decrypt);
    ClassDB::bind_static_method("W3Crypto", D_METHOD("argon2id", "password", "salt", "iterations", "memory_kb", "parallelism", "key_length"), &W3Crypto::argon2id);
}

W3Crypto::W3Crypto() {}
W3Crypto::~W3Crypto() {}

PackedByteArray W3Crypto::generate_private_key() {
    PackedByteArray priv;
    priv.resize(32);
    // Secure RNG
    random_buffer(priv.ptrw(), 32); 
    return priv;
}

void W3Crypto::secure_wipe(PackedByteArray p_data) {
    // FIX: Используем ptr() вместо ptrw().
    // ptrw() в Godot вызывает Copy-On-Write (копирование), если RefCount > 1.
    // Так как массив удерживается переменной в GDScript, копирование происходило всегда.
    // ptr() просто возвращает адрес памяти текущего буфера.
    
    const uint8_t *ptr = p_data.ptr();
    
    if (ptr) {
        // Снимаем const, чтобы затереть данные "на месте" (in-place modification)
        uint8_t *mutable_ptr = const_cast<uint8_t*>(ptr);
        memzero(mutable_ptr, p_data.size());
    }
}

bool W3Crypto::secure_compare(const PackedByteArray& a, const PackedByteArray& b) {
    int len_a = a.size();
    int len_b = b.size();

    // СЛУЧАЙ 1: Длины равны (Web3 Happy Path: адреса, хеши)
    // Это безопасно: время выполнения зависит от длины, которая и так известна (public info),
    // но НЕ зависит от того, где именно символы начали различаться.
    if (len_a == len_b) {
        const uint8_t* ptr_a = a.ptr();
        const uint8_t* ptr_b = b.ptr();
        
        volatile uint8_t diff = 0;
        for(int i = 0; i < len_a; i++) {
            diff |= (ptr_a[i] ^ ptr_b[i]);
        }
        return diff == 0;
    }

    // СЛУЧАЙ 2: Длины разные (API ключи, пароли, мусор)
    // Здесь мы используем хеширование, чтобы время сравнения было примерно одинаковым
    // и не зависело от того, насколько одна строка короче другой.
    
    // Считаем хеши от обоих аргументов
    // (W3Keccak::hash всегда возвращает 32 байта)
    PackedByteArray hash_a = W3Keccak::hash(a);
    PackedByteArray hash_b = W3Keccak::hash(b);
    
    // Рекурсивно вызываем secure_compare для хешей.
    // Так как хеши всегда 32 байта, они попадут в "СЛУЧАЙ 1" (быстрый XOR).
    return secure_compare(hash_a, hash_b);
}

PackedByteArray W3Crypto::get_public_key(const PackedByteArray& p_priv_key, bool p_compressed) {
    if (p_priv_key.size() != 32) {
        ERR_PRINT("W3Crypto: Private key must be 32 bytes.");
        return PackedByteArray();
    }

    const ecdsa_curve *curve = &secp256k1;
    
    // Копируем приватный ключ во временный буфер стека
    uint8_t priv_temp[32];
    memcpy(priv_temp, p_priv_key.ptr(), 32);

    PackedByteArray res;
    
    if (p_compressed) {
        res.resize(33);
        uint8_t pub[33];
        ecdsa_get_public_key33(curve, priv_temp, pub);
        memcpy(res.ptrw(), pub, 33);
    } else {
        res.resize(65);
        uint8_t pub[65];
        ecdsa_get_public_key65(curve, priv_temp, pub);
        memcpy(res.ptrw(), pub, 65);
    }
    
    // SECURITY: Очищаем стек
    memzero(priv_temp, 32);

    return res;
}


String W3Crypto::recover_address(const PackedByteArray& p_hash, const PackedByteArray& p_sig) {
    if (p_hash.size() != 32 || p_sig.size() != 65) return "";

    const uint8_t* hash_ptr = p_hash.ptr();
    const uint8_t* sig_ptr = p_sig.ptr();
    
    uint8_t v = sig_ptr[64];
    
    // Поддержка всех вариантов: 0/1, 27/28 и даже 37/38 (EIP-155)
    // Библиотека Trezor ожидает 0, 1, 2 или 3.
    if (v >= 37) v = (v - 35) % 2;
    if (v >= 27) v -= 27;

    uint8_t recovered_pub[65];
    const ecdsa_curve *curve = &secp256k1;

    // В Trezor ecdsa_recover_pub_from_sig возвращает 0 при успехе
    if (ecdsa_recover_pub_from_sig(curve, recovered_pub, sig_ptr, hash_ptr, v) == 0) {
        PackedByteArray pub_bytes;
        pub_bytes.resize(65);
        memcpy(pub_bytes.ptrw(), recovered_pub, 65);
        return get_address_from_pubkey(pub_bytes);
    }
    return "";
}

PackedByteArray W3Crypto::sign(const PackedByteArray& p_hash, const PackedByteArray& p_priv_key) {
    if (p_hash.size() != 32) {
        ERR_PRINT("W3Crypto: Hash must be 32 bytes.");
        return PackedByteArray();
    }
    if (p_priv_key.size() != 32) {
        ERR_PRINT("W3Crypto: Private key must be 32 bytes.");
        return PackedByteArray();
    }

    const ecdsa_curve *curve = &secp256k1;
    uint8_t pby;
    uint8_t sig[64];
    
    uint8_t priv_temp[32];
    memcpy(priv_temp, p_priv_key.ptr(), 32);
    
    int result = ecdsa_sign_digest(curve, priv_temp, p_hash.ptr(), sig, &pby, NULL);
    
    // SECURITY: Очищаем стек
    memzero(priv_temp, 32);

    if (result != 0) {
        ERR_PRINT("W3Crypto: Signing failed.");
        return PackedByteArray();
    }
    
    PackedByteArray final_sig;
    final_sig.resize(65);
    uint8_t* ptr = final_sig.ptrw();
    
    memcpy(ptr, sig, 64);
    ptr[64] = pby; 

    return final_sig;
}

String W3Crypto::get_address_from_pubkey(const PackedByteArray& p_pub_key) {
    PackedByteArray to_hash;
    
    // 1. Если ключ сжатый (33 байта), распаковываем его
    if (p_pub_key.size() == 33) {
        uint8_t uncompressed[65];
        const ecdsa_curve *curve = &secp256k1;
        
        if (ecdsa_uncompress_pubkey(curve, p_pub_key.ptr(), uncompressed) == 0) {
            ERR_PRINT("W3Crypto: Failed to uncompress public key.");
            return "";
        }
        
        // Берем X и Y (пропускаем префикс 0x04)
        PackedByteArray temp;
        temp.resize(64);
        memcpy(temp.ptrw(), uncompressed + 1, 64);
        to_hash = temp;
        
        memzero(uncompressed, 65);
        
    } else if (p_pub_key.size() == 65) {
        to_hash = p_pub_key.slice(1);
    } else if (p_pub_key.size() == 64) {
        to_hash = p_pub_key;
    } else {
        ERR_PRINT("W3Crypto: Invalid public key size.");
        return "";
    }
    
    PackedByteArray hash = W3Keccak::hash(to_hash);
    PackedByteArray address_bytes = hash.slice(12);
    
    return HexUtils::bytes_to_hex(address_bytes, true);
}

PackedByteArray W3Crypto::pbkdf2(const String& p_password, const PackedByteArray& p_salt, int p_iterations, int p_key_length) {
    // 1. Защита от безумных аллокаций
    if (p_key_length <= 0 || p_key_length > 1024) p_key_length = 32;

    PackedByteArray result;
    result.resize(p_key_length);
    
    // 2. Получаем пароль как UTF-8
    CharString pass_cs = p_password.utf8();
    
    pbkdf2_hmac_sha256(
        (const uint8_t*)pass_cs.get_data(), (int)pass_cs.length(),
        p_salt.ptr(), (int)p_salt.size(),
        (uint32_t)p_iterations,
        result.ptrw(), (int)p_key_length
    );
    
    // 3. ЭКСПЕРТНЫЙ УРОВЕНЬ: Затираем временный буфер пароля в памяти сразу после использования
    // pass_cs.get_data() возвращает указатель на внутренний буфер, который мы можем обнулить
    if (pass_cs.length() > 0) {
        memzero((void*)pass_cs.get_data(), pass_cs.length());
    }
    
    return result;
}

PackedByteArray W3Crypto::aes_ctr_encrypt(const PackedByteArray& p_data, const PackedByteArray& p_key, const PackedByteArray& p_iv) {
    if (p_key.size() != 32) {
        ERR_PRINT("W3Crypto: AES-256 requires 32 bytes key.");
        return PackedByteArray();
    }
    if (p_iv.size() != 16) {
        ERR_PRINT("W3Crypto: IV must be 16 bytes.");
        return PackedByteArray();
    }

    PackedByteArray result;
    result.resize(p_data.size());

    aes_encrypt_ctx cx;
    if (aes_encrypt_key256((const unsigned char*)p_key.ptr(), &cx) != 0) {
        ERR_PRINT("W3Crypto: aes_encrypt_key256 failed.");
        return PackedByteArray();
    }

    uint8_t iv_buffer[16];
    memcpy(iv_buffer, p_iv.ptr(), 16);

    aes_ctr_crypt(
        (const unsigned char*)p_data.ptr(), 
        (unsigned char*)result.ptrw(), 
        (int)p_data.size(), 
        (unsigned char*)iv_buffer, 
        aes_ctr_cbuf_inc, 
        &cx
    );

    // Очистка конфиденциальных данных со стека (уже было, это хорошо)
    memzero(&cx, sizeof(cx));
    memzero(iv_buffer, 16);

    return result;
}

PackedByteArray W3Crypto::aes_ctr_decrypt(const PackedByteArray& p_data, const PackedByteArray& p_key, const PackedByteArray& p_iv) {
    // В CTR режиме шифрование и расшифровка симметричны
    return aes_ctr_encrypt(p_data, p_key, p_iv);
}

PackedByteArray W3Crypto::argon2id(const String& p_password, const PackedByteArray& p_salt, int p_iterations, int p_memory, int p_parallelism, int p_key_length) {
    // 1. Валидация
    if (p_key_length < 4 || p_key_length > 1024) {
        ERR_PRINT("W3Crypto: Invalid key length for Argon2id (min 4, max 1024 bytes)");
        return PackedByteArray();
    }
    if (p_key_length <= 0 || p_key_length > 1024) {
        ERR_PRINT("W3Crypto: Invalid key length for Argon2id");
        return PackedByteArray();
    }
    if (p_salt.size() < 8) {
        ERR_PRINT("W3Crypto: Salt too short for Argon2id (min 8 bytes)");
        return PackedByteArray();
    }

    // 2. Подготовка буферов
    PackedByteArray result;
    result.resize(p_key_length);
    
    CharString pass_cs = p_password.utf8();
    
    // 3. Вызов библиотеки (используем low-level hash_raw, чтобы получить байты, а не encoded string)
    int res = argon2id_hash_raw(
        (uint32_t)p_iterations,
        (uint32_t)p_memory,
        (uint32_t)p_parallelism,
        pass_cs.get_data(),
        pass_cs.length(),
        p_salt.ptr(),
        p_salt.size(),
        result.ptrw(),
        (size_t)p_key_length
    );

    // 4. Очистка пароля из памяти (Security best practice)
    if (pass_cs.length() > 0) {
        memzero((void*)pass_cs.get_data(), pass_cs.length());
    }

    if (res != ARGON2_OK) {
        ERR_PRINT("W3Crypto: Argon2id failed with error code: " + String::num(res));
        // Возвращаем пустой массив в случае ошибки
        return PackedByteArray();
    }

    return result;
}

Ref<Image> W3Crypto::generate_qr_code(const PackedByteArray& p_data, int p_scale) {
    // 1. Подготавливаем данные (Hex-строка ключа внутри C++)
    String hex = HexUtils::bytes_to_hex(p_data, true);
    CharString hex_cs = hex.utf8();
    
    // 2. Генерируем QR-код
    uint8_t qrcode[qrcodegen_BUFFER_LEN_MAX];
    uint8_t tempBuffer[qrcodegen_BUFFER_LEN_MAX];
    
    bool ok = qrcodegen_encodeText(hex_cs.get_data(), tempBuffer, qrcode, 
                                   qrcodegen_Ecc_LOW, qrcodegen_VERSION_MIN, 
                                   qrcodegen_VERSION_MAX, qrcodegen_Mask_AUTO, true);

    // СРАЗУ затираем hex-строку в памяти C++
    memzero((void*)hex_cs.get_data(), hex_cs.length());

    if (!ok) return Ref<Image>();

    // 3. Создаем Image
    int size = qrcodegen_getSize(qrcode);
    int img_size = size * p_scale;
    
    Ref<Image> img = Image::create(img_size, img_size, false, Image::FORMAT_L8);
    
    // Рисуем QR-код
    for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
            bool color = qrcodegen_getModule(qrcode, x, y);
            uint8_t raw_color = color ? 0 : 255; // Черный на белом
            
            // Масштабируем пиксели
            for (int sy = 0; sy < p_scale; sy++) {
                for (int sx = 0; sx < p_scale; sx++) {
                    img->set_pixel(x * p_scale + sx, y * p_scale + sy, Color(raw_color/255.0, raw_color/255.0, raw_color/255.0));
                }
            }
        }
    }

    return img;
}

PackedByteArray W3Crypto::get_eip712_forward_request_hash(const Dictionary& p_domain, const Dictionary& p_message) {
    // 1. TYPEHASH константы
    const char* DOMAIN_TYPEHASH = "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";
    const char* REQUEST_TYPEHASH = "ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,uint48 deadline,bytes data)";

    // 2. Вычисляем Domain Separator
    PackedByteArray domain_data;
    domain_data.append_array(W3Keccak::hash(String(DOMAIN_TYPEHASH).to_utf8_buffer()));
    domain_data.append_array(hash_eip712_data(p_domain.get("name", "")));
    domain_data.append_array(hash_eip712_data(p_domain.get("version", "1")));
    domain_data.append_array(pack_uint256_word(p_domain.get("chainId", 1)));
    domain_data.append_array(pack_address_word(p_domain.get("verifyingContract", "")));
    
    PackedByteArray domain_separator = W3Keccak::hash(domain_data);

    // 3. Вычисляем Struct Hash (ForwardRequest)
    PackedByteArray struct_data;
    struct_data.append_array(W3Keccak::hash(String(REQUEST_TYPEHASH).to_utf8_buffer())); // 1
    struct_data.append_array(pack_address_word(p_message.get("from", "")));             // 2
    struct_data.append_array(pack_address_word(p_message.get("to", "")));               // 3
    struct_data.append_array(pack_uint256_word(p_message.get("value", 0)));             // 4
    struct_data.append_array(pack_uint256_word(p_message.get("gas", 0)));               // 5
    struct_data.append_array(pack_uint256_word(p_message.get("nonce", 0)));             // 6
    struct_data.append_array(pack_uint256_word(p_message.get("deadline", 0)));          // 7
    struct_data.append_array(hash_eip712_data(p_message.get("data", PackedByteArray()))); // 8 (bytes)

    PackedByteArray struct_hash = W3Keccak::hash(struct_data);

    // 4. Финальный хеш: keccak256("\x19\x01" + domainSeparator + structHash)
    PackedByteArray final_data;
    final_data.resize(2 + 32 + 32);
    uint8_t* ptr = final_data.ptrw();
    ptr[0] = 0x19;
    ptr[1] = 0x01;
    memcpy(ptr + 2, domain_separator.ptr(), 32);
    memcpy(ptr + 2 + 32, struct_hash.ptr(), 32);

    return W3Keccak::hash(final_data);
}
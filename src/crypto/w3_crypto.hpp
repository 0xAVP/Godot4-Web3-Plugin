#ifndef W3_CRYPTO_HPP
#define W3_CRYPTO_HPP

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/classes/image.hpp>

namespace godot {

class W3Crypto : public RefCounted {
    GDCLASS(W3Crypto, RefCounted)

protected:
    static void _bind_methods();

public:
    W3Crypto();
    ~W3Crypto();
    static PackedByteArray get_eip712_forward_request_hash(const Dictionary& p_domain, const Dictionary& p_message);
    static Ref<Image> generate_qr_code(const PackedByteArray& p_data, int p_scale = 10);
    static PackedByteArray generate_private_key();
    static PackedByteArray get_public_key(const PackedByteArray& p_priv_key, bool p_compressed = false);
    static PackedByteArray sign(const PackedByteArray& p_hash, const PackedByteArray& p_priv_key);
    static String get_address_from_pubkey(const PackedByteArray& p_pub_key);
    static String recover_address(const PackedByteArray& p_hash, const PackedByteArray& p_sig);
    static void secure_wipe(PackedByteArray p_data);
    // --- KEYSTORE METHODS ---
    static PackedByteArray pbkdf2(const String& p_password, const PackedByteArray& p_salt, int p_iterations, int p_key_length);
    static PackedByteArray aes_ctr_encrypt(const PackedByteArray& p_data, const PackedByteArray& p_key, const PackedByteArray& p_iv);
    static PackedByteArray aes_ctr_decrypt(const PackedByteArray& p_data, const PackedByteArray& p_key, const PackedByteArray& p_iv);
    // Constant-time comparison for sensitive data (hashes, keys)
    static bool secure_compare(const PackedByteArray& a, const PackedByteArray& b);
    // --- ARGON2 ---
    /**
     * @param p_password Пароль
     * @param p_salt Соль (минимум 8 байт, рекомендуется 16)
     * @param p_iterations Количество проходов (Time cost)
     * @param p_memory Память в Килобайтах (Memory cost, например 65536 = 64MB)
     * @param p_parallelism Количество потоков (Parallelism)
     * @param p_key_length Длина выходного ключа (обычно 32 байта)
     */
    static PackedByteArray argon2id(const String& p_password, const PackedByteArray& p_salt, int p_iterations, int p_memory, int p_parallelism, int p_key_length);
    
};

}

#endif
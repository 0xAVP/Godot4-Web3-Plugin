#include "W3EIP712.hpp"
#include <cstring>
#include <algorithm>

extern "C" {
#include "../vendor/trezor-crypto/sha3.h"
#include "../vendor/trezor-crypto/memzero.h"
}

namespace w3 {

// --- КРИПТОГРАФИЧЕСКИЕ ПРИМИТИВЫ ---

EIP712::Hash32 EIP712::keccak256(const uint8_t* data, size_t len) {
    Hash32 out;
    ::keccak_256(data, len, out.data());
    return out;
}

EIP712::Hash32 EIP712::hash_string(const std::string& str) {
    return keccak256(reinterpret_cast<const uint8_t*>(str.c_str()), str.length());
}

EIP712::Hash32 EIP712::hash_bytes(const std::vector<uint8_t>& data) {
    return keccak256(data.data(), data.size());
}

// --- УПАКОВКА (ABI ENCODING) ---

void EIP712::pack_uint256(std::vector<uint8_t>& buffer, uint256_t val) {
    uint8_t word[32] = {0};
    uint256_t temp = val;
    for (int i = 31; i >= 0; --i) {
        word[i] = static_cast<uint8_t>(temp & 0xFF);
        temp >>= 8;
    }
    buffer.insert(buffer.end(), std::begin(word), std::end(word));
}

void EIP712::pack_address(std::vector<uint8_t>& buffer, const std::string& address) {
    // Внутренняя логика конвертации hex -> bytes
    // Адрес в EIP-712 дополняется до 32 байт нулями слева
    uint8_t word[32] = {0};
    
    std::string clean_addr = address;
    if (clean_addr.compare(0, 2, "0x") == 0 || clean_addr.compare(0, 2, "0X") == 0) {
        clean_addr = clean_addr.substr(2);
    }
    
    // Преобразование Hex в байты (упрощено для ядра)
    for (size_t i = 0; i < 20 && (i * 2 + 1) < clean_addr.length(); ++i) {
        std::string byteString = clean_addr.substr(i * 2, 2);
        word[12 + i] = static_cast<uint8_t>(strtol(byteString.c_str(), nullptr, 16));
    }
    
    buffer.insert(buffer.end(), std::begin(word), std::end(word));
}

void EIP712::pack_bytes32(std::vector<uint8_t>& buffer, const Hash32& hash) {
    buffer.insert(buffer.end(), hash.begin(), hash.end());
}

// --- EIP-712 ЛОГИКА ---

EIP712::Hash32 EIP712::hash_domain(const Domain& domain) {
    std::vector<uint8_t> buffer;
    buffer.reserve(32 * 5); // Оптимизация аллокации (TypeHash + 4 поля)

    // 1. TypeHash
    pack_bytes32(buffer, hash_string(DOMAIN_TYPEHASH));
    
    // 2. name (hashed)
    pack_bytes32(buffer, hash_string(domain.name));
    
    // 3. version (hashed)
    pack_bytes32(buffer, hash_string(domain.version));
    
    // 4. chainId
    pack_uint256(buffer, uint256_t(domain.chainId));
    
    // 5. verifyingContract (address)
    pack_address(buffer, domain.verifyingContract);

    return keccak256(buffer.data(), buffer.size());
}

EIP712::Hash32 EIP712::hash_forward_request(const ForwardRequest& req) {
    std::vector<uint8_t> buffer;
    buffer.reserve(32 * 8); // TypeHash + 7 полей

    pack_bytes32(buffer, hash_string(FORWARD_REQUEST_TYPEHASH)); // 1
    pack_address(buffer, req.from);                               // 2
    pack_address(buffer, req.to);                                 // 3
    pack_uint256(buffer, req.value);                              // 4
    pack_uint256(buffer, uint256_t(req.gas));                     // 5
    pack_uint256(buffer, req.nonce);                              // 6
    pack_uint256(buffer, uint256_t(req.deadline));                // 7
    pack_bytes32(buffer, hash_bytes(req.data));                   // 8 (bytes хешируются!)

    return keccak256(buffer.data(), buffer.size());
}

EIP712::Hash32 EIP712::calculate_final_hash(const Domain& domain, const ForwardRequest& req) {
    Hash32 domainSeparator = hash_domain(domain);
    Hash32 structHash = hash_forward_request(req);

    // Финальная сборка: \x19\x01 + domainSeparator + structHash
    std::vector<uint8_t> final_buffer;
    final_buffer.reserve(2 + 32 + 32);
    
    final_buffer.push_back(0x19);
    final_buffer.push_back(0x01);
    final_buffer.insert(final_buffer.end(), domainSeparator.begin(), domainSeparator.end());
    final_buffer.insert(final_buffer.end(), structHash.begin(), structHash.end());

    Hash32 result = keccak256(final_buffer.data(), final_buffer.size());
    
    // Очистка чувствительных данных из вектора (хотя здесь только хеши)
    ::memzero(final_buffer.data(), final_buffer.size());
    
    return result;
}

} // namespace w3
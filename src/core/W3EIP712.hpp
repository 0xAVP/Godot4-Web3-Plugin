#ifndef W3_EIP712_CORE_HPP
#define W3_EIP712_CORE_HPP

#include <vector>
#include <string>
#include <cstdint>
#include <array>
#include "../vendor/uint256_t/uint256_t.h"

namespace w3 {

/**
 * @brief Класс для вычисления хешей согласно EIP-712 (Typed Structured Data Hashing).
 * Реализация сфокусирована на ForwardRequest, но архитектурно готова к расширению.
 */
class EIP712 {
public:
    using Hash32 = std::array<uint8_t, 32>;

    struct Domain {
        std::string name;
        std::string version;
        uint64_t chainId;
        std::string verifyingContract; // Hex-string address
    };

    struct ForwardRequest {
        std::string from;
        std::string to;
        uint256_t value;
        uint64_t gas;
        uint256_t nonce;
        uint64_t deadline; // uint48 в солидности
        std::vector<uint8_t> data;
    };

    /**
     * @brief Вычисляет финальный хеш сообщения для подписи:
     * keccak256("\x19\x01" | domainSeparator | hashStruct(message))
     */
    static Hash32 calculate_final_hash(const Domain& domain, const ForwardRequest& req);

    /**
     * @brief Вычисляет Domain Separator
     */
    static Hash32 hash_domain(const Domain& domain);

    /**
     * @brief Вычисляет hashStruct(ForwardRequest)
     */
    static Hash32 hash_forward_request(const ForwardRequest& req);

private:
    // Константы TypeHash (вычислены заранее для оптимизации)
    static constexpr const char* DOMAIN_TYPEHASH = 
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";
    
    static constexpr const char* FORWARD_REQUEST_TYPEHASH = 
        "ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,uint48 deadline,bytes data)";

    // Вспомогательные методы упаковки
    static void pack_uint256(std::vector<uint8_t>& buffer, uint256_t val);
    static void pack_address(std::vector<uint8_t>& buffer, const std::string& address);
    static void pack_bytes32(std::vector<uint8_t>& buffer, const Hash32& hash);
    static Hash32 keccak256(const uint8_t* data, size_t len);
    static Hash32 hash_string(const std::string& str);
    static Hash32 hash_bytes(const std::vector<uint8_t>& data);
};

} // namespace w3

#endif
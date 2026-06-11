#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "sha2.h" 

// --- OS SPECIFIC HEADERS ---
#if defined(_WIN32) || defined(_WIN64)
    #include <windows.h>
    #include <bcrypt.h>
    #ifndef BCRYPT_USE_SYSTEM_PREFERRED_RNG
    #define BCRYPT_USE_SYSTEM_PREFERRED_RNG 0x00000002
    #endif
#elif defined(__APPLE__) || defined(__ANDROID__) || defined(__OpenBSD__)
    // macOS, iOS, Android, OpenBSD имеют встроенный arc4random_buf
    #include <stdlib.h> 
#elif defined(__linux__) || defined(__gnu_linux__)
    // Linux: используем getrandom (доступен с Kernel 3.17, glibc 2.25)
    #include <sys/random.h>
    #include <errno.h>
    #include <unistd.h>
#else
    // Generic POSIX (FreeBSD, NetBSD и т.д., если нет arc4random)
    #include <stdio.h>
#endif

// --- 1. Реализация __builtin_clz для Windows (MSVC) ---
#ifdef _MSC_VER
#include <intrin.h>
int __builtin_clz(uint32_t x) {
    unsigned long r = 0;
    if (_BitScanReverse(&r, x)) {
        return 31 - r;
    }
    return 32;
}
#endif

// --- 2. CSPRNG (Cryptographically Secure Pseudo-Random Number Generator) ---

// Функция паники при отказе RNG
static void rng_panic() {
    abort();
}

void random_buffer(uint8_t *buf, size_t len) {
#if defined(_WIN32) || defined(_WIN64)
    // [WINDOWS]
    NTSTATUS status = BCryptGenRandom(NULL, buf, (ULONG)len, BCRYPT_USE_SYSTEM_PREFERRED_RNG);
    if (!BCRYPT_SUCCESS(status)) {
        rng_panic();
    }
#elif defined(__APPLE__) || defined(__ANDROID__) || defined(__OpenBSD__)
    // [APPLE & ANDROID & OpenBSD] - Native API
    // Не требует открытия файлов, никогда не падает, работает очень быстро.
    arc4random_buf(buf, len);
#elif defined(__linux__) || defined(__gnu_linux__)
    // [LINUX] - getrandom syscall
    // Не использует файловые дескрипторы.
    while (len > 0) {
        ssize_t res = getrandom(buf, len, 0);
        if (res == -1) {
            if (errno == EINTR) {
                continue; // Прервано сигналом, пробуем снова
            }
            rng_panic(); // Фатальная ошибка RNG
        }
        buf += res;
        len -= res;
    }
#else
    // [GENERIC POSIX] - Fallback to /dev/urandom
    // Менее эффективно, но работает везде, где есть файловая система /dev
    FILE *f = fopen("/dev/urandom", "rb");
    if (!f) {
        rng_panic();
    }
    
    // Читаем в цикле, так как fread может вернуть меньше байт
    size_t remaining = len;
    while (remaining > 0) {
        size_t read_len = fread(buf, 1, remaining, f);
        if (read_len == 0) {
             fclose(f);
             rng_panic(); // Ошибка чтения или EOF (чего быть не должно у urandom)
        }
        buf += read_len;
        remaining -= read_len;
    }
    fclose(f);
#endif
}

uint32_t random32(void) {
    uint32_t val;
    random_buffer((uint8_t*)&val, sizeof(val));
    return val;
}

// --- 3. Заглушки для Bitcoin (не используются в ETH) ---
int base58_encode_check(const uint8_t *data, int len, void *hasher, char *str, int str_len) { return 0; }
int base58_decode_check(const char *str, void *hasher, uint8_t *data, int data_max_len) { return 0; }

int address_prefix_bytes_len(uint32_t address_type) { return 0; }
void address_write_prefix_bytes(uint32_t address_type, uint8_t *out) {}
int address_check_prefix(const uint8_t *addr, uint32_t address_type) { return 0; }

// --- 4. Безопасная реализация hasher_Raw ---

typedef struct {
	void (*init)(void *ctx);
	void (*update)(void *ctx, const void *data, size_t len);
	void (*final)(void *ctx, uint8_t *hash);
	size_t ctx_len;
} StubHasherType;

// Прокси-функции
void stub_hasher_Init(void *ctx) {
    sha256_Init((SHA256_CTX*)ctx);
}

void stub_hasher_Update(void *ctx, const void *data, size_t len) {
    sha256_Update((SHA256_CTX*)ctx, (const uint8_t*)data, len);
}

void stub_hasher_Final(void *ctx, uint8_t *hash) {
    sha256_Final((SHA256_CTX*)ctx, hash);
}

// Теперь hasher_Raw указывает на рабочие функции SHA256
const StubHasherType hasher_Raw = {
    stub_hasher_Init,
    stub_hasher_Update,
    stub_hasher_Final,
    sizeof(SHA256_CTX) // Обязательно указываем реальный размер контекста!
};
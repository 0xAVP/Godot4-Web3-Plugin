#!/usr/bin/env python
import os
import sys

env = Environment(ENV=os.environ)

# Получаем платформу из аргументов командной строки
platform = ARGUMENTS.get("platform", "")

godot_cpp_path = "godot-cpp"

# Настройки для Windows (MSVC)
if platform == "windows":
    env.Append(CPPDEFINES=['ssize_t=long'])
    env.Append(CPPDEFINES=['_CRT_SECURE_NO_WARNINGS'])
    env.Append(LIBS=["bcrypt"]) 

env.Append(CPPPATH=[
    "src",
    "src/vendor/uint256_t",
    "src/vendor/uint256_t/uint128_t",
    "src/vendor/trezor-crypto",
    "src/vendor/phc-winner-argon2/include",
    "src/vendor/phc-winner-argon2/src",
    "godot-cpp/gen/include/classes",
    "src/vendor/qrcodegen",
    godot_cpp_path + "/include",
    godot_cpp_path + "/gen/include" 
])

# Подключаем настройки из godot-cpp
env = SConscript(godot_cpp_path + "/SConstruct", exports="env")

library_name = "godot_web3_windows_template_debug_x86_64"
output_path = "demo/addons/godot_web3/bin/"

if not os.path.exists(output_path):
    os.makedirs(output_path)

# --- СБОРКА ИСТОЧНИКОВ ---
sources = []

# 1. Core & Utils (только .cpp)
sources.extend(Glob("src/*.cpp"))
sources.extend(Glob("src/core/*.cpp"))
sources.extend(Glob("src/utils/*.cpp"))

# 2. Crypto (и .cpp, и .c для заглушек)
sources.extend(Glob("src/crypto/*.cpp"))
sources.extend(Glob("src/crypto/*.c"))

# 3. Vendor: uint256_t
sources.extend(Glob("src/vendor/uint256_t/*.cpp"))
sources.extend(Glob("src/vendor/uint256_t/uint128_t/*.cpp"))

# 4. Vendor: Trezor Crypto (избирательно)
trezor_files = [
    "bignum.c",
    "ecdsa.c",
    "hmac.c",
    "hmac_drbg.c",
    "memzero.c",
    "rfc6979.c",
    "secp256k1.c",
    "sha2.c",
    "sha3.c",
    "pbkdf2.c", 
    "aes/aes_modes.c",
    "aes/aescrypt.c",  
    "aes/aeskey.c",   
    "aes/aestab.c",
]

# 4. Vendor: phc-winner-argon2
argon2_base = "src/vendor/phc-winner-argon2/src/"
argon2_files = [
    "argon2.c",
    "core.c",
    "encoding.c",
    "thread.c",
    "ref.c",
    "blake2/blake2b.c"
]
for f in argon2_files:
    sources.append(argon2_base + f)

for f in trezor_files:
    sources.append("src/vendor/trezor-crypto/" + f)

sources.append("src/vendor/qrcodegen/qrcodegen.c")

# Удаляем дубликаты из списка sources (на всякий случай)
sources = list(set(sources))

library = env.SharedLibrary(
    target=output_path + library_name, 
    source=sources
)

Default(library)
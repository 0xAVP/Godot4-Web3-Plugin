# Godot Web3 GDExtension (Godot 4.6+)

**Project Status:** Prototype / Architectural Showcase (development temporarily paused)

This project is a showcase of Web3 (Ethereum / EVM) integration into the **Godot 4** game engine, built at the intersection of high-performance C++ (GDExtension core) and high-level GDScript. 

The project was designed as a flexible prototype for secure in-game blockchain interaction. A fully functional version with pre-compiled binaries is already located in the `demo/` folder, allowing you to run the project in the Godot editor immediately after cloning.

---

## 🛠️ Technical Capabilities & Architecture (Codebase Analysis)

This repository demonstrates advanced C++ game-engine integrations, cryptographic engineering, and resilient network design. Below is a detailed technical analysis of the systems implemented in this plugin:

### 1. High-Performance Core & Cryptography (C++)
* **Unsigned 256-bit Arithmetic (`W3BigInt`):** Implements a highly optimized, custom GDExtension wrapper around a 256-bit unsigned integer core (`uint256_t`). It supports native EVM wrap-around math semantics, fast direct bit-shifting byte extraction (`get_bytes`), signed and unsigned comparison checks (`gt_signed`/`lt_signed`), and custom decimal/hex boundary validations to prevent parsing-stage overflows.
* **EVM Binary Encoding/Decoding (`W3ABI` & `W3RLP`):**
  * **Solidity ABI Indexing & Dynamic Decoding:** Employs a recursive ABI decoding engine capable of traversing complex dynamic layouts (e.g., nested tuples, dynamic byte arrays, arrays of structs `tuple[][]`). It decodes raw EVM binary call returns directly to high-level Godot Variant arrays.
  * **EVM Revert & Panic Extraction:** Features a built-in transaction failure analyzer capable of intercepting and decoding EVM revert signatures (`Error(string)`) and Solidity `Panic(uint256)` codes (e.g., overflow, zero division, index out-of-bounds), converting raw hexadecimal trace errors into human-readable developer logs.
  * **RLP Serialization:** Complete Recursive Length Prefix (RLP) serialization for bytes, lists, and Ethereum integers (which explicitly represent `0` as an empty byte array/`0x80`).
* **Cryptographic Strength (`W3Crypto`):**
  * Fully integrates `secp256k1` ECDSA signature generation (`ecdsa_sign_digest`) and address recovery from signatures (`ecdsa_recover_pub_from_sig`) mapped via Keccak-256.
  * Constant-time safe byte comparisons (`secure_compare`) to shield cryptographic assertions from timing side-channel attacks (hashing varying lengths internally to enforce equal comparison times).
  * Robust Key Derivation Function (KDF): Implements memory-hard Argon2id (via `phc-winner-argon2`) alongside PBKDF2 HMAC-SHA256, allowing configurable thread-level parallelism, memory footprints, and time-cost iterations.
  * Symmetric Encryption: Native AES-256-CTR encryption/decryption roundtrips.
  * Offline QR Code Generation: Generates standard QR-Code matrix patterns directly from byte secrets in C++, delivering them seamlessly back into Godot as a lightweight `Image` asset for instant UI rendering.

### 2. Secure-in-Memory Wallet Design (C++ & GDScript)
* **XOR-Masked Memory Protection (`EthBaseWallet`):** Designed with game-client memory security in mind. Sensitive private keys are never stored in plain text. Instead, they are obfuscated using a session-specific, randomly generated 32-byte mask (`_masked_key = key ^ _session_mask`). The plain key is temporarily reconstructed in memory only during the active signing window and is immediately scrubbed.
* **Proactive Zeroing (`secure_wipe`):** Leverages a dedicated C++ wrapper that forces an in-place `memzero` on all unmasked keys, passwords, and KDF buffers directly after usage. This bypasses typical compiler optimizations to prevent residual cryptographic secrets from lingering in the system memory heap.
* **Flexible Cryptographic Identities:**
  * **EthBrainWallet:** Derives deterministic, salted cryptographic keys via Argon2id from user-supplied passwords combined with an application-specific secret salt.
  * **EthSimpleWallet:** Provides memory-only random guest wallets initialized instantly via CSPRNG.

### 3. Resilient Network & Subscription Transport (GDScript)
* **Unified Provider Interface (`EthClient` & `EthNetworkManager`):**
  * **Multi-Node Failover & Automated Rotation:** Manages a pool of RPC endpoints. Outgoing requests are monitored by a dedicated `EthResponseAnalyzer`. Any infrastructure errors (rate limits, out-of-sync nodes, connection drops) automatically trigger failover rotation, routing the task through the next healthy node in the list.
  * **Concurrency Throttle:** Features a task semaphore limiting concurrent outgoing asynchronous JSON-RPC requests (`max_concurrency`) to protect games from socket flooding or API provider limits.
* **Low-Overhead HTTP Polling:** Resolves the issue of high Compute Unit (CU) consumption on HTTP-only networks. It consolidates multiple active polling subscriptions (`newHeads`, `logs`) into a single master loop. It makes cheap, lightweight `eth_blockNumber` calls to monitor state, only querying full block details or log-events when the chain head actually advances.
* **Gap-Filling Event Recovery (`EthSubscriptionService`):** Protects WebSocket-based event systems from network drops. If a socket connection is interrupted, the service automatically initiates reconnection, issues a resubscription, checks the last consumed block number, and requests a historical backfill (`eth_getLogs`) to catch up on any log-events missed during downtime.

### 4. Gas Management, Nonces, and Gasless Relay (GDScript)
* **EthNonceManager (Race Condition Protection):** Manages a thread-safe, local nonce counter. It increments the nonce locally immediately after transaction assembly—before the asynchronous network push completes—guaranteeing that subsequent rapid transactions (e.g., rapid clicks or ticks) do not suffer from duplicate nonce transaction collision.
* **EthGasOracle (Adaptive Fee Tuning):** Fetches network base fees and priority fee multipliers dynamically for EIP-1559 or Legacy strategies. Supports adjustable gas buffers (percentage limits) to prevent transactions from failing due to out-of-gas reverts during sudden state changes.
* **EthRelayer (Gasless Transactions):** Out-of-the-box support for gasless game transactions. Integrates C++ structured data hashing to build EIP-712 signatures. Generates compliant `ForwardRequest` payloads to route transactions through a custom Forwarder contract, allowing players to play without paying gas.

---

## 📂 Project Structure

* `/src` — C++ source code (GDExtension core: transactions, ABI, RLP, cryptography).
* `/src/vendor` — Lightweight third-party C/C++ libraries (trezor-crypto, Argon2id, uint256_t, qrcodegen).
* `/demo` — A working Godot project containing GDScript nodes (`EthClient`, `EthAccount`, `EthContract`, `EthWallet`, `EthRelayer`), unit tests, and **pre-compiled binaries** in the `demo/addons/godot_web3/bin/` folder.

---

## 🎮 How to Run the Demo

Since the pre-compiled binaries are already included in the `demo/` folder, you do not need to compile the C++ codebase yourself (although the source code is fully open for review):

1. **Clone the repository along with the `godot-cpp` submodule:**
   ```bash
   git clone --recursive https://github.com/0xAVP/Godot4-Web3-Plugin.git
   ```
2. **Open the `demo` folder in the Godot 4.6+ editor.**
3. Run the test scene to verify the functionality of all modules.

---

## Used Technologies and Third-Party Code
All third-party cryptography is located in the `src/vendor` folder and documented in accordance with their respective licenses in the THIRDPARTY_NOTICES.md
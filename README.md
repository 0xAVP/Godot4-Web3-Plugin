# Godot Web3 GDExtension (Godot 4.6+)

**Project Status:** Prototype / Architectural Showcase (development temporarily paused)

This project is a showcase of Web3 (Ethereum / EVM) integration into the **Godot 4** game engine, built at the intersection of high-performance C++ (GDExtension core) and high-level GDScript. 

The project was designed as a flexible prototype for secure in-game blockchain interaction. A fully functional version with pre-compiled binaries is already located in the `demo/` folder, allowing you to run the project in the Godot editor immediately after cloning.

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
# Child Playtime Limiter — Privacy-Preserving Parental Control ⏳🔒

A single-page dApp + Solidity smart contract that lets parents set secure weekly playtime rules for their children.  
All rules are stored **encrypted with Zama FHEVM**, so only the **final result** (can/cannot play now) is ever publicly revealed.

---

## ✨ Features
- 🔐 **Private rules** — both parent and child upload encrypted playtime masks (per day, per hour).
- 🧮 **On-chain FHE checks** — smart contract computes intersection of masks using Zama FHEVM (`and`, `gt`) without revealing raw schedules.
- 🖥️ **Polished frontend** — clean SPA with MetaMask connect, animated encryption effects, live status updates.
- 👩‍👩‍👧 **Roles** — owner sets parent/child roles, only they can update their rules.
- ⏱️ **Checks** — anyone can ask “Can play now?”; contract emits a public decryptable handle.

---

## 🛠️ Tech Stack
- Solidity ^0.8.24  
- Zama FHEVM (`@fhevm/solidity/lib/FHE.sol`)  
- Relayer SDK JS `@zama-fhe/relayer-sdk` (via CDN)  
- Ethers v6.15.0 (ESM)  
- Network: Sepolia testnet (`11155111`)  
- Relayer: `https://relayer.testnet.zama.cloud`  
- KMS (Sepolia): `0x1364cBBf2cDF5032C47d8226a6f6FBD2AFCDacAC`

---

## 🚀 Quick Start

### Prerequisites
- Node.js 18+  
- MetaMask (with Sepolia & test ETH)  
- Dev server with COOP/COEP headers (for WASM workers)

### Install & Deploy
```bash
npm install
npx hardhat compile

# Example: deploy to Sepolia
npx hardhat run scripts/deploy.ts --network sepolia
Take the deployed contract address and update CONTRACT_ADDRESS inside index.html.

Run Frontend
Serve with COOP/COEP headers:

bash
Копировать код
node server.js
# open http://localhost:3000
🧩 Usage
Connect MetaMask (switch to Sepolia if prompted).

Set roles (owner → parent & child addresses).

Parent/Child upload rules (select allowed hours for each day).

Check playtime: anyone can query “Can play now?”, frontend decrypts final ebool.

📁 Project Structure
bash
Копировать код
.
├─ index.html                    # Full SPA (frontend)
├─ contracts/
│  └─ ChildPlaytimeLimiter.sol   # FHEVM smart contract
├─ server.js                     # Dev server with COOP/COEP headers
├─ scripts/, tasks/, test/       # Optional Hardhat helpers
├─ package.json
└─ README.md
🔒 Security Notes
Rules stay encrypted; only final access flag is revealed.

This is a demo project — not audited for production/mainnet.

Do not commit private keys or mnemonics.

📚 References
Zama FHEVM Docs

Relayer SDK Guides

Solidity Guides for FHEVM

📄 License
MIT — see LICENSE.

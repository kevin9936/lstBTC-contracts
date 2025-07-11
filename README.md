# lstBTC Protocol

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.4-blue.svg)](https://soliditylang.org/)
[![Hardhat](https://img.shields.io/badge/Hardhat-2.25.0-orange.svg)](https://hardhat.org/)
[![TypeScript](https://img.shields.io/badge/TypeScript-4.7.3-blue.svg)](https://www.typescriptlang.org/)

> A trustless, decentralized protocol for bridging Bitcoin between Bitcoin and Core Chain securely

## 📖 Overview

lstBTC is a fully decentralized protocol that enables secure cross-chain Bitcoin transfers between Bitcoin and Core Chain. The protocol provides a trustless bridge mechanism with advanced security features, yield generation capabilities, and comprehensive whitelist management.

### 🎯 Key Features

- **Trustless Bridge**: Secure Bitcoin bridging without centralized intermediaries
- **Advanced Security**: Multi-layered security with role-based access control
- **Yield Generation**: Automatic yield accrual and distribution mechanisms
- **Whitelist Management**: Comprehensive address and script validation
- **Upgradeable Architecture**: UUPS upgradeable contracts for future improvements
- **Bitcoin Integration**: Native support for Bitcoin script types (P2PKH, P2SH, P2WPKH, P2WSH, P2TR)

## 🏗️ Architecture

### Core Components

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   LstBTC Token  │    │  Bridge Logic   │    │ Bitcoin TxStore │
│                 │    │                 │    │                 │
│ • ERC20 Token   │◄──►│ • Peg-in/out    │◄──►│ • SPV Proofs    │
│ • Mint/Burn     │    │ • Batch Process │    │ • Merkle Proofs │
│ • Blacklist     │    │ • Fee Mgmt      │    │ • Tx Validation │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │              ┌─────────────────┐              │
         │              │ Whitelist Reg.  │              │
         │              │                 │              │
         └──────────────►│ • Address Val.  │◄─────────────┘
                        │ • Script Types  │
                        │ • Group Mgmt    │
                        └─────────────────┘
```

### Contract Structure

- **`LstBTCLogic`**: ERC20 token with mint/burn capabilities and role management
- **`LstBTCBridgeLogic`**: Main bridge contract handling cross-chain transfers
- **`BitcoinTxStoreLogic`**: Bitcoin transaction verification and SPV proof validation
- **`WhitelistRegistryLogic`**: Address and script public key validation
- **`ConfigRegistryLogic`**: Fee configuration and protocol parameters
- **`NavProviderLogic`**: Exchange rate and NAV management

## 🚀 Quick Start

### Prerequisites

- Node.js >= 20.4.0
- Yarn package manager
- Git

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/coredao/lstbtc-contracts.git
   cd lstbtc-contracts
   ```

2. **Install dependencies**
   ```bash
   yarn install
   ```

3. **Set up environment variables**
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

### Development

1. **Compile contracts**
   ```bash
   yarn build
   ```

2. **Run tests**
   ```bash
   yarn test
   ```

## 🛠️ Deployment

### Supported Networks

- **Core Testnet2**: `core_testnet2`
- **Core Mainnet**: `core_mainnet`

### Deploy Contracts

1. **Set environment variables**
   ```bash
   export NETWORK=core_testnet2
   export NETNAME=core_testnet2
   export PRIVATE_KEY=your_private_key
   export ETHERSCAN_API_KEY=your_etherscan_api_key
   ```

2. **Deploy all contracts**
   ```bash
   yarn deploy
   ```

3. **Deploy specific contract**
   ```bash
   yarn deploy --tags WhitelistRegistryLogic
   ```

### Post-Deployment Configuration

1. **Initialize contract settings**
   ```bash
   yarn set_contracts
   ```

2. **Configure upgradeable contracts**
   ```bash
   TARGET=uups yarn upgrade_contracts
   ```

## 📋 Scripts

### Available Commands

| Command | Description |
|---------|-------------|
| `yarn build` | Compile contracts and generate TypeScript types |
| `yarn clean` | Clean build artifacts and cache |
| `yarn test` | Run all tests |
| `yarn deploy` | Deploy contracts to specified network |
| `yarn set_contracts` | Configure contract settings post-deployment |
| `yarn upgrade_contracts` | Upgrade contract implementations |
| `yarn lint` | Run commit linting |

## 🔧 Configuration

### Environment Variables

```bash
# Required
NETWORK=core_testnet2          # Target network
PRIVATE_KEY=your_private_key   # Deployment private key

# Optional
ETHERSCAN_API_KEY=your_key     # Contract verification
VERIFY_OPTION=1                # Enable verification
```

## 🧪 Testing

### Running Tests

```bash
# Run all tests
yarn test
```

> **Note**: After running tests, check the test results and ensure all tests pass before proceeding with deployment.

## 🔒 Security

### Security Features

- **Role-Based Access Control**: Granular permissions for different operations
- **Reentrancy Protection**: Guards against reentrancy attacks
- **Pausable Operations**: Emergency pause functionality
- **Upgradeable Contracts**: UUPS pattern for secure upgrades
- **Input Validation**: Comprehensive parameter validation
- **Whitelist Management**: Strict address and script validation

### Audit Status

- 🔄 Audit in progress

### Best Practices

- All contracts follow OpenZeppelin security patterns
- Comprehensive test coverage
- Formal verification ready
- Upgradeable architecture with proper access controls

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Development Workflow

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

### Code Style

- Follow Solidity style guide
- Use NatSpec documentation
- Maintain test coverage
- Follow TypeScript best practices

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🌐 Community

- **Website**: [https://coredao.org](https://coredao.org)
- **Twitter**: [@Coredao_Org](https://twitter.com/Coredao_Org)
- **Discord**: [Join our community](https://discord.com/invite/coredaoofficial)
- **Documentation**: [Protocol Documentation](https://docs.coredao.org)

## 🙏 Acknowledgments

- Built on [Core Chain](https://coredao.org)
- Uses [OpenZeppelin](https://openzeppelin.com) contracts
- Inspired by [TeleportDAO](https://github.com/TeleportDAO/teleswap-contracts)

---

**Disclaimer**: This software is provided "as is" without warranty of any kind. Use at your own risk.

// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

/**
 * @title ScriptTypesEnum
 * @dev Bitcoin script type enumeration for transaction validation
 *
 * This enum is based on the original implementation from TeleportDAO's btc-evm-bridge-contracts:
 * https://github.com/TeleportDAO/btc-evm-bridge-contracts
 *
 * Original License: MIT
 * Original Author: TeleportDAO
 *
 * Modifications made for lstBTC protocol:
 * - Updated to Solidity 0.8.4
 */

    enum ScriptTypes {
        P2PK, // 32 bytes
        P2PKH, // 20 bytes
        P2SH, // 20 bytes
        P2WPKH, // 20 bytes
        P2WSH, // 32 bytes
        P2TR // 32 bytes
    }

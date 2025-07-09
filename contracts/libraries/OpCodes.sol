// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

/**
 * @title OpCodes
 * @dev Bitcoin script operation codes library
 *
 * This library is based on the original implementation from RSK's btc-transaction-solidity-helper:
 * https://github.com/rsksmart/btc-transaction-solidity-helper
 *
 * Original License: MIT
 * Original Author: RSK Smart
 *
 * Modifications made for lstBTC protocol:
 * - Updated to Solidity 0.8.4
 */
library OpCodes {
    bytes1 public constant OP_DUP = 0x76;
    bytes1 public constant OP_HASH160 = 0xa9;
    bytes1 public constant OP_EQUALVERIFY = 0x88;
    bytes1 public constant OP_CHECKSIG = 0xac;
    bytes1 public constant OP_RETURN = 0x6a;
    bytes1 public constant OP_EQUAL = 0x87;

    bytes1 public constant OP_0 = 0x00;
    bytes1 public constant OP_1 = 0x51;
}

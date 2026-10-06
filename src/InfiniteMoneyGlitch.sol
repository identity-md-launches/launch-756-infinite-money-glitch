// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Infinite Money Glitch (IMB)
/// @notice Fixed-supply ERC-20 with 18 decimals and no administrative powers.
contract InfiniteMoneyGlitch is ERC20 {
    /// @notice One billion IMB expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev The direct deployer receives the entire supply, including when deployed by a factory.
    constructor() ERC20("Infinite Money Glitch", "IMB") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}

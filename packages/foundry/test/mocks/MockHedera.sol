// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { MockHederaTokenService } from "@lattice-test/mocks/hedera/MockHederaTokenService.sol";
import { HederaResponseCodes } from "@lattice/interfaces/external/hedera/HederaResponseCodes.sol";
import { HTS_SYSTEM_CONTRACT } from "@lattice/tokens/hedera/HTSAdapterLib.sol";

/// @notice Lattice's HTS mock plus the fungible-token `approve` (selector 0xe1f21c67) that SaucerSwap's router relies
///         on. Etch it over 0x167 after the base mock: it adds no state, so everything the base mock holds stays.
contract MockHederaTokenServiceWithApprove is MockHederaTokenService {
    /// @notice Sets the allowance the caller gives `spender` on `token`, replacing any earlier one, as HTS does.
    function approve(address token, address spender, uint256 amount) external returns (int64) {
        int64 forced = forcedCode[this.approve.selector];
        if (forced != 0) {
            delete forcedCode[this.approve.selector];
            return forced;
        }
        if (!tokenExists[token]) return HederaResponseCodes.INVALID_TOKEN_ID;
        allowances[token][msg.sender][spender] = amount;
        return HederaResponseCodes.SUCCESS;
    }
}

/// @notice An HTS token's facade with the ERC-20 reads Lattice's `MockHRC719Token` lacks. Etch it over a token the
///         mock created; it reads everything from the HTS mock at 0x167, so it needs no state of its own.
contract MockHtsTokenFacade {
    MockHederaTokenService internal constant HTS = MockHederaTokenService(payable(HTS_SYSTEM_CONTRACT));

    function associate() external returns (uint256) {
        return uint256(uint64(HTS.associateToken(msg.sender, address(this))));
    }

    function isAssociated() external view returns (bool) {
        return HTS.associated(msg.sender, address(this));
    }

    function balanceOf(address account) external view returns (uint256) {
        return uint256(uint64(HTS.balanceOf(address(this), account)));
    }

    function totalSupply() external view returns (uint256) {
        return uint256(uint64(HTS.totalSupply(address(this))));
    }
}

/// @notice Stand-in for the Exchange Rate system contract at 0x168. Etch it, then call `setRate`.
contract MockExchangeRate {
    uint256 public cents;
    uint256 public hbars;

    /// @notice `centEquivalent` US cents buy `hbarEquivalent` HBAR, as the network's exchange rate file says.
    function setRate(uint256 centEquivalent, uint256 hbarEquivalent) external {
        cents = centEquivalent;
        hbars = hbarEquivalent;
    }

    function tinycentsToTinybars(uint256 tinycents) external view returns (uint256) {
        return tinycents * hbars / cents;
    }

    function tinybarsToTinycents(uint256 tinybars) external view returns (uint256) {
        return tinybars * cents / hbars;
    }
}

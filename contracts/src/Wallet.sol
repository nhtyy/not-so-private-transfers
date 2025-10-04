// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library LibWallet {
    function makeCall(address wallet, address to, uint256 value, bytes memory data) internal {
        bytes memory _calldata = abi.encodePacked(abi.encode(to, value), data);

        (bool succ,) = wallet.call(_calldata);

        require(succ, "call failed.");
    }
}

contract Wallet {
    error NotDeployer();

    /// @dev The deployer contract for this wallet.
    address deployer;

    constructor() payable {
        // Note we store this in storage for now to keep the bytecode size as small as posible
        deployer = msg.sender;
    }

    /**
     * @dev Fallback function to handle arbitrary calls for the owner of the wallet.
     *
     * @dev Assume the arguments are encoded in the form abi.encodePacked(abi.encode(to) || abi.encode(value) || bytes data), where data
     * is the data to send to the address, not length prefixed.
     *
     * @dev This fallback function does not allow the wallet to accept native value after deployment.
     */
    fallback() external payable {
        // Immutables are not accesiable from within assembly ;(
        assembly {
            if iszero(eq(caller(), sload(deployer.slot))) {
                mstore(0, 0x8b906c97)
                revert(0, 0x04)
            }

            let inSize := sub(calldatasize(), 0x40)
            calldatacopy(0, 0x40, inSize)

            if iszero(call(gas(), calldataload(0), calldataload(0x20), 0, inSize, codesize(), 0x00)) {
                returndatacopy(0x00, 0x00, returndatasize())
                revert(0x00, returndatasize())
            }
        }
    }
}

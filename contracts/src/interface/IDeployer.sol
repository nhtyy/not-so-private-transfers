// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @dev Struct for the relay authentication.
struct RelayAuthentication {
    address owner;
    bytes32 salt;
    address to;
    uint256 value;
    bytes data;
}

interface IDeployer {
    /// @dev Error thrown when an authentication is already used.
    error AuthenticationAlreadyUsed();

    /// @dev Error thrown when a wallet is not deployed.
    error WalletNotDeployed();

    /// @dev Error thrown when an invalid signer is provided.
    error InvalidSigner(address signer, address owner);

    /// @dev Event emitted when a wallet is deployed.
    event Deployed(address indexed owner, bytes32 indexed salt, address indexed wallet);

    /// @notice Deploy a wallet.
    /// @param salt The salt of the wallet.
    /// @param to The address to call.
    /// @param value The value to send.
    /// @param data The data to send.
    function deploy(bytes32 salt, address to, uint256 value, bytes memory data) external returns (address);

    /// @notice Make a call to the wallet as the owner.
    /// @param salt The salt of the wallet.
    /// @param to The address to call.
    /// @param value The value to send.
    /// @param data The data to send.
    function ownerCall(bytes32 salt, address to, uint256 value, bytes memory data) external;

    /// @notice Deploy a wallet with a relayer covering the gas costs.
    /// @param relayAuthentication The relayer
    /// @param signature The signature of the relay authentication.
    function relayDeploy(RelayAuthentication calldata relayAuthentication, bytes memory signature)
        external
        returns (address);
}

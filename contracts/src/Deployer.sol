// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {LibWallet, Wallet} from "./Wallet.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {RelayAuthentication, IDeployer} from "./interface/IDeployer.sol";

contract Deployer is IDeployer {
    /// @dev Mapping of spent authentications.
    mapping(bytes32 signedAuthentication => bool) spentAuth;

    /// @dev `cast keccak "RelayAuthentication(address owner,bytes32 salt,address to,uint256 value,bytes data)"`
    bytes32 constant RELAY_AUTH_TYPEHASH = 0xbd55b7f7526a00c1ed7ef41c425970ddfb173696d7e3ef728d18ce0020f19c58;

    /// @dev `cast keccak "EIP712Domain(string name,uint256 chainId,address verifyingContract)"`
    bytes32 constant DOMAIN_TYPEHASH = 0x8cad95687ba82c2ce50e74f7b754645e5117c3a5bec8151c0726d5857980a866;

    /// @dev Domain separator for the relay authentication.
    bytes32 immutable DOMAIN_SEPARATOR;

    constructor() {
        DOMAIN_SEPARATOR =
            keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("RelayAuthentication"), block.chainid, address(this)));
    }

    /// @notice Deploy a wallet.
    /// @param salt The salt of the wallet.
    /// @param to The address to call.
    /// @param value The value to send.
    /// @param data The data to send.
    function deploy(bytes32 salt, address to, uint256 value, bytes memory data) public returns (address) {
        // Compute the salt for the wallet.
        //
        // note: We include the owner in the salt so that collisions are impossible for unique wallets.
        bytes32 actualSalt = computeSalt(salt, msg.sender);

        // Deploy the wallet.
        address wallet = address(new Wallet{salt: actualSalt}());

        // Make the call to the wallet.
        LibWallet.makeCall(wallet, to, value, data);

        emit Deployed(msg.sender, salt, wallet);

        return wallet;
    }

    /// @notice Deploy a wallet with a relayer covering the gas costs.
    /// @param relayAuthentication The relayer
    /// @param signature The signature of the relay authentication.
    function relayDeploy(RelayAuthentication calldata relayAuthentication, bytes memory signature)
        public
        returns (address)
    {
        // Compute the digest of the relay authentication.
        bytes32 digest = eip712Digest(relayAuthentication);
        if (spentAuth[digest]) {
            revert AuthenticationAlreadyUsed();
        }

        // Recover the owner from the signature, reverts if the signature is invalid.
        // We want to include the owner in the salt so that collisions are impossible for unique wallets.
        address signer = ECDSA.recover(digest, signature);
        if (signer != relayAuthentication.owner) {
            revert InvalidSigner(signer, relayAuthentication.owner);
        }

        // Mark the authentication as spent.
        spentAuth[digest] = true;

        // Compute the salt for the wallet.
        //
        // note: We include the owner in the salt so that collisions are impossible for unique wallets.
        bytes32 actualSalt = computeSalt(relayAuthentication.salt, relayAuthentication.owner);
        address wallet = address(new Wallet{salt: actualSalt}());

        // Make the call to the wallet.
        LibWallet.makeCall(wallet, relayAuthentication.to, relayAuthentication.value, relayAuthentication.data);

        emit Deployed(relayAuthentication.owner, relayAuthentication.salt, wallet);

        return wallet;
    }

    /// @notice Make a call to the wallet as the owner.
    /// @param salt The salt of the wallet.
    /// @param to The address to call.
    /// @param value The value to send.
    /// @param data The data to send.
    function ownerCall(bytes32 salt, address to, uint256 value, bytes memory data) public {
        address wallet = computeWalletAddress(salt, msg.sender);

        if (wallet.code.length == 0) {
            revert WalletNotDeployed();
        }

        // Make the call to the wallet.
        LibWallet.makeCall(wallet, to, value, data);
    }

    /// @notice Hash a RelayAuthentication struct (structHash).
    function eip712StructHash(RelayAuthentication calldata m) public pure returns (bytes32) {
        bytes memory encodeStruct = abi.encode(m.owner, m.salt, m.to, m.value, keccak256(m.data));

        return keccak256(abi.encodePacked(RELAY_AUTH_TYPEHASH, encodeStruct));
    }

    /// @notice Full EIP-712 digest given domainSeparator.
    function eip712Digest(RelayAuthentication calldata m) public view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, eip712StructHash(m)));
    }

    function computeSalt(bytes32 salt, address owner) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(salt, owner));
    }

    function computeWalletAddress(bytes32 salt, address owner) public view returns (address) {
        bytes32 actualSalt = computeSalt(salt, owner);

        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(this), actualSalt, keccak256(type(Wallet).creationCode))
                    )
                )
            )
        );
    }
}

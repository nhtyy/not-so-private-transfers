// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Deployer} from "src/Deployer.sol";
import {Wallet} from "src/Wallet.sol";
import {RelayAuthentication} from "src/interface/IDeployer.sol";

contract DeployerTest is Test {
    Deployer public deployer;

    function setUp() public {
        deployer = new Deployer();
    }

    function testExpectedAuthEip712Encoding() public view {
        bytes memory encoded =
            hex"0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb9226651c83b551ce782ac775ea888601b2115ed93e9492522ec86adb2a05263e73d8a000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb922660000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000000";
        RelayAuthentication memory decoded = abi.decode(encoded, (RelayAuthentication));

        bytes32 structHash = deployer.eip712StructHash(decoded);
        // Taken from the rust encode function.
        assertEq(structHash, bytes32(0xe3648031e38f3d7a46788e4e6da59b1f1d582300d491bc23ac98e2e242bcdb0a));
    }

    function testCanDeployWalletWithAuth() public {
        (address owner, uint256 pk) = makeAddrAndKey("owner_key");
        bytes32 salt = keccak256("salt");
        bytes32 actualSalt = keccak256(abi.encodePacked(salt, owner));

        address wallet = vm.computeCreate2Address(actualSalt, keccak256(type(Wallet).creationCode), address(deployer));
        // Deal 1 ether to the wallet.
        vm.deal(wallet, 1 ether);

        // Send 1 ether back to the owner from the wallet.
        RelayAuthentication memory auth =
            RelayAuthentication({owner: owner, salt: salt, to: owner, value: 1 ether, data: bytes("")});

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, deployer.eip712Digest(auth));

        bytes memory signature = abi.encodePacked(r, s, v);

        deployer.relayDeploy(auth, signature);

        assertEq(address(wallet).balance, 0);
        assertEq(owner.balance, 1 ether);
    }
}

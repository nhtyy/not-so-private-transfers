// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Wallet, LibWallet} from "src/Wallet.sol";
import {Deployer} from "src/Deployer.sol";
import {IDeployer} from "src/interface/IDeployer.sol";

contract CallTarget {
    bytes32 public value = bytes32(0);

    function setState(bytes32 _value) external payable {
        value = _value;
    }

    receive() external payable {}
}

contract CounterTest is Test {
    CallTarget public callTarget;
    Deployer public deployer;

    function setUp() public {
        callTarget = new CallTarget();
        deployer = new Deployer();
    }

    function testWalletCanMakeCall() public {
        bytes32 expectedValue = bytes32(uint256(1));

        bytes memory callData = abi.encodeWithSelector(CallTarget.setState.selector, (expectedValue));

        deployWallet(address(callTarget), 0, callData);

        assertEq(callTarget.value(), expectedValue);
    }

    function testWalletCanMakeCallValue() public {
        uint256 expectedValue = 1 ether;

        vm.deal(walletAddress(), 1 ether);

        bytes memory callData;
        deployWallet(address(callTarget), expectedValue, callData);

        assertEq(address(callTarget).balance, expectedValue);
    }

    function testOnlyTheOwnerCanMakeCalls(address caller) public {
        vm.assume(caller != address(this));

        bytes32 expectedValue = bytes32(uint256(1));

        bytes memory callData = abi.encodeWithSelector(CallTarget.setState.selector, (expectedValue));

        deployWallet(address(callTarget), 0, callData);

        assertEq(callTarget.value(), expectedValue);

        vm.prank(caller);
        bytes32 wrongValue = bytes32(uint256(2));
        bytes memory wrongValueCallData = abi.encodeWithSelector(CallTarget.setState.selector, (wrongValue));

        // It should revert because the caller is not the owner
        vm.expectRevert(IDeployer.WalletNotDeployed.selector);
        deployer.ownerCall(salt(), address(callTarget), 0, wrongValueCallData);
    }

    function testOwnerCanMakeCall() public {
        bytes32 expectedValue = bytes32(uint256(1));
        bytes memory callData = abi.encodeWithSelector(CallTarget.setState.selector, (expectedValue));

        address wallet = deployWallet(address(callTarget), 0, callData);

        assertEq(callTarget.value(), expectedValue);

        // Set the value to 2 and ensure its set correctly.
        bytes32 newState = bytes32(uint256(2));
        bytes memory newStateCallData = abi.encodeWithSelector(CallTarget.setState.selector, (newState));
        vm.deal(wallet, 1 ether);

        deployer.ownerCall(salt(), address(callTarget), 1 ether, newStateCallData);

        assertEq(callTarget.value(), newState);
        assertEq(address(callTarget).balance, 1 ether);
    }

    function deployWallet(address to, uint256 value, bytes memory data) internal returns (address) {
        return deployer.deploy(salt(), to, value, data);
    }

    function walletAddress() internal view returns (address) {
        bytes32 actualSalt = keccak256(abi.encodePacked(salt(), address(this)));

        return vm.computeCreate2Address(actualSalt, keccak256(type(Wallet).creationCode), address(deployer));
    }

    function salt() internal pure returns (bytes32) {
        return keccak256("salt");
    }
}

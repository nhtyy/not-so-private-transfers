// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "../src/Deployer.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

contract CounterScript is Script {
    Deployer public deployer;

    function run() public {
        vm.startBroadcast();

        deployer = new Deployer();

        vm.stopBroadcast();

        writeJson();
    }

    function writeJson() internal {
        string memory outpathKey = "CONTRACT_DEPLOY_OUTPATH";
        string memory outpathDefault = "deployments.json";
        string memory outpath = vm.envOr(outpathKey, outpathDefault);

        // If there is no file, create a new one with an empty object.
        if (!vm.exists(outpath)) {
            vm.writeFile(outpath, "{}");
        }

        string memory key = Strings.toString(block.chainid);
        string memory value = vm.toString(address(deployer));

        // If the key is alreadry in the file, update the value.
        if (vm.keyExists(vm.readFile(outpath), string.concat(".", key))) {
            // Directly overwrite the value.
            vm.writeJson(value, outpath, string.concat(".", key));
        } else {
            // Serialize the whole table under root.
            string memory root = "root";
            vm.serializeJson(root, vm.readFile(outpath));

            // Insert the neew value and take the intermediate result as the new JSON.
            string memory inserted = vm.serializeAddress(root, key, address(deployer));
            vm.writeJson(inserted, outpath);
        }
    }
}

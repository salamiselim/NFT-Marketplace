// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {QuivaComic} from "../src/QuivaComic.sol";

contract DeployQuivaComic is Script {
    function run() external returns (QuivaComic) {
        vm.startBroadcast();
        QuivaComic comic = new QuivaComic("ipfs://placeholder/");
        vm.stopBroadcast();
        return comic;
    }
}

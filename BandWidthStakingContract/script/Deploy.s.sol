// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {BandWidthStaking} from "../src/NFTStaking.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

import {console} from "forge-std/Test.sol";

contract Deploy is Script {
    function run() external returns (address proxy, address logic) {
        string memory privateKeyString = vm.envString("PRIVATE_KEY");
        uint256 deployerPrivateKey;

        if (
            bytes(privateKeyString).length > 0 && bytes(privateKeyString)[0] == "0" && bytes(privateKeyString)[1] == "x"
        ) {
            deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        } else {
            deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        }

        vm.startBroadcast(deployerPrivateKey);

        (proxy, logic) = deploy();
        vm.stopBroadcast();
        console.log("Proxy Contract deployed at:", proxy);
        console.log("Logic Contract deployed at:", logic);
        return (proxy, logic);
    }

    function deploy() public returns (address proxy, address logic) {
        Options memory opts;

        logic = Upgrades.deployImplementation("NFTStaking.sol:BandWidthStaking", opts);

        address nftContract = vm.envAddress("NFT_CONTRACT");
        console.log("nftContract Address:", nftContract);

        address rewardTokenContract = vm.envAddress("REWARD_TOKEN_CONTRACT");
        console.log("rewardTokenContract Address:", rewardTokenContract);

        address dbcAIProxy = vm.envAddress("DBC_AI_PROXY");
        console.log("DBC AI Proxy Address:", dbcAIProxy);

        address slashToPay = vm.envAddress("SLASH_TO_PAY");
        console.log("SLASH_TO_PAY Address:", dbcAIProxy);

        proxy = Upgrades.deployUUPSProxy(
            "NFTStaking.sol:BandWidthStaking",
            abi.encodeCall(
                BandWidthStaking.initialize, (msg.sender, slashToPay, nftContract, rewardTokenContract, dbcAIProxy)
            )
        );
        return (proxy, logic);
    }
}

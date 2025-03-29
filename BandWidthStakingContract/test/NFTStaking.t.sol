// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BandWidthStaking} from "../src/NFTStaking.sol";

import {BandWidthStaking} from "../src/NFTStaking.sol";
import {IPrecompileContract} from "../src/interface/IPrecompileContract.sol";
import {IDBCAIContract} from "../src/interface/IDBCAIContract.sol";

import {IRewardToken} from "../src/interface/IRewardToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Token} from "./MockRewardToken.sol";
import "./MockERC1155.t.sol";
import "../src/library/ToolLib.sol";

contract RentTest is Test {
    BandWidthStaking public nftStaking;
    IPrecompileContract public precompileContract;
    Token public rewardToken;
    DLCNode public nftToken;
    IDBCAIContract public dbcAIContract;
    uint256 public mockRegionValue = 1000;

    address owner = address(0x01);
    address admin2 = address(0x02);
    address admin3 = address(0x03);
    address admin4 = address(0x04);
    address admin5 = address(0x05);

    address stakeHolder2 = address(0x06);

    function setUp() public {
        vm.startPrank(owner);
        precompileContract = IPrecompileContract(address(0x11));
        rewardToken = new Token();
        nftToken = new DLCNode(owner);

        ERC1967Proxy proxy1 = new ERC1967Proxy(address(new BandWidthStaking()), "");
        nftStaking = BandWidthStaking(address(proxy1));

        BandWidthStaking(address(proxy1)).initialize(
            owner, owner, address(nftToken), address(rewardToken), address(dbcAIContract)
        );

        deal(address(rewardToken), address(this), 10000000 * 1e18);
        deal(address(rewardToken), owner, 4_000_000_000 * 1e18);
        rewardToken.approve(address(nftStaking), 4_000_000_000 * 1e18);
        deal(address(rewardToken), address(nftStaking), 4_000_000_000 * 1e18);

        nftStaking.setRewardStartAt(block.timestamp);

        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.machineBandWidthInfos.selector),
            abi.encode(owner, "what ever", 1, 16, "Maharashtra", 100, 100)
        );
        vm.mockCall(
            address(dbcAIContract), abi.encodeWithSelector(dbcAIContract.reportStakingStatus.selector), abi.encode()
        );
        vm.mockCall(address(dbcAIContract), abi.encodeWithSelector(dbcAIContract.freeGpuAmount.selector), abi.encode(1));
        vm.mockCall(
            address(dbcAIContract),
            abi.encodeWithSelector(dbcAIContract.getMachineRegion.selector),
            abi.encode("Maharashtra")
        );

        nftStaking.setBurnAddress(owner);
        vm.stopPrank();
    }

    function testTool() public pure {
        string memory gpuType1 = "NVIDIA GeForce RTX 4060 Ti";
        assertEq(ToolLib.checkString(gpuType1), true, "checkString failed1");

        string memory gpuType2 = "Gen Intel(R) Core(TM) i7-13790F";
        assertEq(ToolLib.checkString(gpuType2), false, "checkString failed2");

        string memory gpuType3 = "NVIDIA GeForce RTX 20 Ti";
        assertEq(ToolLib.checkString(gpuType3), true, "checkString failed3");
    }

    function test_daily_reward() public {
        assertEq(nftStaking.getDailyRewardAmount(), nftStaking.INITIAL_YEARLY_REWARD() / 365);
        passDays(5 * 365);
        assertEq(nftStaking.getDailyRewardAmount(), nftStaking.INITIAL_YEARLY_REWARD() / 365 / 2);
    }

    function stakeByOwner(string memory machineId, uint256 reserveAmount, address _owner) public {
        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.machineBandWidthInfos.selector),
            abi.encode(_owner, "what ever", 1, 16, "Maharashtra", 100, 100)
        );

        vm.mockCall(
            address(nftStaking.dbcAIContract()),
            abi.encodeWithSelector(IDBCAIContract.getMachineState.selector),
            abi.encode(true, true)
        );

        vm.startPrank(_owner);
        dealERC1155(address(nftToken), _owner, 1, 1, false);
        assertEq(nftToken.balanceOf(_owner, 1), 1, "owner erc1155 failed");
        deal(address(rewardToken), _owner, 100000 * 1e18);
        rewardToken.approve(address(nftStaking), reserveAmount);
        nftToken.setApprovalForAll(address(nftStaking), true);

        uint256[] memory nftTokens = new uint256[](1);
        uint256[] memory nftTokensBalance = new uint256[](1);
        nftTokens[0] = 1;
        nftTokensBalance[0] = 1;
        uint256 totalCalcPointBefore = nftStaking.totalCalcPoint();
        nftStaking.stake(_owner, machineId, nftTokens, nftTokensBalance);
        nftStaking.addDLCToStake(machineId, reserveAmount);
        vm.stopPrank();
        uint256 totalCalcPoint = nftStaking.totalCalcPoint();

        assertEq(totalCalcPoint, totalCalcPointBefore + 100);
        (uint256 accumulated,) = nftStaking.machineId2StakeUnitRewards(machineId);
//        assertEq(accumulatedPerShare, lastAccumulatedPerShare);
        assertEq(accumulated, 0);
    }

    function testStake() public {
        address stakeHolder = owner;
        //        assertEq(nftToken.balanceOf(stakeHolder, 1), 100);
        //        address nftAddr = address(nftToken);
        string memory machineId = "machineId";
        string memory machineId2 = "machineId2";
        //        vm.mockCall(nftAddr, abi.encodeWithSelector(IERC721.transferFrom.selector), abi.encode(true));
        //        vm.mockCall(nftAddr, abi.encodeWithSelector(IERC721.balanceOf.selector), abi.encode(1));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        vm.startPrank(stakeHolder);
        // staking.stake(machineId, 0, tokenIds, 1);
        stakeByOwner(machineId, 0, stakeHolder);
        vm.stopPrank();

        //        (address[] memory topHolders, uint256[] memory topCalcPoints) = state.getTopStakeHolders();
        //        assertEq(topHolders[0], stakeHolder);
        //        assertEq(topCalcPoints[0], 100);

        assertTrue(nftStaking.isStaking(machineId));

        passDays(1);

        vm.startPrank(stakeHolder);
        assertEq(
            nftStaking.getReward(machineId) / 1e18,
            nftStaking.getDailyRewardAmount() * nftStaking.region2Value("Maharashtra") / nftStaking.totalRegionValue()
                / 1e18,
            "get reward gt failed after reward start 1 day 2"
        );
        vm.stopPrank();

        // staking.stake(machineId2, 0, tokenIds0, 2);

        vm.prank(stakeHolder2);
        stakeByOwner(machineId2, 0, stakeHolder2);
        passDays(1);

        uint256 reward2 = nftStaking.getReward(machineId2);
        assertGt(reward2, 0, "machineId2 get reward lt 0  failed after staked 1 day");

        assertLt(
            reward2,
            nftStaking.getDailyRewardAmount() / 2,
            "machineId2 get reward lt staking.getDailyRewardAmount()/2 failed after staked 1 day"
        );

        assertGt(
            nftStaking.getReward(machineId2),
            nftStaking.getDailyRewardAmount() * mockRegionValue / nftStaking.totalRegionValue() / 2 - 1 * 1e18,
            "machineId2 get reward gt staking.getDailyRewardAmount()/2 - 1 * 1e18 failed after staked 1 day"
        );

        (, uint256 rewardAmountCanClaim, uint256 lockedRewardAmount,) = nftStaking.getRewardInfo(machineId2);
        assertEq(rewardAmountCanClaim, reward2 / 10);
        assertEq(lockedRewardAmount, reward2 - reward2 / 10);

        passDays(1);
        uint256 reward4 = nftStaking.getReward(machineId2);
        console.log("reward4  ", reward4);

        (, uint256 rewardAmountCanClaim0, uint256 lockedRewardAmount0,) = nftStaking.getRewardInfo(machineId2);
        assertEq(rewardAmountCanClaim0, reward4 / 10);
        assertEq(lockedRewardAmount0, reward4 - reward4 / 10);

        vm.prank(stakeHolder2);
        nftStaking.claim(machineId2);

        reward4 = nftStaking.getReward(machineId2);
        assertEq(reward4, 0, "machineId2 get reward  failed after claim");

        passDays(1);
        (uint256 release, uint256 locked) = nftStaking.calculateReleaseReward(machineId2);
        assertEq(release, ((locked + release) * 3 days / nftStaking.LOCK_PERIOD()), "111");
        vm.stopPrank();
        uint256[] memory tokenIds3 = new uint256[](1);
        tokenIds3[0] = 10;
    }

    //    function testBurnInactiveRegionRewards() public {
    //        address stakeHolder = owner;
    //
    //        string memory machineId = "machineId";
    //
    //        uint256[] memory tokenIds = new uint256[](1);
    //        tokenIds[0] = 1;
    //        vm.startPrank(stakeHolder);
    //        // staking.stake(machineId, 0, tokenIds, 1);
    //        stakeByOwner(machineId, 0, stakeHolder);
    //        vm.stopPrank();
    //
    //        //        (address[] memory topHolders, uint256[] memory topCalcPoints) = state.getTopStakeHolders();
    //        //        assertEq(topHolders[0], stakeHolder);
    //        //        assertEq(topCalcPoints[0], 100);
    //
    //        assertTrue(nftStaking.isStaking(machineId));
    //
    //        passDays(1);
    //
    //        vm.startPrank(stakeHolder);
    //        assertLt(
    //            nftStaking.getReward(machineId),
    //            nftStaking.getDailyRewardAmount(),
    //            "get reward lt failed after reward start 1 day 1"
    //        );
    //        assertGt(
    //            nftStaking.getReward(machineId),
    //            nftStaking.getDailyRewardAmount() * mockRegionValue / nftStaking.totalRegionValue() - 1 * 1e18,
    //            "get reward gt failed after reward start 1 day 2"
    //        );
    //        vm.stopPrank();
    //
    ////        nftStaking.burnInactiveRegionRewards();
    ////        uint256 activeRegionReward = nftStaking.getDailyRewardAmount() * mockRegionValue / nftStaking.totalRegionValue();
    ////        assertLe(nftStaking.totalBurnedRewardAmount(), nftStaking.getDailyRewardAmount() - activeRegionReward);
    ////        assertGe(
    ////            nftStaking.totalBurnedRewardAmount(), nftStaking.getDailyRewardAmount() - activeRegionReward - 1 * 1e18
    ////        );
    //    }

    function claimAfter(string memory machineId, address _owner, uint256 hour, bool shouldGetMore) internal {
        uint256 balance1 = rewardToken.balanceOf(_owner);
        passHours(hour);
        vm.prank(_owner);
        nftStaking.claim(machineId);
        uint256 balance2 = rewardToken.balanceOf(_owner);
        if (shouldGetMore) {
            assertGt(balance2, balance1);
        } else {
            assertEq(balance2, balance1);
        }
    }

    function passHours(uint256 n) public {
        uint256 secondsToAdvance = n * 60 * 60;
        uint256 blocksToAdvance = secondsToAdvance / 6;

        vm.warp(vm.getBlockTimestamp() + secondsToAdvance);
        vm.roll(vm.getBlockNumber() + blocksToAdvance);
    }

    function passDays(uint256 n) public {
        uint256 secondsToAdvance = n * 24 * 60 * 60;
        uint256 blocksToAdvance = secondsToAdvance / nftStaking.SECONDS_PER_BLOCK();

        vm.warp(vm.getBlockTimestamp() + secondsToAdvance);
        vm.roll(vm.getBlockNumber() + blocksToAdvance);
    }

    function passBlocks(uint256 n) public {
        uint256 timeToAdvance = n * nftStaking.SECONDS_PER_BLOCK();

        vm.warp(vm.getBlockTimestamp() + timeToAdvance - 1);
        vm.roll(vm.getBlockNumber() + n - 1);
    }
}

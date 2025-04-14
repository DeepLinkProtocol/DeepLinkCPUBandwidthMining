// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RewardCalculatorLib} from "./library/RewardCalculatorLib.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract OldRewardCalculator {
    uint256 public constant LOCK_PERIOD = 180 days;

    uint256 public constant HALVING_PERIOD = 4 * 365 days;
    uint256 public constant INIT_REWARD_AMOUNT = 4_000_000_000 ether;
    uint256 public constant INITIAL_YEARLY_REWARD = 500_000_000 ether; // first four years reward

    uint256 public dailyRewardAmount;

    uint256 public totalAdjustUnit;
    uint256 public rewardStartAtTimestamp;

    RewardCalculatorLib.RewardsPerShare public rewardsPerCalcPoint;

    struct LockedRewardDetail {
        uint256 totalAmount;
        uint256 lockTime;
        uint256 unlockTime;
        uint256 claimedAmount;
    }

    mapping(string => LockedRewardDetail) public machineId2LockedRewardDetail;

    mapping(string => RewardCalculatorLib.UserRewards) public machineId2StakeUnitRewards;
    mapping(string => uint256) public region2totalAdjustUnit;
    mapping(string => RewardCalculatorLib.RewardsPerShare) public region2RewardPerCalcPoint;

    event RewardsPerCalcPointUpdate(uint256 accumulatedPerShareBefore, uint256 accumulatedPerShareAfter);

    function __RewardCalculator_init() internal {}

    function _getRewardDetail(uint256 totalRewardAmount)
        internal
        pure
        returns (uint256 canClaimAmount, uint256 lockedAmount)
    {
        uint256 releaseImmediateAmount = totalRewardAmount / 10;
        uint256 releaseLinearLockedAmount = totalRewardAmount - releaseImmediateAmount;
        return (releaseImmediateAmount, releaseLinearLockedAmount);
    }

    function calculateReleaseReward(string memory machineId)
        public
        view
        returns (uint256 releaseAmount, uint256 lockedAmount)
    {
        LockedRewardDetail storage lockedRewardDetail = machineId2LockedRewardDetail[machineId];
        if (lockedRewardDetail.totalAmount > 0 && lockedRewardDetail.totalAmount == lockedRewardDetail.claimedAmount) {
            return (0, 0);
        }

        if (block.timestamp > lockedRewardDetail.unlockTime) {
            releaseAmount = lockedRewardDetail.totalAmount - lockedRewardDetail.claimedAmount;
            return (releaseAmount, 0);
        }

        uint256 totalUnlocked =
            (block.timestamp - lockedRewardDetail.lockTime) * lockedRewardDetail.totalAmount / LOCK_PERIOD;
        releaseAmount = totalUnlocked - lockedRewardDetail.claimedAmount;
        return (releaseAmount, lockedRewardDetail.totalAmount - releaseAmount);
    }

    function _updateRewardPerCalcPoint(
        uint256 totalDistributedRewardAmount,
        uint256 totalBurnedRewardAmount,
        uint256 totalShare
    ) internal {
        uint256 accumulatedPerShareBefore = rewardsPerCalcPoint.accumulatedPerShare;
        rewardsPerCalcPoint =
            _getUpdatedRewardPerCalcPoint(totalDistributedRewardAmount, totalBurnedRewardAmount, totalShare);
        emit RewardsPerCalcPointUpdate(accumulatedPerShareBefore, rewardsPerCalcPoint.accumulatedPerShare);
    }

    function _updateRegionRewardPerCalcPoint(string memory region, uint256 regionRewardsPerSeconds) internal {
        uint256 regionTotalShare = region2totalAdjustUnit[region];
        uint256 accumulatedPerShareBefore = region2RewardPerCalcPoint[region].accumulatedPerShare;
        rewardsPerCalcPoint = _getUpdatedRegionRewardPerCalcPoint(regionTotalShare, regionRewardsPerSeconds);
        emit RewardsPerCalcPointUpdate(accumulatedPerShareBefore, rewardsPerCalcPoint.accumulatedPerShare);
    }

    function _getUpdatedRewardPerCalcPoint(
        uint256 totalDistributedRewardAmount,
        uint256 totalBurnedRewardAmount,
        uint256 totalShare
    ) internal view returns (RewardCalculatorLib.RewardsPerShare memory) {
        uint256 rewardsPerSeconds =
            (_getDailyRewardAmount(totalDistributedRewardAmount, totalBurnedRewardAmount)) / 1 days;
        if (rewardStartAtTimestamp == 0) {
            return RewardCalculatorLib.RewardsPerShare(0, 0);
        }

        uint256 rewardEndAt = 0;
        RewardCalculatorLib.RewardsPerShare memory rewardsPerTokenUpdated = RewardCalculatorLib.getUpdateRewardsPerShare(
            rewardsPerCalcPoint, totalShare, rewardsPerSeconds, rewardStartAtTimestamp, rewardEndAt
        );
        return rewardsPerTokenUpdated;
    }

    function _getUpdatedRegionRewardPerCalcPoint(uint256 regionTotalShare, uint256 regionRewardsPerSeconds)
        internal
        view
        returns (RewardCalculatorLib.RewardsPerShare memory)
    {
        if (rewardStartAtTimestamp == 0) {
            return RewardCalculatorLib.RewardsPerShare(0, 0);
        }

        uint256 rewardEndAt = 0;
        RewardCalculatorLib.RewardsPerShare memory rewardsPerTokenUpdated = RewardCalculatorLib.getUpdateRewardsPerShare(
            rewardsPerCalcPoint, regionTotalShare, regionRewardsPerSeconds, rewardStartAtTimestamp, rewardEndAt
        );
        return rewardsPerTokenUpdated;
    }

    function _getDailyRewardAmount(uint256 totalDistributedRewardAmount, uint256 totalBurnedRewardAmount)
        public
        view
        returns (uint256)
    {
        uint256 timestamp = block.timestamp;
        require(timestamp >= rewardStartAtTimestamp, "Timestamp must be after start time");

        uint256 elapsedTime = timestamp - rewardStartAtTimestamp;
        uint256 cycle = elapsedTime / HALVING_PERIOD;
        uint256 yearlyReward = INITIAL_YEARLY_REWARD / (2 ** cycle);

        uint256 dailyReward = yearlyReward / 365;

        uint256 rewardUsed = totalDistributedRewardAmount + totalBurnedRewardAmount;
        rewardUsed = Math.min(rewardUsed, INIT_REWARD_AMOUNT);
        uint256 remainingSupply = INIT_REWARD_AMOUNT - rewardUsed;
        if (dailyReward > remainingSupply) {
            return remainingSupply;
        }

        return dailyReward;
    }

    function _updateMachineRewardsOfRegion(
        string memory machineId,
        uint256 machineShares,
        string memory region,
        uint256 regionRewardsPerSeconds
    ) internal {
        _updateRegionRewardPerCalcPoint(region, regionRewardsPerSeconds);
        RewardCalculatorLib.UserRewards memory machineRewards = machineId2StakeUnitRewards[machineId];
        if (machineRewards.lastAccumulatedPerShare == 0) {
            machineRewards.lastAccumulatedPerShare = rewardsPerCalcPoint.accumulatedPerShare;
        }

        RewardCalculatorLib.RewardsPerShare storage regionRewardsPerCalcPoint = region2RewardPerCalcPoint[region];
        if (regionRewardsPerCalcPoint.lastUpdated == 0) {
            regionRewardsPerCalcPoint.lastUpdated = block.timestamp;
        }
        RewardCalculatorLib.UserRewards memory machineRewardsUpdated =
            RewardCalculatorLib.getUpdateMachineRewards(machineRewards, machineShares, regionRewardsPerCalcPoint);
        machineId2StakeUnitRewards[machineId] = machineRewardsUpdated;
    }

    function _updateMachineRewards(
        string memory machineId,
        uint256 machineShares,
        uint256 totalDistributedRewardAmount,
        uint256 totalBurnedRewardAmount
    ) internal {
        uint256 totalShare = region2totalAdjustUnit[machineId];
        _updateRewardPerCalcPoint(totalDistributedRewardAmount, totalBurnedRewardAmount, totalShare);

        RewardCalculatorLib.UserRewards memory machineRewards = machineId2StakeUnitRewards[machineId];
        if (machineRewards.lastAccumulatedPerShare == 0) {
            machineRewards.lastAccumulatedPerShare = rewardsPerCalcPoint.accumulatedPerShare;
        }
        RewardCalculatorLib.UserRewards memory machineRewardsUpdated =
            RewardCalculatorLib.getUpdateMachineRewards(machineRewards, machineShares, rewardsPerCalcPoint);
        machineId2StakeUnitRewards[machineId] = machineRewardsUpdated;
    }

    function calculateReleaseRewardAndUpdate(string memory machineId)
        internal
        returns (uint256 releaseAmount, uint256 lockedAmount)
    {
        LockedRewardDetail storage lockedRewardDetail = machineId2LockedRewardDetail[machineId];
        if (lockedRewardDetail.totalAmount > 0 && lockedRewardDetail.totalAmount == lockedRewardDetail.claimedAmount) {
            return (0, 0);
        }

        if (block.timestamp > lockedRewardDetail.unlockTime) {
            releaseAmount = lockedRewardDetail.totalAmount - lockedRewardDetail.claimedAmount;
            lockedRewardDetail.claimedAmount = lockedRewardDetail.totalAmount;
            return (releaseAmount, 0);
        }

        uint256 totalUnlocked =
            (block.timestamp - lockedRewardDetail.lockTime) * lockedRewardDetail.totalAmount / LOCK_PERIOD;
        releaseAmount = totalUnlocked - lockedRewardDetail.claimedAmount;
        lockedRewardDetail.claimedAmount += releaseAmount;
        return (releaseAmount, lockedRewardDetail.totalAmount - releaseAmount);
    }

    function rewardStart() internal view returns (bool) {
        return rewardStartAtTimestamp > 0 && block.timestamp >= rewardStartAtTimestamp;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console.sol";

library RewardCalculatorLib {
    uint256 private constant PRECISION_FACTOR = 1 ether;

    struct RewardsPerShare {
        uint256 accumulatedPerShare; // accumulated rewards per share
        uint256 lastUpdated; // accumulated rewards per share last updated time
    }

    struct UserRewards {
        uint256 accumulated; // user accumulated rewards
        uint256 lastAccumulatedPerShare; // last accumulated rewards per share of user
    }

    function getOneDayUpdateRewardsPerShare(
        RewardsPerShare memory rewardsPerTokenIn,
        uint256 totalShares,
        uint256 rewardsRate,
        uint256 rewardsStart,
        uint256 rewardsEnd
    ) internal view returns (RewardsPerShare memory) {
        RewardsPerShare memory rewardsPerTokenOut =
            RewardsPerShare(rewardsPerTokenIn.accumulatedPerShare, rewardsPerTokenIn.lastUpdated);

        if (block.timestamp < rewardsStart) return rewardsPerTokenOut;

        uint256 updateTime;
        if (rewardsEnd == 0) {
            updateTime = block.timestamp;
        } else {
            updateTime = block.timestamp < rewardsEnd ? block.timestamp : rewardsEnd;
        }
        uint256 elapsed = 1 days;

        if (elapsed == 0) return rewardsPerTokenOut;
        rewardsPerTokenOut.lastUpdated = updateTime;

        if (totalShares == 0) return rewardsPerTokenOut;

        rewardsPerTokenOut.accumulatedPerShare =
            rewardsPerTokenIn.accumulatedPerShare + PRECISION_FACTOR * elapsed * rewardsRate / totalShares;
        return rewardsPerTokenOut;
    }

    function getUpdateRewardsPerShare(
        RewardsPerShare memory rewardsPerTokenIn,
        uint256 totalShares,
        uint256 rewardsRate,
        uint256 rewardsStart,
        uint256 rewardsEnd
    ) internal view returns (RewardsPerShare memory) {
        RewardsPerShare memory rewardsPerTokenOut =
            RewardsPerShare(rewardsPerTokenIn.accumulatedPerShare, rewardsPerTokenIn.lastUpdated);

        if (block.timestamp < rewardsStart) return rewardsPerTokenOut;

        uint256 updateTime;
        if (rewardsEnd == 0) {
            updateTime = block.timestamp;
        } else {
            updateTime = block.timestamp < rewardsEnd ? block.timestamp : rewardsEnd;
        }
        uint256 elapsed = updateTime > rewardsPerTokenIn.lastUpdated ? updateTime - rewardsPerTokenIn.lastUpdated : 0;

        if (elapsed == 0) return rewardsPerTokenOut;
        rewardsPerTokenOut.lastUpdated = updateTime;

        if (totalShares == 0) return rewardsPerTokenOut;

        rewardsPerTokenOut.accumulatedPerShare =
            rewardsPerTokenIn.accumulatedPerShare + PRECISION_FACTOR * elapsed * rewardsRate / totalShares;
        return rewardsPerTokenOut;
    }

    function getUpdateMachineRewards(
        UserRewards memory machineRewardsIn,
        uint256 machineShares,
        RewardsPerShare memory rewardsPerToken_
    ) internal pure returns (UserRewards memory) {
        if (machineRewardsIn.lastAccumulatedPerShare == rewardsPerToken_.lastUpdated) return machineRewardsIn;

        machineRewardsIn.accumulated += calculatePendingMachineRewards(
            machineShares, rewardsPerToken_.accumulatedPerShare, machineRewardsIn.lastAccumulatedPerShare
        );
        machineRewardsIn.lastAccumulatedPerShare = rewardsPerToken_.accumulatedPerShare;

        return machineRewardsIn;
    }

    function calculatePendingMachineRewards(
        uint256 userShares,
        uint256 latterAccumulatedPerShare,
        uint256 earlierAccumulatedPerShare
    ) internal pure returns (uint256) {
        if (latterAccumulatedPerShare < earlierAccumulatedPerShare) {
            return 0;
        }
        if (earlierAccumulatedPerShare == 0) {
            return 0;
        }
        return userShares * (latterAccumulatedPerShare - earlierAccumulatedPerShare) / PRECISION_FACTOR;
    }
}

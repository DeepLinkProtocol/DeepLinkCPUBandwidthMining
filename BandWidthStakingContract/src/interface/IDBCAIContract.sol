pragma solidity ^0.8.20;

import {BandWidthStaking} from "../NFTStaking.sol";

interface IDBCAIContract {
    function getMachineState(
        string calldata machineId,
        string calldata projectName,
        BandWidthStaking.StakingType stakingType
    ) external view returns (bool isOnline, bool isRegistered);

    function getMachineInfo(string calldata id, bool isDeepLink)
        external
        view
        returns (
            address machineOwner,
            uint256 calcPoint,
            uint256 cpuRate,
            string memory gpuType,
            uint256 gpuMem,
            string memory cpuType,
            uint256 gpuCount,
            string memory machineId,
            uint256 mem
        );

    function freeGpuAmount(string calldata) external pure returns (uint256);

    function reportStakingStatus(
        string calldata projectName,
        BandWidthStaking.StakingType stakingType,
        string calldata id,
        uint256 gpuNum,
        bool isStake
    ) external;

    function getMachineRegion(string calldata _id) external view returns (string memory);
}

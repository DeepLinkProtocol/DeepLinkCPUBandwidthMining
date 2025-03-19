pragma solidity ^0.8.20;

import {BandWidthStaking} from "../NFTStaking.sol";

interface IDBCAIContract {
    function getMachineState(
        string calldata machineId,
        string calldata projectName,
        BandWidthStaking.StakingType stakingType
    ) external view returns (bool isOnline, bool isRegistered);

    function freeGpuAmount(string calldata) external pure returns (uint256);

    function reportStakingStatus(
        string calldata projectName,
        BandWidthStaking.StakingType stakingType,
        string calldata id,
        uint256 gpuNum,
        bool isStake
    ) external;

    function getMachineRegion(string calldata _id) external view returns (string memory);

    function machineBandWidthInfos(string calldata _machineId)
        external
        view
        returns (
            address machineOwner,
            string memory machineId,
            uint256 cpuCores,
            uint256 machineMem,
            string memory region,
            uint256 hdd,
            uint256 bandwidth
        );
}

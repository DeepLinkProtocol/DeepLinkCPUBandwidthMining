// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/interface/IDBCAIContract.sol";
import "forge-std/console.sol";
//
//struct MachineInfo {
//    address machineOwner;
//    uint256 calcPoint;
//    uint256 cpuRate;
//    string gpuType;
//    uint256 gpuMem;
//    string cpuType;
//    uint256 gpuCount;
//    string machineId;
//}
//
//contract DBCStakingContractMock is IDBCAIContract {
//    mapping(string => MachineInfo) private machineInfoStore;
//
//    constructor() {
//        machineInfoStore["machineId"] = MachineInfo({
//            machineOwner: address(0x10), // machineOwner
//            calcPoint: 100, // calcPoint
//            cpuRate: 3600, // cpuRate
//            gpuType: "NVIDIA", // gpuType
//            gpuMem: 16, // gpuMem
//            cpuType: "Intel", // cpuType
//            gpuCount: 1, // gpuCount
//            machineId: "machineId"
//        });
//
//        machineInfoStore["machineId2"] = MachineInfo({
//            machineOwner: address(0x20), // machineOwner
//            calcPoint: 100, // calcPoint
//            cpuRate: 3600, // cpuRate
//            gpuType: "NVIDIA", // gpuType
//            gpuMem: 16, // gpuMem
//            cpuType: "Intel", // cpuType
//            gpuCount: 1, // gpuCount
//            machineId: "machineId"
//        });
//
//        machineInfoStore["machineId3"] = MachineInfo({
//            machineOwner: address(0x10), // machineOwner
//            calcPoint: 100, // calcPoint
//            cpuRate: 3600, // cpuRate
//            gpuType: "NVIDIA", // gpuType
//            gpuMem: 16, // gpuMem
//            cpuType: "Intel", // cpuType
//            gpuCount: 1, // gpuCount
//            machineId: "machineId"
//        });
//    }
//
//    function getMachineInfo(string calldata id, bool isDeepLink)
//        external
//        view
//        override
//        returns (
//            address machineOwner,
//            uint256 calcPoint,
//            uint256 cpuRate,
//            string memory gpuType,
//            uint256 gpuMem,
//            string memory cpuType,
//            uint256 gpuCount,
//            string memory machineId,
//            uint256 mem
//        )
//    {
//        isDeepLink = true;
//        MachineInfo storage machine = machineInfoStore[id];
//
//        machineOwner = machine.machineOwner;
//        calcPoint = machine.calcPoint;
//        cpuRate = machine.cpuRate;
//        gpuType = machine.gpuType;
//        gpuMem = machine.gpuMem;
//        cpuType = machine.cpuType;
//        gpuCount = machine.gpuCount;
//        machineId = machine.machineId;
//        mem = 16;
//    }
//
//    function getMachineState(string calldata id, string calldata projectName, BandWidthStaking.StakingType stakingType)
//        external
//        pure
//        returns (bool isOnline, bool isRegistered)
//    {
//        console.log("id: ", id);
//        console.log("projectName: ", projectName);
//        console.log("stakingType: ", uint256(stakingType));
//
//        return (true, true);
//    }
//
//    function freeGpuAmount(string calldata) external pure returns (uint256) {
//        return 1;
//    }
//
//    function reportStakingStatus(string calldata, BandWidthStaking.StakingType, string calldata, uint256, bool)
//        external
//        pure
//    {
//        return;
//    }
//
//    function getMachineRegion(string calldata) public pure returns (string memory) {
//        return "region";
//    }
//
//    function machineBandWidthInfos(string calldata machineId)
//        public
//        view
//        returns (
//            address machineOwner,
//            string memory machineId,
//            uint256 cpuCores,
//            uint256 machineMem,
//            string memory region,
//            uint256 hdd,
//            uint256 bandwidth
//        )
//    {
//        MachineInfo storage machine = machineInfoStore[machineId];
//
//        machineOwner = machine.machineOwner;
//        calcPoint = machine.calcPoint;
//        cpuRate = machine.cpuRate;
//        gpuType = machine.gpuType;
//        gpuMem = machine.gpuMem;
//        cpuType = machine.cpuType;
//        gpuCount = machine.gpuCount;
//        machineId = machine.machineId;
//        mem = 16;
//    }
//}

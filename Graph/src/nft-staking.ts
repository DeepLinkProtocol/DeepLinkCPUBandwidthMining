import { BigInt, Bytes } from '@graphprotocol/graph-ts';
import {
  Claimed as ClaimedEvent,
  OwnershipTransferred as OwnershipTransferredEvent,
  PaySlash as PaySlashEvent,
  RentMachine as RentMachineEvent,
  ReportMachineFault as ReportMachineFaultEvent,
  ReserveDLC as ReserveDLCEvent,
  Staked as StakedEvent,
  Unstaked as UnstakedEvent,
  MoveToReserveAmount as MoveToReserveAmountEvent,
  BurnedInactiveRegionRewards as BurnedInactiveRegionRewardsEvent,
  BurnedInactiveSingleRegionRewards as BurnedInactiveSingleRegionRewardsEvent, UpdateRegion,
} from '../generated/NFTStaking/NFTStaking';
import {
  StateSummary,
  StakeHolder,
  MachineInfo,
  RegionInfo, RegionBurnInfo,
} from '../generated/schema';

export function handleClaimed(event: ClaimedEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  if (machineInfo == null) {
    return;
  }

  machineInfo.totalClaimedRewardAmount =
    machineInfo.totalClaimedRewardAmount.plus(event.params.totalRewardAmount);
  machineInfo.totalReleasedRewardAmount = machineInfo.totalReleasedRewardAmount
    .plus(event.params.moveToUserWalletAmount)
    .plus(event.params.moveToReservedAmount);
  machineInfo.save();

  let stakeholder = StakeHolder.load(
    Bytes.fromHexString(machineInfo.holder.toHexString())
  );
  if (stakeholder == null) {
    return;
  }

  stakeholder.totalReleasedRewardAmount =
    stakeholder.totalReleasedRewardAmount.plus(
      event.params.moveToUserWalletAmount
    );
  stakeholder.totalClaimedRewardAmount =
    stakeholder.totalClaimedRewardAmount.plus(event.params.totalRewardAmount);
  // stakeholder.totalreservedAmount = stakeholder.totalreservedAmount.plus(event.params.moveToreservedAmount)
  stakeholder.save();
}

export function handleMoveToReserveAmount(
  event: MoveToReserveAmountEvent
): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  if (machineInfo == null) {
    return;
  }

  machineInfo.totalReservedAmount = machineInfo.totalReservedAmount.plus(
    event.params.amount
  );
  machineInfo.save();

  let stakeholder = StakeHolder.load(
    Bytes.fromHexString(machineInfo.holder.toHexString())
  );
  if (stakeholder == null) {
    return;
  }

  stakeholder.totalReservedAmount = stakeholder.totalReservedAmount.plus(
    event.params.amount
  );
  stakeholder.save();

  let stateSummary = StateSummary.load(Bytes.empty());
  if (stateSummary == null) {
    return;
  }

  stateSummary.totalReservedAmount = stateSummary.totalReservedAmount.plus(
    event.params.amount
  );
  stateSummary.save();

  let regionInfo = RegionInfo.load(Bytes.fromUTF8(machineInfo.region));
  if (regionInfo == null) {
    return
  }
  regionInfo.reservedAmount = regionInfo.reservedAmount.plus(
    event.params.amount
  );
  regionInfo.save();
}

export function handlePaySlash(event: PaySlashEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  if (machineInfo == null) {
    return;
  }

  machineInfo.totalReservedAmount = machineInfo.totalReservedAmount.minus(
    event.params.slashAmount
  );
  machineInfo.save();

  let stakeholder = StakeHolder.load(
    Bytes.fromHexString(machineInfo.holder.toHexString())
  );
  if (stakeholder == null) {
    return;
  }

  stakeholder.totalReservedAmount = stakeholder.totalReservedAmount.minus(
    event.params.slashAmount
  );
  stakeholder.save();

  let stateSummary = StateSummary.load(Bytes.empty());
  if (stateSummary == null) {
    return;
  }

  stateSummary.totalReservedAmount = stateSummary.totalReservedAmount.minus(
    event.params.slashAmount
  );
  stateSummary.save();
}

export function handleReserveDLC(event: ReserveDLCEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  if (machineInfo == null) {
    return;
  }

  machineInfo.totalReservedAmount = machineInfo.totalReservedAmount.plus(
    event.params.amount
  );
  machineInfo.save();

  let stakeholder = StakeHolder.load(
    Bytes.fromHexString(machineInfo.holder.toHexString())
  );
  if (stakeholder == null) {
    // never happen
    stakeholder = new StakeHolder(
      Bytes.fromHexString(machineInfo.holder.toHexString())
    );
    return;
  }

  stakeholder.totalReservedAmount = stakeholder.totalReservedAmount.plus(
    event.params.amount
  );
  stakeholder.save();

  let stateSummary = StateSummary.load(Bytes.empty());
  if (stateSummary == null) {
    return;
  }

  stateSummary.totalReservedAmount = stateSummary.totalReservedAmount.plus(
    event.params.amount
  );
  stateSummary.save();


  let regionInfo = RegionInfo.load(Bytes.fromUTF8(machineInfo.region));
  if (regionInfo == null) {
    return
  }
  regionInfo.reservedAmount = regionInfo.reservedAmount.plus(
    event.params.amount
  );
  regionInfo.save();

}

export function handleStaked(event: StakedEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  let isNewMachine: boolean = false;
  if (machineInfo == null) {
    isNewMachine = true;
    machineInfo = new MachineInfo(id);
    machineInfo.blockNumber = event.block.number;
    machineInfo.blockTimestamp = event.block.timestamp;
    machineInfo.transactionHash = event.transaction.hash;
    machineInfo.machineId = event.params.machineId;
    machineInfo.totalReservedAmount = BigInt.fromI32(0);
    machineInfo.region = "";
    machineInfo.totalClaimedRewardAmount = BigInt.fromI32(0);
    machineInfo.totalReleasedRewardAmount = BigInt.fromI32(0);
    machineInfo.totalCalcPoint = BigInt.fromI32(0);
    machineInfo.totalCalcPointWithNFT = BigInt.fromI32(0);
    machineInfo.fullTotalCalcPoint = BigInt.fromI32(0);
    machineInfo.isStaking = true;
    machineInfo.online = true;
    machineInfo.registered = true;
    machineInfo.regionRef = Bytes.empty();
    machineInfo.holderRef = Bytes.empty();
  }

  machineInfo.region = event.params.region
  machineInfo.holder = event.params.stakeholder;
  machineInfo.totalCalcPoint = event.params.originCalcPoint;
  machineInfo.totalCalcPointWithNFT = event.params.calcPoint;
  machineInfo.fullTotalCalcPoint = event.params.calcPoint;
  machineInfo.isStaking = true;
  machineInfo.online = true;
  machineInfo.registered = true;


  let stakeholder = StakeHolder.load(
    Bytes.fromHexString(event.params.stakeholder.toHexString())
  );
  if (stakeholder == null) {
    stakeholder = new StakeHolder(
      Bytes.fromHexString(event.params.stakeholder.toHexString())
    );
    stakeholder.holder = event.params.stakeholder;
    stakeholder.blockNumber = event.block.number;
    stakeholder.blockTimestamp = event.block.timestamp;
    stakeholder.transactionHash = event.transaction.hash;
    stakeholder.machineCount = BigInt.fromI32(0);
    stakeholder.totalStakingGPUCount = BigInt.fromI32(0);
    stakeholder.totalCalcPoint = BigInt.fromI32(0);
    stakeholder.fullTotalCalcPoint = BigInt.fromI32(0);
    stakeholder.totalReservedAmount = BigInt.fromI32(0);
    stakeholder.totalReleasedRewardAmount = BigInt.fromI32(0);
    stakeholder.totalClaimedRewardAmount = BigInt.fromI32(0);
  }


  if (isNewMachine) {
    stakeholder.machineCount = stakeholder.machineCount.plus(BigInt.fromI32(1));
  }
  stakeholder.totalStakingGPUCount = stakeholder.totalStakingGPUCount.plus(
    BigInt.fromI32(1)
  );
  stakeholder.totalCalcPoint = stakeholder.totalCalcPoint.plus(
    machineInfo.totalCalcPoint
  );
  stakeholder.fullTotalCalcPoint = stakeholder.fullTotalCalcPoint.plus(
    machineInfo.fullTotalCalcPoint
  );
  stakeholder.save();

  machineInfo.holderRef = stakeholder.id;

  let isNewRegion: boolean = false;
  let regionInfo = RegionInfo.load(Bytes.fromUTF8(machineInfo.region));
  if (regionInfo == null) {
    isNewRegion = true;
    regionInfo = new RegionInfo(Bytes.fromUTF8(machineInfo.region));
    regionInfo.region = machineInfo.region;
    regionInfo.stakingMachineCount = BigInt.fromI32(0);
    regionInfo.totalMachineCount = BigInt.fromI32(0);
    regionInfo.totalBandwidth = BigInt.fromI32(0);
    regionInfo.stakingBandwidth = BigInt.fromI32(0);
    regionInfo.reservedAmount = BigInt.fromI32(0);
    regionInfo.burnedAmount = BigInt.fromI32(0);
  }


  regionInfo.stakingMachineCount = regionInfo.stakingMachineCount.plus(
    BigInt.fromI32(1)
  );

  regionInfo.stakingBandwidth = regionInfo.stakingBandwidth.plus(
    machineInfo.totalCalcPoint
  );

  if (isNewMachine) {
    regionInfo.totalMachineCount = regionInfo.totalMachineCount.plus(
      BigInt.fromI32(1)
    );
    regionInfo.totalBandwidth = regionInfo.totalBandwidth.plus(
      machineInfo.totalCalcPoint
    );
  }
  regionInfo.save();

  machineInfo.regionRef = regionInfo.id;
  machineInfo.save();
  //
  let stateSummary = StateSummary.load(Bytes.empty());
  if (stateSummary == null) {
    stateSummary = new StateSummary(Bytes.empty());
    stateSummary.totalGPUCount = BigInt.fromI32(0);
    stateSummary.totalStakingGPUCount = BigInt.fromI32(0);
    stateSummary.totalCalcPointPoolCount = BigInt.fromI32(0);
    stateSummary.totalBurnedReward = BigInt.fromI32(0);
    stateSummary.totalReservedAmount = BigInt.fromI32(0);
    stateSummary.totalCalcPoint = BigInt.fromI32(0);
    stateSummary.totalRegionCount = BigInt.fromI32(0);
  }
  if (isNewMachine) {
    stateSummary.totalGPUCount = stateSummary.totalGPUCount.plus(
      BigInt.fromI32(1)
    );
    stateSummary.totalCalcPoint = stateSummary.totalCalcPoint.plus(
      machineInfo.totalCalcPoint
    );
  }
  if (isNewRegion) {
    stateSummary.totalRegionCount = stateSummary.totalRegionCount.minus(
      BigInt.fromI32(1)
    );
  }
  stateSummary.totalStakingGPUCount = stateSummary.totalStakingGPUCount.plus(
    BigInt.fromI32(1)
  );
  if (stakeholder.totalStakingGPUCount.toU32() == 1) {
    stateSummary.totalCalcPointPoolCount =
      stateSummary.totalCalcPointPoolCount.plus(BigInt.fromI32(1));
  }

  stateSummary.save();
  return;
}

export function handleUnstaked(event: UnstakedEvent): void {
  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  if (machineInfo == null) {
    return;
  }

  let stakeholder = StakeHolder.load(
    Bytes.fromHexString(event.params.stakeholder.toHexString())
  );
  if (stakeholder == null) {
    return;
  }

  stakeholder.fullTotalCalcPoint = stakeholder.fullTotalCalcPoint.minus(
    machineInfo.fullTotalCalcPoint
  );
  stakeholder.totalReservedAmount = stakeholder.totalReservedAmount.minus(
    machineInfo.totalReservedAmount
  );
  stakeholder.totalStakingGPUCount = stakeholder.totalStakingGPUCount.minus(
    BigInt.fromI32(1)
  );
  stakeholder.totalCalcPoint = stakeholder.totalCalcPoint.minus(
    machineInfo.totalCalcPoint
  );
  stakeholder.save();

  let stateSummary = StateSummary.load(Bytes.empty());
  if (stateSummary == null) {
    return;
  }

  let regionInfo = RegionInfo.load(Bytes.fromUTF8(machineInfo.region));
  if (regionInfo == null) {
    return;
  }

  regionInfo.stakingBandwidth = regionInfo.stakingBandwidth.minus(
    machineInfo.totalCalcPoint
  );

  regionInfo.stakingMachineCount = regionInfo.stakingMachineCount.minus(
    BigInt.fromI32(1)
  );

  regionInfo.reservedAmount = regionInfo.reservedAmount.minus(
    machineInfo.totalReservedAmount
  )

  regionInfo.save();

  if (regionInfo.stakingMachineCount.toI32() == 0) {
    stateSummary.totalRegionCount = stateSummary.totalRegionCount.minus(
      BigInt.fromI32(1)
    );
  }

  stateSummary.totalStakingGPUCount = stateSummary.totalStakingGPUCount.minus(
    BigInt.fromU32(1)
  );

  if (stakeholder.totalCalcPoint.toU32() == 0) {
    stateSummary.totalCalcPointPoolCount =
      stateSummary.totalCalcPointPoolCount.minus(BigInt.fromI32(1));
  }
  stateSummary.totalReservedAmount = stateSummary.totalReservedAmount.minus(
    machineInfo.totalReservedAmount
  );
  stateSummary.save();

  machineInfo.totalReservedAmount = BigInt.zero();
  machineInfo.totalCalcPoint = BigInt.zero();
  machineInfo.fullTotalCalcPoint = BigInt.zero();
  machineInfo.totalCalcPointWithNFT = BigInt.zero();
  machineInfo.isStaking = false;
  machineInfo.online = false;
  machineInfo.registered = false;
  machineInfo.save();
}

export function handleBurnedInactiveRegionRewards(
  event: BurnedInactiveRegionRewardsEvent
): void {
  let stateSummary = StateSummary.load(Bytes.empty());
  if (stateSummary == null) {
    return;
  }

  stateSummary.totalBurnedReward = stateSummary.totalBurnedReward.plus(
    event.params.amount
  );
  stateSummary.save();
}


export function handleBurnedInactiveSingleRegionRewards(event: BurnedInactiveSingleRegionRewardsEvent): void {
  let regionInfo = RegionInfo.load(Bytes.fromUTF8(event.params.region));
  if (regionInfo == null) {
    regionInfo = new RegionInfo(Bytes.fromUTF8(event.params.region));
    regionInfo.region = event.params.region;
    regionInfo.stakingMachineCount = BigInt.fromI32(0);
    regionInfo.totalMachineCount = BigInt.fromI32(0);
    regionInfo.totalBandwidth = BigInt.fromI32(0);
    regionInfo.stakingBandwidth = BigInt.fromI32(0);
    regionInfo.reservedAmount = BigInt.fromI32(0);
    regionInfo.burnedAmount = BigInt.fromI32(0);
    return
  }

  regionInfo.burnedAmount = regionInfo.burnedAmount.plus(
    event.params.amount
  );

  regionInfo.save();

  let regionBurnInfo = new RegionBurnInfo(event.transaction.hash)
  regionBurnInfo.region = event.params.region
  regionBurnInfo.burnedAmount = event.params.amount
  regionBurnInfo.blockTimestamp = event.block.timestamp
  regionBurnInfo.transactionHash = event.transaction.hash
  regionBurnInfo.save()

}

// export function handleUpdateRegion(event: UpdateRegion): void {
//   let id = Bytes.fromUTF8(event.params.machineId.toString());
//   let machineInfo = MachineInfo.load(id);
//   if (machineInfo == null) {
//     return;
//   }
//
//   // machine region handle
//   const oldRegion = machineInfo.region
//   machineInfo.region = event.params.region;
//
//   // new region handle
//   let isNewRegion: boolean = false;
//   let newRegionInfo = RegionInfo.load(Bytes.fromUTF8(event.params.region));
//   if (newRegionInfo == null) {
//     isNewRegion = true;
//     newRegionInfo = new RegionInfo(Bytes.fromUTF8(event.params.region));
//     newRegionInfo.region = event.params.region;
//     newRegionInfo.stakingMachineCount = BigInt.fromI32(0);
//     newRegionInfo.totalMachineCount = BigInt.fromI32(0);
//     newRegionInfo.totalBandwidth = BigInt.fromI32(0);
//     newRegionInfo.stakingBandwidth = BigInt.fromI32(0);
//     newRegionInfo.reservedAmount = BigInt.fromI32(0);
//     newRegionInfo.burnedAmount = BigInt.fromI32(0);
//   }
//
//   newRegionInfo.stakingMachineCount = newRegionInfo.stakingMachineCount.plus(
//     BigInt.fromI32(1)
//   );
//
//   newRegionInfo.stakingBandwidth = newRegionInfo.stakingBandwidth.plus(
//     machineInfo.totalCalcPoint
//   );
//
//   newRegionInfo.totalMachineCount = newRegionInfo.totalMachineCount.plus(
//       BigInt.fromI32(1)
//   );
//
//   newRegionInfo.totalBandwidth = newRegionInfo.totalBandwidth.plus(
//       machineInfo.totalCalcPoint
//   );
//
//   newRegionInfo.reservedAmount = newRegionInfo.reservedAmount.plus(
//     machineInfo.totalReservedAmount
//   );
//
//   newRegionInfo.save();
//
//   machineInfo.regionRef = newRegionInfo.id;
//   machineInfo.save();
//
//
//   // old region handle
//   let oldRegionInfo = RegionInfo.load(Bytes.fromUTF8(oldRegion));
//   if (oldRegionInfo == null) {
//     return
//   }
//
//   oldRegionInfo.stakingBandwidth = oldRegionInfo.stakingBandwidth.minus(
//     machineInfo.totalCalcPoint
//   );
//
//   oldRegionInfo.stakingMachineCount = oldRegionInfo.stakingMachineCount.minus(
//     BigInt.fromI32(1)
//   );
//
//   oldRegionInfo.totalBandwidth = oldRegionInfo.totalBandwidth.minus(
//     machineInfo.totalCalcPoint
//   );
//
//   oldRegionInfo.reservedAmount = oldRegionInfo.reservedAmount.minus(
//     machineInfo.totalReservedAmount
//   )
//
//   oldRegionInfo.save();
//
// }
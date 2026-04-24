import { BigInt, Bytes, crypto, ethereum } from '@graphprotocol/graph-ts';
import {
  Claimed as ClaimedEventSrc,
  PaySlash as PaySlashEventSrc,
  ReserveDLC as ReserveDLCEventSrc,
  Staked as StakedEventSrc,
  Unstaked as UnstakedEventSrc,
  MoveToReserveAmount as MoveToReserveAmountEvent,
  BurnedInactiveRegionRewards as BurnedInactiveRegionRewardsEvent,
  BurnedInactiveSingleRegionRewards as BurnedInactiveSingleRegionRewardsEvent,
  MachineRegister as MachineRegisterEvent,
  MachineUnregister as MachineUnregisterEvent,
  RentMachine as RentMachineEvent,
  EndRentMachine as EndRentMachineEvent,
  ReportMachineFault as ReportMachineFaultEvent,
  SlashMachineOnOffline as SlashMachineOnOfflineEvent,
  AddBackCalcPointOnOnline as AddBackCalcPointOnOnlineEvent,
  ExitStakingForOffline as ExitStakingForOfflineEvent,
  RecoverRewarding as RecoverRewardingEvent,
  DepositReward as DepositRewardEventSrc,
  RewardsPerCalcPointUpdate as RewardsPerCalcPointUpdateEvent,
} from '../generated/NFTStaking/NFTStaking';
import {
  StateSummary,
  StakeHolder,
  MachineInfo,
  RegionInfo,
  RegionBurnInfo,
  ClaimedEvent,
  StakedEvent,
  UnstakedEvent,
  SlashEvent,
  MachineLifecycleEvent,
  DepositRewardEvent,
  RewardRateUpdateEvent,
  StateSummaryDaily,
  RegionDaily,
  HolderDaily,
} from '../generated/schema';

// -------------------- Helpers --------------------

const SECONDS_PER_DAY: i32 = 86400;

function eventLogId(event: ethereum.Event): Bytes {
  return event.transaction.hash.concatI32(event.logIndex.toI32());
}

function dayIdFromTimestamp(timestamp: BigInt): BigInt {
  return timestamp.div(BigInt.fromI32(SECONDS_PER_DAY));
}

function dayStartSeconds(timestamp: BigInt): BigInt {
  return dayIdFromTimestamp(timestamp).times(BigInt.fromI32(SECONDS_PER_DAY));
}

function dayBytes(dayId: BigInt): Bytes {
  // Fixed 8-byte big-endian encoding so composite IDs
  // (regionDayId / holderDayId) don't collide across day magnitudes.
  let d: i64 = dayId.toI64();
  let hi: i32 = i32(d >> 32);
  let lo: i32 = i32(d & 0xFFFFFFFF);
  return Bytes.fromByteArray(Bytes.empty().concatI32(hi).concatI32(lo));
}

function regionDayId(region: string, dayId: BigInt): Bytes {
  // keccak256 over (region_utf8 || day_8byte) — fixed-length hash avoids
  // variable-length collisions (e.g. "US"+0x4142 vs "USAB"+0x0000).
  let combined = Bytes.fromUTF8(region).concat(dayBytes(dayId));
  return Bytes.fromByteArray(crypto.keccak256(combined));
}

function holderDayId(holder: Bytes, dayId: BigInt): Bytes {
  // holder is a fixed 20-byte address so direct concat is safe,
  // but keccak for symmetry and insurance against address-wrapping changes.
  let combined = holder.concat(dayBytes(dayId));
  return Bytes.fromByteArray(crypto.keccak256(combined));
}

function loadOrCreateStateSummaryDaily(timestamp: BigInt): StateSummaryDaily {
  let day = dayIdFromTimestamp(timestamp);
  let id = dayBytes(day);
  let d = StateSummaryDaily.load(id);
  if (d == null) {
    d = new StateSummaryDaily(id);
    d.dayStartTimestamp = dayStartSeconds(timestamp);
    d.totalGPUCount = BigInt.zero();
    d.totalStakingGPUCount = BigInt.zero();
    d.totalBurnedReward = BigInt.zero();
    d.totalReservedAmount = BigInt.zero();
    d.totalCalcPoint = BigInt.zero();
    d.totalRegionCount = BigInt.zero();
    d.claimedAmountDelta = BigInt.zero();
    d.burnedRewardDelta = BigInt.zero();
    d.depositedRewardDelta = BigInt.zero();
    d.slashAmountDelta = BigInt.zero();
  }
  return d;
}

function snapshotStateSummaryDaily(timestamp: BigInt): void {
  let ss = StateSummary.load(Bytes.empty());
  if (ss == null) {
    return;
  }
  let d = loadOrCreateStateSummaryDaily(timestamp);
  d.totalGPUCount = ss.totalGPUCount;
  d.totalStakingGPUCount = ss.totalStakingGPUCount;
  d.totalBurnedReward = ss.totalBurnedReward;
  d.totalReservedAmount = ss.totalReservedAmount;
  d.totalCalcPoint = ss.totalCalcPoint;
  d.totalRegionCount = ss.totalRegionCount;
  d.save();
}

function loadOrCreateRegionDaily(region: string, timestamp: BigInt): RegionDaily {
  let day = dayIdFromTimestamp(timestamp);
  let id = regionDayId(region, day);
  let d = RegionDaily.load(id);
  if (d == null) {
    d = new RegionDaily(id);
    d.region = region;
    d.dayStartTimestamp = dayStartSeconds(timestamp);
    d.totalMachineCount = BigInt.zero();
    d.stakingMachineCount = BigInt.zero();
    d.totalBandwidth = BigInt.zero();
    d.stakingBandwidth = BigInt.zero();
    d.reservedAmount = BigInt.zero();
    d.burnedAmountDelta = BigInt.zero();
    d.claimedAmountDelta = BigInt.zero();
    d.slashAmountDelta = BigInt.zero();
  }
  return d;
}

function snapshotRegionDaily(region: string, timestamp: BigInt): void {
  if (region.length == 0) {
    return;
  }
  let ri = RegionInfo.load(Bytes.fromUTF8(region));
  if (ri == null) {
    return;
  }
  let d = loadOrCreateRegionDaily(region, timestamp);
  d.totalMachineCount = ri.totalMachineCount;
  d.stakingMachineCount = ri.stakingMachineCount;
  d.totalBandwidth = ri.totalBandwidth;
  d.stakingBandwidth = ri.stakingBandwidth;
  d.reservedAmount = ri.reservedAmount;
  d.save();
}

function loadOrCreateHolderDaily(holder: Bytes, timestamp: BigInt): HolderDaily {
  let day = dayIdFromTimestamp(timestamp);
  let id = holderDayId(holder, day);
  let d = HolderDaily.load(id);
  if (d == null) {
    d = new HolderDaily(id);
    d.holder = holder;
    d.dayStartTimestamp = dayStartSeconds(timestamp);
    d.totalClaimedRewardAmount = BigInt.zero();
    d.totalReleasedRewardAmount = BigInt.zero();
    d.claimedAmountDelta = BigInt.zero();
    d.activeMachineCount = BigInt.zero();
  }
  return d;
}

// -------------------- Existing handlers (preserved + event log writes) --------------------

export function handleClaimed(event: ClaimedEventSrc): void {
  // Event log written FIRST — unconditional, so it survives the early-return
  // paths below when an upstream entity is unexpectedly missing.
  let ce = new ClaimedEvent(eventLogId(event));
  ce.holder = event.params.stakeholder;
  ce.machineId = event.params.machineId;
  ce.totalRewardAmount = event.params.totalRewardAmount;
  ce.moveToUserWalletAmount = event.params.moveToUserWalletAmount;
  ce.moveToReservedAmount = event.params.moveToReservedAmount;
  ce.paidSlash = event.params.paidSlash;
  ce.blockNumber = event.block.number;
  ce.blockTimestamp = event.block.timestamp;
  ce.transactionHash = event.transaction.hash;
  ce.save();

  // Global daily delta — independent of MachineInfo/StakeHolder state.
  let dd = loadOrCreateStateSummaryDaily(event.block.timestamp);
  dd.claimedAmountDelta = dd.claimedAmountDelta.plus(event.params.totalRewardAmount);
  dd.save();

  // Holder daily delta — also independent (holder address always known).
  let hdd = loadOrCreateHolderDaily(event.params.stakeholder, event.block.timestamp);
  hdd.claimedAmountDelta = hdd.claimedAmountDelta.plus(event.params.totalRewardAmount);
  hdd.save();

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

  // Region daily delta (once we know the region from machineInfo).
  if (machineInfo.region.length > 0) {
    let rd = loadOrCreateRegionDaily(machineInfo.region, event.block.timestamp);
    rd.claimedAmountDelta = rd.claimedAmountDelta.plus(event.params.totalRewardAmount);
    rd.save();
  }

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
  stakeholder.save();

  // Refresh holder daily cumulative after stakeholder mutation.
  let hd = loadOrCreateHolderDaily(stakeholder.holder, event.block.timestamp);
  hd.totalClaimedRewardAmount = stakeholder.totalClaimedRewardAmount;
  hd.totalReleasedRewardAmount = stakeholder.totalReleasedRewardAmount;
  hd.save();

  // Global cumulative snapshot.
  snapshotStateSummaryDaily(event.block.timestamp);
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
    return;
  }
  regionInfo.reservedAmount = regionInfo.reservedAmount.plus(
    event.params.amount
  );
  regionInfo.save();

  snapshotStateSummaryDaily(event.block.timestamp);
  snapshotRegionDaily(machineInfo.region, event.block.timestamp);
}

export function handlePaySlash(event: PaySlashEventSrc): void {
  // Event log first — unconditional.
  let se = new SlashEvent(eventLogId(event));
  se.machineId = event.params.machineId;
  se.holder = event.params.to;
  se.slashAmount = event.params.slashAmount;
  se.kind = 'PAY_SLASH';
  se.blockNumber = event.block.number;
  se.blockTimestamp = event.block.timestamp;
  se.transactionHash = event.transaction.hash;
  se.save();

  // Global slash delta — independent of downstream state.
  let dd = loadOrCreateStateSummaryDaily(event.block.timestamp);
  dd.slashAmountDelta = dd.slashAmountDelta.plus(event.params.slashAmount);
  dd.save();

  let id = Bytes.fromUTF8(event.params.machineId.toString());
  let machineInfo = MachineInfo.load(id);
  if (machineInfo == null) {
    return;
  }

  machineInfo.totalReservedAmount = machineInfo.totalReservedAmount.minus(
    event.params.slashAmount
  );
  machineInfo.save();

  // Region accounting: missing in original v1 — caused region.reservedAmount
  // to drift from state/stakeholder and go negative on unstake. Fixed here.
  let regionInfo = RegionInfo.load(Bytes.fromUTF8(machineInfo.region));
  if (regionInfo !== null) {
    regionInfo.reservedAmount = regionInfo.reservedAmount.minus(
      event.params.slashAmount
    );
    regionInfo.save();

    // Region daily slash delta.
    let rd = loadOrCreateRegionDaily(machineInfo.region, event.block.timestamp);
    rd.slashAmountDelta = rd.slashAmountDelta.plus(event.params.slashAmount);
    rd.save();
  }

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

  snapshotStateSummaryDaily(event.block.timestamp);
  snapshotRegionDaily(machineInfo.region, event.block.timestamp);
}

export function handleReserveDLC(event: ReserveDLCEventSrc): void {
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
    // ReserveDLC without a prior Staked is a contract invariant violation;
    // we skip the aggregate mutation but keep the machineInfo update above.
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
    return;
  }
  regionInfo.reservedAmount = regionInfo.reservedAmount.plus(
    event.params.amount
  );
  regionInfo.save();

  snapshotStateSummaryDaily(event.block.timestamp);
  snapshotRegionDaily(machineInfo.region, event.block.timestamp);
}

export function handleStaked(event: StakedEventSrc): void {
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
    machineInfo.region = '';
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

  machineInfo.region = event.params.region;
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
  let regionWasDormant: boolean = false;
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
  } else if (regionInfo.stakingMachineCount.equals(BigInt.zero())) {
    // FIX: region existed but had no active stakers — re-entering the
    // "active region" set. Without this flag, totalRegionCount stays
    // permanently undercounted after a region goes 1 → 0 → 1.
    regionWasDormant = true;
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
  if (isNewRegion || regionWasDormant) {
    // FIX: v1 had `.minus(1)` here (sign flip) AND had no re-activation
    // branch, so `totalRegionCount` underflowed on each new region AND
    // stayed undercounted after any region went 1 → 0 → 1.
    stateSummary.totalRegionCount = stateSummary.totalRegionCount.plus(
      BigInt.fromI32(1)
    );
  }
  stateSummary.totalStakingGPUCount = stateSummary.totalStakingGPUCount.plus(
    BigInt.fromI32(1)
  );
  // FIX: use BigInt.equals to avoid toU32() truncation on large values.
  if (stakeholder.totalStakingGPUCount.equals(BigInt.fromI32(1))) {
    stateSummary.totalCalcPointPoolCount =
      stateSummary.totalCalcPointPoolCount.plus(BigInt.fromI32(1));
  }

  stateSummary.save();

  // HolderDaily active-machine count (after stakeholder increment above).
  let hd = loadOrCreateHolderDaily(stakeholder.holder, event.block.timestamp);
  hd.activeMachineCount = stakeholder.totalStakingGPUCount;
  hd.save();

  // Event log
  let ev = new StakedEvent(eventLogId(event));
  ev.holder = event.params.stakeholder;
  ev.machineId = event.params.machineId;
  ev.originCalcPoint = event.params.originCalcPoint;
  ev.calcPoint = event.params.calcPoint;
  ev.region = event.params.region;
  ev.blockNumber = event.block.number;
  ev.blockTimestamp = event.block.timestamp;
  ev.transactionHash = event.transaction.hash;
  ev.save();

  snapshotStateSummaryDaily(event.block.timestamp);
  snapshotRegionDaily(machineInfo.region, event.block.timestamp);
}

export function handleUnstaked(event: UnstakedEventSrc): void {
  // Event log first — survives the early-returns below.
  let ev = new UnstakedEvent(eventLogId(event));
  ev.holder = event.params.stakeholder;
  ev.machineId = event.params.machineId;
  ev.paybackReserveAmount = event.params.paybackReserveAmount;
  ev.blockNumber = event.block.number;
  ev.blockTimestamp = event.block.timestamp;
  ev.transactionHash = event.transaction.hash;
  ev.save();

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
  );

  regionInfo.save();

  // FIX: use BigInt.equals to avoid toI32/toU32 truncation on large values.
  if (regionInfo.stakingMachineCount.equals(BigInt.zero())) {
    stateSummary.totalRegionCount = stateSummary.totalRegionCount.minus(
      BigInt.fromI32(1)
    );
  }

  stateSummary.totalStakingGPUCount = stateSummary.totalStakingGPUCount.minus(
    BigInt.fromU32(1)
  );

  if (stakeholder.totalCalcPoint.equals(BigInt.zero())) {
    stateSummary.totalCalcPointPoolCount =
      stateSummary.totalCalcPointPoolCount.minus(BigInt.fromI32(1));
  }
  stateSummary.totalReservedAmount = stateSummary.totalReservedAmount.minus(
    machineInfo.totalReservedAmount
  );
  stateSummary.save();

  let priorRegion = machineInfo.region;

  machineInfo.totalReservedAmount = BigInt.zero();
  machineInfo.totalCalcPoint = BigInt.zero();
  machineInfo.fullTotalCalcPoint = BigInt.zero();
  machineInfo.totalCalcPointWithNFT = BigInt.zero();
  machineInfo.isStaking = false;
  machineInfo.online = false;
  machineInfo.registered = false;
  machineInfo.save();

  // HolderDaily active-machine count (after stakeholder decrement above).
  let hd = loadOrCreateHolderDaily(stakeholder.holder, event.block.timestamp);
  hd.activeMachineCount = stakeholder.totalStakingGPUCount;
  hd.save();

  snapshotStateSummaryDaily(event.block.timestamp);
  snapshotRegionDaily(priorRegion, event.block.timestamp);
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

  snapshotStateSummaryDaily(event.block.timestamp);
  let d = loadOrCreateStateSummaryDaily(event.block.timestamp);
  d.burnedRewardDelta = d.burnedRewardDelta.plus(event.params.amount);
  d.save();
}

export function handleBurnedInactiveSingleRegionRewards(
  event: BurnedInactiveSingleRegionRewardsEvent
): void {
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
    // FIX: v1 had `return;` here, silently dropping the burn for any region's
    // first-ever burn event. Fall through so the burn is recorded.
  }

  regionInfo.burnedAmount = regionInfo.burnedAmount.plus(event.params.amount);

  regionInfo.save();

  // FIX: use eventLogId to avoid collision when two regions burn in the same tx
  // (id used to be just the tx hash, so the later burn would overwrite the earlier).
  let regionBurnInfo = new RegionBurnInfo(eventLogId(event));
  regionBurnInfo.region = event.params.region;
  regionBurnInfo.burnedAmount = event.params.amount;
  regionBurnInfo.blockTimestamp = event.block.timestamp;
  regionBurnInfo.transactionHash = event.transaction.hash;
  regionBurnInfo.save();

  snapshotRegionDaily(event.params.region, event.block.timestamp);
  let rd = loadOrCreateRegionDaily(event.params.region, event.block.timestamp);
  rd.burnedAmountDelta = rd.burnedAmountDelta.plus(event.params.amount);
  rd.save();
}

// -------------------- New lifecycle handlers --------------------

function emitLifecycle(
  event: ethereum.Event,
  machineId: string,
  kind: string,
  actor: Bytes | null,
  calcPoint: BigInt | null,
  slashId: BigInt | null
): void {
  let ev = new MachineLifecycleEvent(eventLogId(event));
  ev.machineId = machineId;
  ev.kind = kind;
  if (actor !== null) ev.actor = actor as Bytes;
  if (calcPoint !== null) ev.calcPoint = calcPoint as BigInt;
  if (slashId !== null) ev.slashId = slashId as BigInt;
  ev.blockNumber = event.block.number;
  ev.blockTimestamp = event.block.timestamp;
  ev.transactionHash = event.transaction.hash;
  ev.save();
}

export function handleMachineRegister(event: MachineRegisterEvent): void {
  emitLifecycle(
    event,
    event.params.machineId,
    'REGISTER',
    null,
    event.params.calcPoint,
    null
  );
}

export function handleMachineUnregister(event: MachineUnregisterEvent): void {
  let mid = Bytes.fromUTF8(event.params.machineId);
  let machineInfo = MachineInfo.load(mid);
  if (machineInfo !== null) {
    machineInfo.registered = false;
    machineInfo.save();
  }
  emitLifecycle(
    event,
    event.params.machineId,
    'UNREGISTER',
    null,
    event.params.calcPoint,
    null
  );
}

export function handleRentMachine(event: RentMachineEvent): void {
  emitLifecycle(event, event.params.machineId, 'RENT_START', null, null, null);
}

export function handleEndRentMachine(event: EndRentMachineEvent): void {
  emitLifecycle(event, event.params.machineId, 'RENT_END', null, null, null);
}

export function handleReportMachineFault(event: ReportMachineFaultEvent): void {
  emitLifecycle(
    event,
    event.params.machineId,
    'FAULT_REPORT',
    event.params.renter,
    null,
    event.params.slashId
  );
}

export function handleSlashMachineOnOffline(
  event: SlashMachineOnOfflineEvent
): void {
  // Event log
  let se = new SlashEvent(eventLogId(event));
  se.machineId = event.params.machineId;
  se.holder = event.params.stakeHolder;
  se.slashAmount = event.params.slashAmount;
  se.kind = 'OFFLINE_SLASH';
  se.blockNumber = event.block.number;
  se.blockTimestamp = event.block.timestamp;
  se.transactionHash = event.transaction.hash;
  se.save();

  // Daily slash delta (independent of downstream state).
  let dd = loadOrCreateStateSummaryDaily(event.block.timestamp);
  dd.slashAmountDelta = dd.slashAmountDelta.plus(event.params.slashAmount);
  dd.save();

  let mid = Bytes.fromUTF8(event.params.machineId);
  let machineInfo = MachineInfo.load(mid);
  if (machineInfo !== null) {
    machineInfo.online = false;
    machineInfo.save();

    if (machineInfo.region.length > 0) {
      let rd = loadOrCreateRegionDaily(machineInfo.region, event.block.timestamp);
      rd.slashAmountDelta = rd.slashAmountDelta.plus(event.params.slashAmount);
      rd.save();
    }
  }

  emitLifecycle(
    event,
    event.params.machineId,
    'OFFLINE_SLASH',
    event.params.stakeHolder,
    null,
    null
  );
}

export function handleAddBackCalcPointOnOnline(
  event: AddBackCalcPointOnOnlineEvent
): void {
  let mid = Bytes.fromUTF8(event.params.machineId);
  let machineInfo = MachineInfo.load(mid);
  if (machineInfo !== null) {
    machineInfo.online = true;
    machineInfo.save();
  }
  emitLifecycle(
    event,
    event.params.machineId,
    'ONLINE_RECOVER',
    null,
    event.params.calcPoint,
    null
  );
}

export function handleExitStakingForOffline(
  event: ExitStakingForOfflineEvent
): void {
  emitLifecycle(
    event,
    event.params.machineId,
    'EXIT_FOR_OFFLINE',
    event.params.holder,
    null,
    null
  );
}

export function handleRecoverRewarding(event: RecoverRewardingEvent): void {
  emitLifecycle(
    event,
    event.params.machineId,
    'ONLINE_RECOVER',
    event.params.holder,
    null,
    null
  );
}

export function handleDepositReward(event: DepositRewardEventSrc): void {
  let ev = new DepositRewardEvent(eventLogId(event));
  ev.amount = event.params.amount;
  ev.blockNumber = event.block.number;
  ev.blockTimestamp = event.block.timestamp;
  ev.transactionHash = event.transaction.hash;
  ev.save();

  snapshotStateSummaryDaily(event.block.timestamp);
  let d = loadOrCreateStateSummaryDaily(event.block.timestamp);
  d.depositedRewardDelta = d.depositedRewardDelta.plus(event.params.amount);
  d.save();
}

export function handleRewardsPerCalcPointUpdate(
  event: RewardsPerCalcPointUpdateEvent
): void {
  let ev = new RewardRateUpdateEvent(eventLogId(event));
  ev.accumulatedPerShareBefore = event.params.accumulatedPerShareBefore;
  ev.accumulatedPerShareAfter = event.params.accumulatedPerShareAfter;
  ev.blockNumber = event.block.number;
  ev.blockTimestamp = event.block.timestamp;
  ev.transactionHash = event.transaction.hash;
  ev.save();
}

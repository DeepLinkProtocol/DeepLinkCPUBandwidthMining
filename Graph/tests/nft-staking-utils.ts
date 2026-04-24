import { newMockEvent } from 'matchstick-as';
import { ethereum, Address, BigInt } from '@graphprotocol/graph-ts';
import {
  Claimed,
  Staked,
  Unstaked,
  PaySlash,
  MachineRegister,
  MachineUnregister,
  RentMachine,
  EndRentMachine,
  ReportMachineFault,
  SlashMachineOnOffline,
  AddBackCalcPointOnOnline,
  ExitStakingForOffline,
  RecoverRewarding,
  DepositReward,
  RewardsPerCalcPointUpdate,
  BurnedInactiveRegionRewards,
  BurnedInactiveSingleRegionRewards,
} from '../generated/NFTStaking/NFTStaking';

export function createClaimedEvent(
  stakeholder: Address,
  machineId: string,
  totalRewardAmount: BigInt,
  moveToUserWalletAmount: BigInt,
  moveToReservedAmount: BigInt,
  paidSlash: boolean
): Claimed {
  let ev = changetype<Claimed>(newMockEvent());
  ev.parameters = new Array();
  ev.parameters.push(new ethereum.EventParam('stakeholder', ethereum.Value.fromAddress(stakeholder)));
  ev.parameters.push(new ethereum.EventParam('machineId', ethereum.Value.fromString(machineId)));
  ev.parameters.push(new ethereum.EventParam('totalRewardAmount', ethereum.Value.fromUnsignedBigInt(totalRewardAmount)));
  ev.parameters.push(new ethereum.EventParam('moveToUserWalletAmount', ethereum.Value.fromUnsignedBigInt(moveToUserWalletAmount)));
  ev.parameters.push(new ethereum.EventParam('moveToReservedAmount', ethereum.Value.fromUnsignedBigInt(moveToReservedAmount)));
  ev.parameters.push(new ethereum.EventParam('paidSlash', ethereum.Value.fromBoolean(paidSlash)));
  return ev;
}

export function createStakedEvent(
  stakeholder: Address,
  machineId: string,
  originCalcPoint: BigInt,
  calcPoint: BigInt,
  region: string
): Staked {
  let ev = changetype<Staked>(newMockEvent());
  ev.parameters = new Array();
  ev.parameters.push(new ethereum.EventParam('stakeholder', ethereum.Value.fromAddress(stakeholder)));
  ev.parameters.push(new ethereum.EventParam('machineId', ethereum.Value.fromString(machineId)));
  ev.parameters.push(new ethereum.EventParam('originCalcPoint', ethereum.Value.fromUnsignedBigInt(originCalcPoint)));
  ev.parameters.push(new ethereum.EventParam('calcPoint', ethereum.Value.fromUnsignedBigInt(calcPoint)));
  ev.parameters.push(new ethereum.EventParam('region', ethereum.Value.fromString(region)));
  return ev;
}

export function createUnstakedEvent(
  stakeholder: Address,
  machineId: string,
  paybackReserveAmount: BigInt
): Unstaked {
  let ev = changetype<Unstaked>(newMockEvent());
  ev.parameters = new Array();
  ev.parameters.push(new ethereum.EventParam('stakeholder', ethereum.Value.fromAddress(stakeholder)));
  ev.parameters.push(new ethereum.EventParam('machineId', ethereum.Value.fromString(machineId)));
  ev.parameters.push(new ethereum.EventParam('paybackReserveAmount', ethereum.Value.fromUnsignedBigInt(paybackReserveAmount)));
  return ev;
}

export function createPaySlashEvent(
  machineId: string,
  to: Address,
  slashAmount: BigInt
): PaySlash {
  let ev = changetype<PaySlash>(newMockEvent());
  ev.parameters = new Array();
  ev.parameters.push(new ethereum.EventParam('machineId', ethereum.Value.fromString(machineId)));
  ev.parameters.push(new ethereum.EventParam('to', ethereum.Value.fromAddress(to)));
  ev.parameters.push(new ethereum.EventParam('slashAmount', ethereum.Value.fromUnsignedBigInt(slashAmount)));
  return ev;
}

export function createMachineRegisterEvent(
  machineId: string,
  calcPoint: BigInt
): MachineRegister {
  let ev = changetype<MachineRegister>(newMockEvent());
  ev.parameters = new Array();
  ev.parameters.push(new ethereum.EventParam('machineId', ethereum.Value.fromString(machineId)));
  ev.parameters.push(new ethereum.EventParam('calcPoint', ethereum.Value.fromUnsignedBigInt(calcPoint)));
  return ev;
}

export function createMachineUnregisterEvent(
  machineId: string,
  calcPoint: BigInt
): MachineUnregister {
  let ev = changetype<MachineUnregister>(newMockEvent());
  ev.parameters = new Array();
  ev.parameters.push(new ethereum.EventParam('machineId', ethereum.Value.fromString(machineId)));
  ev.parameters.push(new ethereum.EventParam('calcPoint', ethereum.Value.fromUnsignedBigInt(calcPoint)));
  return ev;
}

export function createRentMachineEvent(machineId: string): RentMachine {
  let ev = changetype<RentMachine>(newMockEvent());
  ev.parameters = new Array();
  ev.parameters.push(new ethereum.EventParam('machineId', ethereum.Value.fromString(machineId)));
  return ev;
}

export function createEndRentMachineEvent(machineId: string): EndRentMachine {
  let ev = changetype<EndRentMachine>(newMockEvent());
  ev.parameters = new Array();
  ev.parameters.push(new ethereum.EventParam('machineId', ethereum.Value.fromString(machineId)));
  return ev;
}

export function createReportMachineFaultEvent(
  machineId: string,
  slashId: BigInt,
  renter: Address
): ReportMachineFault {
  let ev = changetype<ReportMachineFault>(newMockEvent());
  ev.parameters = new Array();
  ev.parameters.push(new ethereum.EventParam('machineId', ethereum.Value.fromString(machineId)));
  ev.parameters.push(new ethereum.EventParam('slashId', ethereum.Value.fromUnsignedBigInt(slashId)));
  ev.parameters.push(new ethereum.EventParam('renter', ethereum.Value.fromAddress(renter)));
  return ev;
}

export function createSlashMachineOnOfflineEvent(
  stakeHolder: Address,
  machineId: string,
  slashAmount: BigInt
): SlashMachineOnOffline {
  let ev = changetype<SlashMachineOnOffline>(newMockEvent());
  ev.parameters = new Array();
  ev.parameters.push(new ethereum.EventParam('stakeHolder', ethereum.Value.fromAddress(stakeHolder)));
  ev.parameters.push(new ethereum.EventParam('machineId', ethereum.Value.fromString(machineId)));
  ev.parameters.push(new ethereum.EventParam('slashAmount', ethereum.Value.fromUnsignedBigInt(slashAmount)));
  return ev;
}

export function createAddBackCalcPointOnOnlineEvent(
  machineId: string,
  calcPoint: BigInt
): AddBackCalcPointOnOnline {
  let ev = changetype<AddBackCalcPointOnOnline>(newMockEvent());
  ev.parameters = new Array();
  ev.parameters.push(new ethereum.EventParam('machineId', ethereum.Value.fromString(machineId)));
  ev.parameters.push(new ethereum.EventParam('calcPoint', ethereum.Value.fromUnsignedBigInt(calcPoint)));
  return ev;
}

export function createExitStakingForOfflineEvent(
  machineId: string,
  holder: Address
): ExitStakingForOffline {
  let ev = changetype<ExitStakingForOffline>(newMockEvent());
  ev.parameters = new Array();
  ev.parameters.push(new ethereum.EventParam('machineId', ethereum.Value.fromString(machineId)));
  ev.parameters.push(new ethereum.EventParam('holder', ethereum.Value.fromAddress(holder)));
  return ev;
}

export function createRecoverRewardingEvent(
  machineId: string,
  holder: Address
): RecoverRewarding {
  let ev = changetype<RecoverRewarding>(newMockEvent());
  ev.parameters = new Array();
  ev.parameters.push(new ethereum.EventParam('machineId', ethereum.Value.fromString(machineId)));
  ev.parameters.push(new ethereum.EventParam('holder', ethereum.Value.fromAddress(holder)));
  return ev;
}

export function createDepositRewardEvent(amount: BigInt): DepositReward {
  let ev = changetype<DepositReward>(newMockEvent());
  ev.parameters = new Array();
  ev.parameters.push(new ethereum.EventParam('amount', ethereum.Value.fromUnsignedBigInt(amount)));
  return ev;
}

export function createRewardsPerCalcPointUpdateEvent(
  before: BigInt,
  after: BigInt
): RewardsPerCalcPointUpdate {
  let ev = changetype<RewardsPerCalcPointUpdate>(newMockEvent());
  ev.parameters = new Array();
  ev.parameters.push(new ethereum.EventParam('accumulatedPerShareBefore', ethereum.Value.fromUnsignedBigInt(before)));
  ev.parameters.push(new ethereum.EventParam('accumulatedPerShareAfter', ethereum.Value.fromUnsignedBigInt(after)));
  return ev;
}

export function createBurnedInactiveRegionRewardsEvent(amount: BigInt): BurnedInactiveRegionRewards {
  let ev = changetype<BurnedInactiveRegionRewards>(newMockEvent());
  ev.parameters = new Array();
  ev.parameters.push(new ethereum.EventParam('amount', ethereum.Value.fromUnsignedBigInt(amount)));
  return ev;
}

export function createBurnedInactiveSingleRegionRewardsEvent(
  region: string,
  amount: BigInt
): BurnedInactiveSingleRegionRewards {
  let ev = changetype<BurnedInactiveSingleRegionRewards>(newMockEvent());
  ev.parameters = new Array();
  ev.parameters.push(new ethereum.EventParam('region', ethereum.Value.fromString(region)));
  ev.parameters.push(new ethereum.EventParam('amount', ethereum.Value.fromUnsignedBigInt(amount)));
  return ev;
}

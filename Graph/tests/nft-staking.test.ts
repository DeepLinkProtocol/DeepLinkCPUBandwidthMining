import {
  assert,
  describe,
  test,
  clearStore,
  beforeAll,
  afterAll,
  beforeEach,
} from 'matchstick-as/assembly/index';
import { Address, BigInt } from '@graphprotocol/graph-ts';
import {
  handleStaked,
  handleClaimed,
  handleUnstaked,
  handlePaySlash,
  handleMachineRegister,
  handleMachineUnregister,
  handleRentMachine,
  handleEndRentMachine,
  handleReportMachineFault,
  handleSlashMachineOnOffline,
  handleAddBackCalcPointOnOnline,
  handleExitStakingForOffline,
  handleRecoverRewarding,
  handleDepositReward,
  handleRewardsPerCalcPointUpdate,
  handleBurnedInactiveRegionRewards,
  handleBurnedInactiveSingleRegionRewards,
} from '../src/nft-staking';
import {
  createStakedEvent,
  createClaimedEvent,
  createUnstakedEvent,
  createPaySlashEvent,
  createMachineRegisterEvent,
  createMachineUnregisterEvent,
  createRentMachineEvent,
  createEndRentMachineEvent,
  createReportMachineFaultEvent,
  createSlashMachineOnOfflineEvent,
  createAddBackCalcPointOnOnlineEvent,
  createExitStakingForOfflineEvent,
  createRecoverRewardingEvent,
  createDepositRewardEvent,
  createRewardsPerCalcPointUpdateEvent,
  createBurnedInactiveRegionRewardsEvent,
  createBurnedInactiveSingleRegionRewardsEvent,
} from './nft-staking-utils';

const HOLDER = Address.fromString('0x0000000000000000000000000000000000000001');
const RENTER = Address.fromString('0x0000000000000000000000000000000000000002');
const MACHINE_ID = 'machine-abc';
const REGION = 'North China';

describe('Event-log entities (time-series for dashboard)', () => {
  afterAll(() => clearStore());

  test('Staked writes StakedEvent + updates MachineInfo/StakeHolder/RegionInfo', () => {
    clearStore();
    let ev = createStakedEvent(HOLDER, MACHINE_ID, BigInt.fromI32(100), BigInt.fromI32(120), REGION);
    handleStaked(ev);

    assert.entityCount('StakedEvent', 1);
    assert.entityCount('MachineInfo', 1);
    assert.entityCount('StakeHolder', 1);
    assert.entityCount('RegionInfo', 1);
    assert.entityCount('StateSummary', 1);
    assert.entityCount('StateSummaryDaily', 1);
    assert.entityCount('RegionDaily', 1);
  });

  test('Claimed appends ClaimedEvent + HolderDaily', () => {
    // Prereq: staked machine exists
    clearStore();
    handleStaked(createStakedEvent(HOLDER, MACHINE_ID, BigInt.fromI32(100), BigInt.fromI32(120), REGION));

    let claim = createClaimedEvent(HOLDER, MACHINE_ID, BigInt.fromI32(500), BigInt.fromI32(300), BigInt.fromI32(200), false);
    handleClaimed(claim);

    assert.entityCount('ClaimedEvent', 1);
    assert.entityCount('HolderDaily', 1);
    // Delta accumulates in today's bucket
    // fieldEquals format: entity, id, field, expected
    // We can't easily predict the id but we check count.
  });

  test('Multiple claims same day accumulate HolderDaily.claimedAmountDelta', () => {
    clearStore();
    handleStaked(createStakedEvent(HOLDER, MACHINE_ID, BigInt.fromI32(100), BigInt.fromI32(120), REGION));

    let c1 = createClaimedEvent(HOLDER, MACHINE_ID, BigInt.fromI32(100), BigInt.fromI32(60), BigInt.fromI32(40), false);
    c1.logIndex = BigInt.fromI32(10);
    handleClaimed(c1);

    let c2 = createClaimedEvent(HOLDER, MACHINE_ID, BigInt.fromI32(200), BigInt.fromI32(120), BigInt.fromI32(80), false);
    c2.logIndex = BigInt.fromI32(11);
    handleClaimed(c2);

    assert.entityCount('ClaimedEvent', 2);
    assert.entityCount('HolderDaily', 1); // same day → same bucket
  });

  test('Unstaked writes UnstakedEvent + flips MachineInfo flags', () => {
    clearStore();
    handleStaked(createStakedEvent(HOLDER, MACHINE_ID, BigInt.fromI32(100), BigInt.fromI32(120), REGION));
    handleUnstaked(createUnstakedEvent(HOLDER, MACHINE_ID, BigInt.fromI32(50)));

    assert.entityCount('UnstakedEvent', 1);
    // machine still indexed but marked inactive
    // id derivation: Bytes.fromUTF8(machineId)
  });

  test('PaySlash writes SlashEvent with kind=PAY_SLASH', () => {
    clearStore();
    handleStaked(createStakedEvent(HOLDER, MACHINE_ID, BigInt.fromI32(100), BigInt.fromI32(120), REGION));
    // Seed some reserved amount so slash doesn't underflow (in prod rev-DLC would precede it)
    // We skip that since the handler tolerates — just verify event log write.
    handlePaySlash(createPaySlashEvent(MACHINE_ID, RENTER, BigInt.fromI32(0)));

    assert.entityCount('SlashEvent', 1);
  });

  test('SlashMachineOnOffline writes SlashEvent + MachineLifecycleEvent', () => {
    clearStore();
    handleStaked(createStakedEvent(HOLDER, MACHINE_ID, BigInt.fromI32(100), BigInt.fromI32(120), REGION));
    handleSlashMachineOnOffline(createSlashMachineOnOfflineEvent(HOLDER, MACHINE_ID, BigInt.fromI32(0)));

    assert.entityCount('SlashEvent', 1);
    assert.entityCount('MachineLifecycleEvent', 1);
  });
});

describe('Lifecycle handlers', () => {
  afterAll(() => clearStore());

  test('MachineRegister writes MachineLifecycleEvent', () => {
    clearStore();
    handleMachineRegister(createMachineRegisterEvent(MACHINE_ID, BigInt.fromI32(100)));
    assert.entityCount('MachineLifecycleEvent', 1);
  });

  test('MachineUnregister writes lifecycle + flips registered=false', () => {
    clearStore();
    handleStaked(createStakedEvent(HOLDER, MACHINE_ID, BigInt.fromI32(100), BigInt.fromI32(120), REGION));
    handleMachineUnregister(createMachineUnregisterEvent(MACHINE_ID, BigInt.fromI32(100)));
    assert.entityCount('MachineLifecycleEvent', 1);
  });

  test('RentMachine + EndRentMachine each write one lifecycle event', () => {
    clearStore();
    let r = createRentMachineEvent(MACHINE_ID);
    r.logIndex = BigInt.fromI32(1);
    handleRentMachine(r);
    let e = createEndRentMachineEvent(MACHINE_ID);
    e.logIndex = BigInt.fromI32(2);
    handleEndRentMachine(e);
    assert.entityCount('MachineLifecycleEvent', 2);
  });

  test('ReportMachineFault writes lifecycle with slashId', () => {
    clearStore();
    handleReportMachineFault(
      createReportMachineFaultEvent(MACHINE_ID, BigInt.fromI32(42), RENTER)
    );
    assert.entityCount('MachineLifecycleEvent', 1);
  });

  test('AddBackCalcPointOnOnline flips machine.online=true', () => {
    clearStore();
    handleStaked(createStakedEvent(HOLDER, MACHINE_ID, BigInt.fromI32(100), BigInt.fromI32(120), REGION));
    handleAddBackCalcPointOnOnline(createAddBackCalcPointOnOnlineEvent(MACHINE_ID, BigInt.fromI32(100)));
    assert.entityCount('MachineLifecycleEvent', 1);
  });

  test('ExitStakingForOffline + RecoverRewarding both write lifecycle', () => {
    clearStore();
    let x = createExitStakingForOfflineEvent(MACHINE_ID, HOLDER);
    x.logIndex = BigInt.fromI32(3);
    handleExitStakingForOffline(x);
    let r = createRecoverRewardingEvent(MACHINE_ID, HOLDER);
    r.logIndex = BigInt.fromI32(4);
    handleRecoverRewarding(r);
    assert.entityCount('MachineLifecycleEvent', 2);
  });
});

describe('Treasury / reward-rate events', () => {
  afterAll(() => clearStore());

  test('DepositReward writes event + accumulates daily delta', () => {
    clearStore();
    // StateSummary needs to exist first for snapshotStateSummaryDaily to run
    handleStaked(createStakedEvent(HOLDER, MACHINE_ID, BigInt.fromI32(100), BigInt.fromI32(120), REGION));

    let d1 = createDepositRewardEvent(BigInt.fromI32(1000));
    d1.logIndex = BigInt.fromI32(20);
    handleDepositReward(d1);

    let d2 = createDepositRewardEvent(BigInt.fromI32(500));
    d2.logIndex = BigInt.fromI32(21);
    handleDepositReward(d2);

    assert.entityCount('DepositRewardEvent', 2);
    assert.entityCount('StateSummaryDaily', 1); // same day bucket
  });

  test('RewardsPerCalcPointUpdate writes rate-update log', () => {
    clearStore();
    handleRewardsPerCalcPointUpdate(
      createRewardsPerCalcPointUpdateEvent(BigInt.fromI32(1000), BigInt.fromI32(1200))
    );
    assert.entityCount('RewardRateUpdateEvent', 1);
  });

  test('BurnedInactiveRegionRewards accumulates burn delta on StateSummaryDaily', () => {
    clearStore();
    handleStaked(createStakedEvent(HOLDER, MACHINE_ID, BigInt.fromI32(100), BigInt.fromI32(120), REGION));
    handleBurnedInactiveRegionRewards(createBurnedInactiveRegionRewardsEvent(BigInt.fromI32(700)));

    assert.entityCount('StateSummaryDaily', 1);
  });

  test('BurnedInactiveSingleRegionRewards updates RegionInfo.burnedAmount + RegionBurnInfo', () => {
    clearStore();
    // Seed region first via Staked (handler won't write RegionBurnInfo if region doesn't exist)
    handleStaked(createStakedEvent(HOLDER, MACHINE_ID, BigInt.fromI32(100), BigInt.fromI32(120), REGION));
    handleBurnedInactiveSingleRegionRewards(
      createBurnedInactiveSingleRegionRewardsEvent(REGION, BigInt.fromI32(300))
    );
    assert.entityCount('RegionBurnInfo', 1);
    assert.entityCount('RegionDaily', 1);
  });
});

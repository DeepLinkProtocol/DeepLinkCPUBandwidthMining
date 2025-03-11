// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interface/IRewardToken.sol";
import "./interface/IRentContract.sol";
import "./interface/IDBCAIContract.sol";
import "./interface/ITool.sol";
import "forge-std/console.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./library/RewardCalculatorLib.sol";
import {NFTStakingState} from "./NFTStakingState.sol";
import {RewardCalculator} from "./RewardCalculater.sol";

/// @custom:oz-upgrades-from OldBandWidthStaking
contract BandWidthStaking is
    RewardCalculator,
    NFTStakingState,
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    IERC1155Receiver
{
    string public constant PROJECT_NAME = "DeepLink BandWidth";
    uint8 public constant SECONDS_PER_BLOCK = 6;
    uint256 public constant BASE_RESERVE_AMOUNT = 10_000 ether;
    StakingType public constant STAKING_TYPE = StakingType.Free;

    IDBCAIContract public dbcAIContract;
    ITool public toolContract;
    IERC1155 public nftToken;
    IRewardToken public rewardToken;

    address public canUpgradeAddress;

    uint256 public totalRegionValue;
    uint256 public totalDistributedRewardAmount;
    uint256 public totalBurnedRewardAmount;

    uint256 public lastBurnTime;
    string[] public regions;

    enum StakingType {
        ShortTerm,
        LongTerm,
        Free
    }

    struct ApprovedReportInfo {
        address renter;
    }

    struct StakeInfo {
        address holder;
        uint256 startAtTimestamp;
        uint256 lastClaimAtTimestamp;
        uint256 endAtTimestamp;
        uint256 calcPoint;
        uint256 reservedAmount;
        uint256[] nftTokenIds;
        uint256[] tokenIdBalances;
        uint256 nftCount;
        uint256 claimedAmount;
        bool isRentedByUser;
        uint256 gpuCount;
        uint256 nextRenterCanRentAt;
    }

    struct RegionStakeInfo {
        uint256 stakedMachineCount;
        uint256 lastUnStakeTime;
    }

    mapping(address => bool) public dlcClientWalletAddress;

    mapping(address => string[]) public holder2MachineIds;

    mapping(string => ApprovedReportInfo[]) private pendingSlashedMachineId2Renter;

    mapping(string => StakeInfo) public machineId2StakeInfos;

    mapping(string => uint256) public region2Value;
    mapping(string => RegionStakeInfo) public region2StakeInfo;

    event Staked(address indexed stakeholder, string machineId, uint256 originCalcPoint, uint256 calcPoint);
    event AddedStakeHours(address indexed stakeholder, string machineId, uint256 stakeHours);

    event ReserveDLC(string machineId, uint256 amount);
    event Unstaked(address indexed stakeholder, string machineId,uint256 paybackReserveAmount);
    event Claimed(
        address indexed stakeholder,
        string machineId,
        uint256 totalRewardAmount,
        uint256 moveToUserWalletAmount,
        uint256 moveToReservedAmount,
        bool paidSlash
    );

    //    event AddNFTs(string machineId, uint256[] nftTokenIds);
    event PaySlash(string machineId, address renter, uint256 slashAmount);
    event RentMachine(string machineId);
    event EndRentMachine(string machineId);
    event ReportMachineFault(string machineId, address renter);
    event BurnedInactiveRegionRewards(uint256 amount);
    event DepositReward(uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function onERC1155BatchReceived(
        address, /* unusedParameter */
        address, /* unusedParameter */
        uint256[] calldata, /* unusedParameter */
        uint256[] calldata, /* unusedParameter */
        bytes calldata /* unusedParameter */
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function onERC1155Received(
        address, /* unusedParameter */
        address, /* unusedParameter */
        uint256, /* unusedParameter */
        uint256, /* unusedParameter */
        bytes calldata /* unusedParameter */
    ) external pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }

    modifier onlyRentContractOrThis() {
        require(
            msg.sender == address(rentContract) || msg.sender == address(this),
            "only rent contract or this can call this function"
        );
        _;
    }

    modifier onlyRentContract() {
        require(msg.sender == address(rentContract), "only rent contract can call this function");
        _;
    }

    function initialize(
        address _initialOwner,
        address _nftToken,
        address _rewardToken,
        address _rentContract,
        address _dbcAIContract,
        address _toolContract,
        uint8 phaseLevel
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();

        rewardToken = IRewardToken(_rewardToken);
        nftToken = IERC1155(_nftToken);
        rentContract = IRentContract(_rentContract);
        dbcAIContract = IDBCAIContract(_dbcAIContract);

        if (phaseLevel == 1) {
            rewardStartGPUThreshold = 500;
        }
        if (phaseLevel == 2) {
            rewardStartGPUThreshold = 1000;
        }
        if (phaseLevel == 3) {
            rewardStartGPUThreshold = 2000;
        }
        setToolContract(ITool(_toolContract));

        uint256 currentTime = block.timestamp;
        rewardsPerCalcPoint.lastUpdated = currentTime;
        rewardStartAtTimestamp = currentTime;
        lastBurnTime = currentTime;

        setRegions();
    }

    function setToolContract(ITool _toolContract) internal onlyOwner {
        toolContract = _toolContract;
    }

    function setThreshold(uint256 _threshold) public onlyOwner {
        rewardStartGPUThreshold = _threshold;
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        require(newImplementation != address(0), "new implementation is the zero address");
        require(msg.sender == canUpgradeAddress, "only canUpgradeAddress can authorize upgrade");
    }

    function setUpgradeAddress(address addr) external onlyOwner {
        canUpgradeAddress = addr;
    }

    function requestUpgradeAddress(address addr) external pure returns (bytes memory) {
        bytes memory data = abi.encodeWithSignature("setUpgradeAddress(address)", addr);
        return data;
    }

    function setRewardToken(address token) external onlyOwner {
        rewardToken = IRewardToken(token);
    }

    function setRentContract(address _rentContract) external onlyOwner {
        rentContract = IRentContract(_rentContract);
    }

    function setNftToken(address token) external onlyOwner {
        nftToken = IERC1155(token);
    }

    function setRewardStartAt(uint256 timestamp) external onlyOwner {
        require(timestamp >= block.timestamp, "time must be greater than current block number");
        rewardStartAtTimestamp = timestamp;
    }

    function setDLCClientWallets(address[] calldata addrs) external onlyOwner {
        for (uint256 i = 0; i < addrs.length; i++) {
            require(addrs[i] != address(0), "address is zero");
            require(dlcClientWalletAddress[addrs[i]] == false, "address already added");
            dlcClientWalletAddress[addrs[i]] = true;
        }
    }

    function setDBCAIContract(address addr) external onlyOwner {
        dbcAIContract = IDBCAIContract(addr);
    }

    function setRegions() internal {
        totalRegionValue = 547000;
        regions = [
            "North China",
            "Northeast China",
            "East China",
            "Central China",
            "South China",
            "Southwest China",
            "Northwest China",
            "Taiwan, China",
            "Hong Kong, China",
            "Uttar Pradesh",
            "Maharashtra",
            "Bihar",
            "Indonesia",
            "Pakistan",
            "Bangladesh",
            "Japan",
            "Philippines",
            "Vietnam",
            "Turkey",
            "Thailand",
            "South Korea",
            "Malaysia",
            "Saudi Arabia",
            "United Arab Emirates",
            "California",
            "Texas",
            "Florida",
            "New York",
            "Pennsylvania",
            "Illinois",
            "Ohio",
            "Georgia",
            "Michigan",
            "North Carolina",
            "Other Regions of the USA",
            "Mexico",
            "Canada",
            "Brazil",
            "Colombia",
            "Argentina",
            "Moscow",
            "Saint Petersburg",
            "Other parts of Russia",
            "Germany",
            "United Kingdom",
            "France",
            "Italy",
            "Spain",
            "Netherlands",
            "Switzerland",
            "Nigeria",
            "Egypt",
            "South Africa",
            "Australia"
        ];

        // 289000
        region2Value["North China"] = 50000;
        region2Value["Northeast China"] = 15000;
        region2Value["East China"] = 60000;
        region2Value["Central China"] = 50000;
        region2Value["South China"] = 50000;
        region2Value["Southwest China"] = 40000;
        region2Value["Northwest China"] = 20000;
        region2Value["Taiwan, China"] = 3000;
        region2Value["Hong Kong, China"] = 1000;

        // 4000
        region2Value["Uttar Pradesh"] = 2000;
        region2Value["Maharashtra"] = 1000;
        region2Value["Bihar"] = 1000;

        // 135,000
        region2Value["Indonesia"] = 3000;
        region2Value["Pakistan"] = 2000;
        region2Value["Bangladesh"] = 2000;
        region2Value["Japan"] = 50000;
        region2Value["Philippines"] = 1000;
        region2Value["Vietnam"] = 3000;
        region2Value["Turkey"] = 5000;
        region2Value["Thailand"] = 8000;
        region2Value["South Korea"] = 50000;
        region2Value["Malaysia"] = 3000;
        region2Value["Saudi Arabia"] = 6000;
        region2Value["United Arab Emirates"] = 2000;

        // 44000
        region2Value["California"] = 8000;
        region2Value["Texas"] = 6000;
        region2Value["Florida"] = 4000;
        region2Value["New York"] = 4000;
        region2Value["Pennsylvania"] = 3000;
        region2Value["Illinois"] = 3000;
        region2Value["Ohio"] = 2000;
        region2Value["Georgia"] = 2000;
        region2Value["Michigan"] = 2000;
        region2Value["North Carolina"] = 2000;
        region2Value["Other Regions of the USA"] = 8000;

        //13000
        region2Value["Mexico"] = 2000;
        region2Value["Canada"] = 3000;
        region2Value["Brazil"] = 5000;
        region2Value["Colombia"] = 1000;
        region2Value["Argentina"] = 2000;

        // 5000
        region2Value["Moscow"] = 2000;
        region2Value["Saint Petersburg"] = 1000;
        region2Value["Other parts of Russia"] = 2000;

        // 46000
        region2Value["Germany"] = 9000;
        region2Value["United Kingdom"] = 9000;
        region2Value["France"] = 9000;
        region2Value["Italy"] = 6000;
        region2Value["Spain"] = 6000;
        region2Value["Netherlands"] = 5000;
        region2Value["Switzerland"] = 2000;

        // 11000
        region2Value["Nigeria"] = 2000;
        region2Value["Egypt"] = 2000;
        region2Value["South Africa"] = 2000;
        region2Value["Australia"] = 5000;

        uint256 totalValue;
        for (uint256 i = 0; i < regions.length; i++) {
            totalValue += region2Value[regions[i]];
        }
        require(totalValue == totalRegionValue, "total value is not correct");
    }

    function getMachineRegion(string memory machineId) public view returns (string memory, uint256) {
        string memory machineRegion = dbcAIContract.getMachineRegion(machineId);
        uint256 machineValue = region2Value[machineRegion];
        return (machineRegion, machineValue);
    }

    function getInactiveRegionRewards() public view returns (uint256) {
        uint256 durationInactiveReward = 0;

        for (uint256 i = 0; i < regions.length; i++) {
            string memory region = regions[i];
            RegionStakeInfo memory info = region2StakeInfo[region];
            uint256 duration = block.timestamp - lastBurnTime;
            if (info.stakedMachineCount == 0 && block.timestamp >= info.lastUnStakeTime + duration) {
                uint256 regionValue = region2Value[region];
                uint256 dailyRegionRewardAmount = getDailyRewardAmount() * regionValue / totalRegionValue;
                durationInactiveReward += (duration * dailyRegionRewardAmount / 1 days);
            }
        }
        return durationInactiveReward;
    }

    function burnInactiveRegionRewards() external {
        uint256 durationInactiveReward = getInactiveRegionRewards();
        totalBurnedRewardAmount += durationInactiveReward;
        rewardToken.approve(address(this), durationInactiveReward);
        rewardToken.burnFrom(address(this), durationInactiveReward);
        lastBurnTime = block.timestamp;
        emit BurnedInactiveRegionRewards(durationInactiveReward);
    }

    function _tryInitMachineLockRewardInfo(string memory machineId, uint256 currentTime) internal {
        if (machineId2LockedRewardDetail[machineId].lockTime == 0) {
            machineId2LockedRewardDetail[machineId] = LockedRewardDetail({
                totalAmount: 0,
                lockTime: currentTime,
                unlockTime: currentTime + LOCK_PERIOD,
                claimedAmount: 0
            });
        }
    }

    function getMaxNFTCountCanStake() public view returns (uint256) {
        uint256 timestamp = block.timestamp;
        require(timestamp >= rewardStartAtTimestamp, "Timestamp must be after start time");
        uint256 daysElapsed = (timestamp - rewardStartAtTimestamp) / 1 days;

        uint256 limit;
        if (daysElapsed < 300) {
            limit = 20; // 0 ~ 299 days
        } else if (daysElapsed < 600) {
            limit = 10; // 300 ~ 599 days
        } else if (daysElapsed < 900) {
            limit = 5; // 600 ~ 899 days
        } else if (daysElapsed < 1200) {
            limit = 2; // 900 ~ 1199 days
        } else {
            // >1200
            limit = 1;
        }
        return limit;
    }

    function addDLCToStake(string memory machineId, uint256 amount) external nonReentrant {
        require(isStaking(machineId), "machine not staked");
        if (amount == 0) {
            return;
        }
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];

        ApprovedReportInfo[] memory approvedReportInfos = pendingSlashedMachineId2Renter[machineId];

        if (approvedReportInfos.length > 0) {
            require(
                amount >= BASE_RESERVE_AMOUNT * approvedReportInfos.length, "amount must be greater than slash amount"
            );
            for (uint8 i = 0; i < approvedReportInfos.length; i++) {
                // pay slash to renters
                payToRenterForSlashing(machineId, stakeInfo, approvedReportInfos[i].renter, false);
                amount -= BASE_RESERVE_AMOUNT;
            }
            delete pendingSlashedMachineId2Renter[machineId];
        }

        _joinStaking(machineId, stakeInfo.calcPoint, amount + stakeInfo.reservedAmount);
        NFTStakingState.addReserveAmount(machineId, stakeInfo.holder, amount);
        emit ReserveDLC(machineId, amount);
    }

    function revertIfMachineInfoCanNotStake(uint256 calcPoint, string memory gpuType, uint256 mem) internal view {
        require(mem >= 16, "memory size must greater than or equal to 16G");
        require(toolContract.checkString(gpuType), "gpu type not match");
        require(calcPoint > 0, "machine calc point not found");
    }

    function stake(
        address stakeholder,
        string calldata machineId,
        uint256[] calldata nftTokenIds,
        uint256[] calldata nftTokenIdBalances
    ) external nonReentrant {
        (address machineOwner, uint256 calcPoint, uint256 cpuRate, string memory gpuType,,,,, uint256 mem) =
            dbcAIContract.getMachineInfo(machineId, true);

        require(dbcAIContract.freeGpuAmount(machineId) >= 1, "machine not stake enough dbc");
        require(nftTokenIds.length == nftTokenIdBalances.length, "nft token ids and balances length not match");

        require(mem >= 16, "memory size must greater than or equal to 16G");
        require(toolContract.checkString(gpuType), "gpu type not match");
        require(calcPoint > 0, "machine calc point not found");
        require(cpuRate >= 3500, "cpu rate must be greater than or equal to 3500");
        require(machineOwner == stakeholder, "machine owner not match");

        require(calcPoint > 0, "machine calc point not found");

        (bool isOnline, bool isRegistered) = dbcAIContract.getMachineState(machineId, PROJECT_NAME, STAKING_TYPE);
        require(isOnline && isRegistered, "machine not online or not registered");
        require(getDailyRewardAmount() > 0, "daily reward amount used out");
        require(!isStaking(machineId), "machine already staked");
        require(nftTokenIds.length > 0, "nft token ids is empty");
        uint256 nftCount = getNFTCount(nftTokenIdBalances);
        require(nftCount <= getMaxNFTCountCanStake(), "nft count must be less than limit");
        uint256 originCalcPoint = calcPoint;
        calcPoint = calcPoint * nftCount;

        uint256 currentTime = block.timestamp;

        uint8 gpuCount = 1;
        totalGpuCount += gpuCount;
        if (totalGpuCount >= rewardStartGPUThreshold && rewardStartAtTimestamp == 0) {
            rewardStartAtTimestamp = currentTime;
        }

        nftToken.safeBatchTransferFrom(stakeholder, address(this), nftTokenIds, nftTokenIdBalances, "transfer");
        uint256 stakeEndAt = 0;
        machineId2StakeInfos[machineId] = StakeInfo({
            startAtTimestamp: currentTime,
            lastClaimAtTimestamp: currentTime,
            endAtTimestamp: stakeEndAt,
            calcPoint: 0,
            reservedAmount: 0,
            nftTokenIds: nftTokenIds,
            tokenIdBalances: nftTokenIdBalances,
            nftCount: nftCount,
            holder: stakeholder,
            claimedAmount: 0,
            isRentedByUser: false,
            gpuCount: gpuCount,
            nextRenterCanRentAt: currentTime
        });

        _joinStaking(machineId, calcPoint, 0);

        _tryInitMachineLockRewardInfo(machineId, currentTime);

        NFTStakingState.addOrUpdateStakeHolder(stakeholder, machineId, calcPoint, gpuCount, true);
        holder2MachineIds[stakeholder].push(machineId);

        (string memory region,) = getMachineRegion(machineId);
        require(region2Value[region] > 0, "machine region not found");
        RegionStakeInfo storage regionStakeInfo = region2StakeInfo[region];
        regionStakeInfo.stakedMachineCount += 1;
        dbcAIContract.reportStakingStatus(PROJECT_NAME, StakingType.Free, machineId, 1, true);
        emit Staked(stakeholder, machineId, originCalcPoint, calcPoint);
    }

    function joinStaking(string memory machineId, uint256 calcPoint, uint256 reserveAmount) external {
        require(msg.sender == address(rentContract), "sender must be rent contract");
        _joinStaking(machineId, calcPoint, reserveAmount);
    }

    function getPendingSlashCount(string memory machineId) public view returns (uint256) {
        return pendingSlashedMachineId2Renter[machineId].length;
    }

    function getRewardInfo(string memory machineId)
        public
        view
        returns (uint256 newRewardAmount, uint256 canClaimAmount, uint256 lockedAmount, uint256 claimedAmount)
    {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];

        uint256 totalRewardAmount = getReward(machineId);
        (uint256 _canClaimAmount, uint256 _lockedAmount) = _getRewardDetail(totalRewardAmount);
        (uint256 releaseAmount, uint256 lockedAmountBefore) = calculateReleaseReward(machineId);

        return (
            totalRewardAmount,
            _canClaimAmount + releaseAmount,
            _lockedAmount + lockedAmountBefore,
            stakeInfo.claimedAmount
        );
    }

    function getNFTCount(uint256[] calldata nftTokenIdBalances) internal pure returns (uint256 nftCount) {
        for (uint256 i = 0; i < nftTokenIdBalances.length; i++) {
            nftCount += nftTokenIdBalances[i];
        }

        return nftCount;
    }

    function _claim(string memory machineId) internal {
        require(rewardStart(), "reward not start yet");
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];

        uint256 machineShares = _getMachineShares(stakeInfo.calcPoint, stakeInfo.reservedAmount);
        _updateMachineRewards(machineId, machineShares, 0, totalDistributedRewardAmount, totalBurnedRewardAmount);

        address stakeholder = stakeInfo.holder;

        uint256 currentTimestamp = block.timestamp;

        bool _isStaking = isStaking(machineId);

        uint256 rewardAmount = getReward(machineId);

        machineId2StakeUnitRewards[machineId].accumulated = 0;

        (uint256 canClaimAmount, uint256 lockedAmount) = _getRewardDetail(rewardAmount);

        (uint256 _dailyReleaseAmount,) = calculateReleaseRewardAndUpdate(machineId);
        canClaimAmount += _dailyReleaseAmount;

        ApprovedReportInfo[] storage approvedReportInfos = pendingSlashedMachineId2Renter[machineId];
        bool slashed = approvedReportInfos.length > 0;
        uint256 moveToReserveAmount = 0;
        if (canClaimAmount > 0 && (_isStaking || slashed)) {
            if (stakeInfo.reservedAmount < BASE_RESERVE_AMOUNT) {
                (uint256 _moveToReserveAmount, uint256 leftAmountCanClaim) =
                    tryMoveReserve(machineId, canClaimAmount, stakeInfo);
                canClaimAmount = leftAmountCanClaim;
                moveToReserveAmount = _moveToReserveAmount;
            }
        }

        bool paidSlash = false;
        if (slashed && stakeInfo.reservedAmount >= BASE_RESERVE_AMOUNT) {
            ApprovedReportInfo memory lastSlashInfo = approvedReportInfos[approvedReportInfos.length - 1];
            payToRenterForSlashing(machineId, stakeInfo, lastSlashInfo.renter, true);
            approvedReportInfos.pop();
            paidSlash = true;
            NFTStakingState.subReserveAmount(msg.sender, machineId, BASE_RESERVE_AMOUNT);
        }

        if (stakeInfo.reservedAmount < BASE_RESERVE_AMOUNT && _isStaking) {
            (uint256 _moveToReserveAmount, uint256 leftAmountCanClaim) =
                tryMoveReserve(machineId, canClaimAmount, stakeInfo);
            canClaimAmount = leftAmountCanClaim;
            moveToReserveAmount = _moveToReserveAmount;
        }

        if (canClaimAmount > 0) {
            rewardToken.transfer(stakeholder, canClaimAmount);
        }

        uint256 totalRewardAmount = canClaimAmount + moveToReserveAmount;
        totalDistributedRewardAmount += totalRewardAmount;
        stakeInfo.claimedAmount += totalRewardAmount;
        stakeInfo.lastClaimAtTimestamp = currentTimestamp;
        NFTStakingState.addClaimedRewardAmount(
            msg.sender, machineId, rewardAmount + _dailyReleaseAmount, totalRewardAmount
        );

        if (lockedAmount > 0) {
            machineId2LockedRewardDetail[machineId].totalAmount += lockedAmount;
        }

        emit Claimed(
            stakeholder, machineId, rewardAmount + _dailyReleaseAmount, canClaimAmount, moveToReserveAmount, paidSlash
        );    }

    function getMachineIdsByStakeholder(address holder) external view returns (string[] memory) {
        return holder2MachineIds[holder];
    }

    function getAllRewardInfo(address holder)
        external
        view
        returns (uint256 availableRewardAmount, uint256 canClaimAmount, uint256 lockedAmount, uint256 claimedAmount)
    {
        string[] memory machineIds = holder2MachineIds[holder];
        for (uint256 i = 0; i < machineIds.length; i++) {
            (uint256 _availableRewardAmount, uint256 _canClaimAmount, uint256 _lockedAmount, uint256 _claimedAmount) =
                getRewardInfo(machineIds[i]);
            availableRewardAmount += _availableRewardAmount;
            canClaimAmount += _canClaimAmount;
            lockedAmount += _lockedAmount;
            claimedAmount += _claimedAmount;
        }
        return (availableRewardAmount, canClaimAmount, lockedAmount, claimedAmount);
    }

    function claimAll() external nonReentrant {
        string[] memory machineIds = holder2MachineIds[msg.sender];
        for (uint256 i = 0; i < machineIds.length; i++) {
            claim(machineIds[i]);
        }
    }

    function claim(string memory machineId) public nonReentrant {
        address stakeholder = msg.sender;
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];

        require(getPendingSlashCount(machineId) == 0, "machine should restake and paid slash before claim");

        require(stakeInfo.holder == stakeholder, "not stakeholder");
        require(block.timestamp - stakeInfo.lastClaimAtTimestamp >= 1 days, "last claim less than 1 day");

        _claim(machineId);
    }

    function tryMoveReserve(string memory machineId, uint256 canClaimAmount, StakeInfo storage stakeInfo)
        internal
        returns (uint256 moveToReserveAmount, uint256 leftAmountCanClaim)
    {
        uint256 leftAmountShouldReserve = BASE_RESERVE_AMOUNT - stakeInfo.reservedAmount;
        if (canClaimAmount >= leftAmountShouldReserve) {
            canClaimAmount -= leftAmountShouldReserve;
            moveToReserveAmount = leftAmountShouldReserve;
        } else {
            moveToReserveAmount = canClaimAmount;
            canClaimAmount = 0;
        }

        // the amount should be transfer to reserve
        totalReservedAmount += moveToReserveAmount;
        stakeInfo.reservedAmount += moveToReserveAmount;
        NFTStakingState.addReserveAmount(machineId, stakeInfo.holder, moveToReserveAmount);
        return (moveToReserveAmount, canClaimAmount);
    }

    function unStake(string calldata machineId) public nonReentrant {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(dlcClientWalletAddress[msg.sender] || msg.sender == stakeInfo.holder, "not dlc client wallet or owner");
        require(stakeInfo.startAtTimestamp > 0, "staking not found");
        require(!stakeInfo.isRentedByUser, "machine rented by user");
        //        require(block.timestamp >= stakeInfo.endAtTimestamp, "staking not ended"); todo
        (, bool isRegistered) = dbcAIContract.getMachineState(machineId, PROJECT_NAME, STAKING_TYPE);
        require(!isRegistered, "machine still registered");
        _claim(machineId);
        _unStake(machineId, stakeInfo.holder);
    }

    function _unStake(string calldata machineId, address stakeholder) internal {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        uint256 reservedAmount = stakeInfo.reservedAmount;

        if (reservedAmount > 0) {
            rewardToken.transfer(stakeholder, reservedAmount);
            stakeInfo.reservedAmount = 0;
            totalReservedAmount = totalReservedAmount > reservedAmount ? totalReservedAmount - reservedAmount : 0;
        }

        stakeInfo.endAtTimestamp = block.timestamp;
        nftToken.safeBatchTransferFrom(
            address(this), stakeholder, stakeInfo.nftTokenIds, stakeInfo.tokenIdBalances, "transfer"
        );
        stakeInfo.nftTokenIds = new uint256[](0);
        stakeInfo.tokenIdBalances = new uint256[](0);
        stakeInfo.nftCount = 0;
        _joinStaking(machineId, 0, 0);
        removeStakingMachineFromHolder(stakeholder, machineId);

        NFTStakingState.removeMachine(stakeInfo.holder, machineId);
        (string memory region,) = getMachineRegion(machineId);
        RegionStakeInfo storage regionStakeInfo = region2StakeInfo[region];
        regionStakeInfo.lastUnStakeTime = block.timestamp;
        regionStakeInfo.stakedMachineCount -= Math.min(regionStakeInfo.stakedMachineCount, 1);
        dbcAIContract.reportStakingStatus(PROJECT_NAME, StakingType.Free, machineId, 1, false);
        emit Unstaked(stakeholder, machineId,reservedAmount);
    }

    function removeStakingMachineFromHolder(address holder, string memory machineId) internal {
        string[] storage machineIds = holder2MachineIds[holder];
        for (uint256 i = 0; i < machineIds.length; i++) {
            if (keccak256(abi.encodePacked(machineIds[i])) == keccak256(abi.encodePacked(machineId))) {
                machineIds[i] = machineIds[machineIds.length - 1];
                machineIds.pop();
                break;
            }
        }
    }

    function getStakeHolder(string calldata machineId) external view returns (address) {
        StakeInfo memory stakeInfo = machineId2StakeInfos[machineId];
        return stakeInfo.holder;
    }

    function isStaking(string memory machineId) public view returns (bool) {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        bool _isStaking = stakeInfo.holder != address(0) && stakeInfo.startAtTimestamp > 0;
        if (stakeInfo.endAtTimestamp != 0) {
            _isStaking = _isStaking && block.timestamp < stakeInfo.endAtTimestamp;
        }

        return _isStaking;
    }

    function getTotalGPUCountInStaking() public view returns (uint256) {
        return totalGpuCount;
    }

    function getLeftGPUCountToStartReward() public view returns (uint256) {
        return rewardStartGPUThreshold > totalGpuCount ? rewardStartGPUThreshold - totalGpuCount : 0;
    }

    function rentMachine(string calldata machineId) external onlyRentContract {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        stakeInfo.isRentedByUser = true;

        uint256 newCalcPoint = (stakeInfo.calcPoint * 13) / 10;
        _joinStaking(machineId, newCalcPoint, stakeInfo.reservedAmount);
        NFTStakingState.addOrUpdateStakeHolder(stakeInfo.holder, machineId, newCalcPoint, 0, false);
        emit RentMachine(machineId);
    }

    function endRentMachine(string calldata machineId) external onlyRentContract {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.isRentedByUser, "not rented by user");
        stakeInfo.isRentedByUser = false;

        // 100 blocks
        stakeInfo.nextRenterCanRentAt = 600 + block.timestamp;

        uint256 newCalcPoint = (stakeInfo.calcPoint * 10) / 13;
        _joinStaking(machineId, newCalcPoint, stakeInfo.reservedAmount);
        NFTStakingState.addOrUpdateStakeHolder(stakeInfo.holder, machineId, newCalcPoint, 0, false);

        NFTStakingState.subRentedGPUCount(stakeInfo.holder, machineId);

        emit EndRentMachine(machineId);
    }

    function reportMachineFault(string calldata machineId, address renter) public onlyRentContractOrThis {
        if (!rewardStart()) {
            return;
        }

        if (renter == address(0)) {
            // if renter is not set, it means the machine is not rented by user
            // so we don't need to slash
            return;
        }
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        emit ReportMachineFault(machineId, renter);
        tryPaySlashOnReport(stakeInfo, machineId, renter);

        _claim(machineId);
        _unStake(machineId, stakeInfo.holder);
    }

    function tryPaySlashOnReport(StakeInfo storage stakeInfo, string memory machineId, address renter) internal {
        if (stakeInfo.reservedAmount >= BASE_RESERVE_AMOUNT) {
            payToRenterForSlashing(machineId, stakeInfo, renter, true);
        } else {
            pendingSlashedMachineId2Renter[machineId].push(ApprovedReportInfo({renter: renter}));
        }
    }

    function getMachineInfo(string memory machineId)
        external
        view
        returns (
            address holder,
            uint256 calcPoint,
            uint256 startAtTimestamp,
            uint256 endAtTimestamp,
            uint256 nextRenterCanRentAt,
            uint256 reservedAmount,
            bool isOnline,
            bool isRegistered
        )
    {
        StakeInfo memory info = machineId2StakeInfos[machineId];
        (bool _isOnline, bool _isRegistered) = dbcAIContract.getMachineState(machineId, PROJECT_NAME, STAKING_TYPE);
        return (
            info.holder,
            info.calcPoint,
            info.startAtTimestamp,
            info.endAtTimestamp,
            info.nextRenterCanRentAt,
            info.reservedAmount,
            _isOnline,
            _isRegistered
        );
    }

    function payToRenterForSlashing(
        string memory machineId,
        StakeInfo storage stakeInfo,
        address renter,
        bool alreadyStaked
    ) internal {
        rewardToken.transfer(renter, BASE_RESERVE_AMOUNT);
        if (alreadyStaked) {
            _joinStaking(machineId, stakeInfo.calcPoint, stakeInfo.reservedAmount - BASE_RESERVE_AMOUNT);
        }

        rentContract.paidSlash(machineId);
        emit PaySlash(machineId, renter, BASE_RESERVE_AMOUNT);
    }

    function getGlobalState() external view returns (uint256, uint256) {
        return (totalCalcPoint, totalReservedAmount);
    }

    function getDailyRewardAmount() public view returns (uint256) {
        return RewardCalculator._getDailyRewardAmount(totalDistributedRewardAmount, totalBurnedRewardAmount);
    }

    function _updateRewardPerCalcPoint() internal {
        uint256 accumulatedPerShareBefore = rewardsPerCalcPoint.accumulatedPerShare;
        rewardsPerCalcPoint = _getUpdatedRewardPerCalcPoint(0, totalDistributedRewardAmount, totalBurnedRewardAmount);
        emit RewardsPerCalcPointUpdate(accumulatedPerShareBefore, rewardsPerCalcPoint.accumulatedPerShare);
    }

    function _getMachineShares(uint256 calcPoint, uint256 reservedAmount) internal view returns (uint256) {
        return calcPoint
            * toolContract.LnUint256(reservedAmount > BASE_RESERVE_AMOUNT ? reservedAmount : BASE_RESERVE_AMOUNT);
    }

    function _joinStaking(string memory machineId, uint256 calcPoint, uint256 reserveAmount) internal {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];

        uint256 oldLnReserved = toolContract.LnUint256(
            stakeInfo.reservedAmount > BASE_RESERVE_AMOUNT ? stakeInfo.reservedAmount : BASE_RESERVE_AMOUNT
        );

        uint256 machineShares = stakeInfo.calcPoint * oldLnReserved;

        uint256 newLnReserved =
            toolContract.LnUint256(reserveAmount > BASE_RESERVE_AMOUNT ? reserveAmount : BASE_RESERVE_AMOUNT);

        totalAdjustUnit -= stakeInfo.calcPoint * oldLnReserved;
        totalAdjustUnit += calcPoint * newLnReserved;

        // update machine rewards
        _updateMachineRewards(machineId, machineShares, 0, totalDistributedRewardAmount, totalBurnedRewardAmount);

        totalCalcPoint = totalCalcPoint - stakeInfo.calcPoint + calcPoint;

        stakeInfo.calcPoint = calcPoint;
        if (reserveAmount > stakeInfo.reservedAmount) {
            rewardToken.transferFrom(stakeInfo.holder, address(this), reserveAmount);
        }
        if (reserveAmount != stakeInfo.reservedAmount) {
            totalReservedAmount = totalReservedAmount + reserveAmount - stakeInfo.reservedAmount;
            stakeInfo.reservedAmount = reserveAmount;
        }
    }

    function getReward(string memory machineId) public view returns (uint256) {
        StakeInfo memory stakeInfo = machineId2StakeInfos[machineId];
        if (stakeInfo.lastClaimAtTimestamp > stakeInfo.endAtTimestamp && stakeInfo.endAtTimestamp > 0) {
            return 0;
        }
        uint256 machineShares = _getMachineShares(stakeInfo.calcPoint, stakeInfo.reservedAmount);

        RewardCalculatorLib.UserRewards memory machineRewards = machineId2StakeUnitRewards[machineId];

        RewardCalculatorLib.RewardsPerShare memory currentRewardPerCalcPoint =
            _getUpdatedRewardPerCalcPoint(0, totalDistributedRewardAmount, totalBurnedRewardAmount);
        uint256 rewardAmount = RewardCalculatorLib.calculatePendingUserRewards(
            machineShares, machineRewards.lastAccumulatedPerShare, currentRewardPerCalcPoint.accumulatedPerShare
        );

        return machineRewards.accumulated + rewardAmount;
    }

    function version() external pure returns (uint256) {
        return 1;
    }
}

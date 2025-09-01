// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Import necessary OpenZeppelin contracts for upgradeable functionality
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
// Import custom interfaces for reward token, rent contract, and DBC AI contract
import "./interface/IRewardToken.sol";
import "./interface/IRentContract.sol";
import "./interface/IDBCAIContract.sol";
import "./library/ToolLib.sol";
import "forge-std/console.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./library/RewardCalculatorLib.sol";
import {RewardCalculator} from "./RewardCalculater.sol";

/**
 * @title BandWidthStaking
 * @dev A staking contract for bandwidth sharing with NFT-based rewards
 * @notice This contract allows users to stake NFTs to earn rewards based on machine bandwidth contribution
 * @custom:oz-upgrades-from OldBandWidthStaking
 */
contract BandWidthStaking is
    RewardCalculator,
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    IERC1155Receiver
{
    // Project constants
    string public constant PROJECT_NAME = "DeepLink BandWidth"; // Name of the project
    uint8 public constant SECONDS_PER_BLOCK = 6; // Average seconds per block
    uint256 public constant BASE_RESERVE_AMOUNT = 10_000 ether; // Base amount required for staking
    StakingType public constant STAKING_TYPE = StakingType.Free; // Default staking type

    // Contract interfaces
    IDBCAIContract public dbcAIContract; // Interface to DBC AI contract for machine management
    IERC1155 public nftToken; // NFT token contract for staking
    IRewardToken public rewardToken; // Reward token contract

    // Administrative addresses
    address public burnAddress; // Address where burned tokens are sent
    address public slashPayToAddress; // Address to receive slashed amounts
    address public canUpgradeAddress; // Address authorized to upgrade the contract

    // Contract state variables
    bool public registered; // Whether the contract is registered
    uint256 public totalRegionValue; // Total value across all regions
    uint256 public totalDistributedRewardAmount; // Total rewards distributed
    uint256 public totalBurnedRewardAmount; // Total rewards burned
    uint256 public totalReservedAmount; // Total amount reserved

    uint256 public totalCalcPoint; // Total calculation points across all machines

    uint256 public lastBurnTime; // Timestamp of last burn operation
    string[] public regions; // Array of supported regions
    /**
     * @dev Enum defining different types of staking periods
     */
    enum StakingType {
        ShortTerm,  // Short-term staking
        LongTerm,   // Long-term staking
        Free        // Free staking (no time restriction)
    }

    /**
     * @dev Enum for different notification types from external contracts
     */
    enum NotifyType {
        ContractRegister,   // Contract registration notification
        MachineRegister,    // Machine registration notification
        MachineUnregister,  // Machine unregistration notification
        MachineOnline,      // Machine online notification
        MachineOffline      // Machine offline notification
    }

    /**
     * @dev Structure to store information about slashing events
     */
    struct SlashInfo {
        address stakeHolder;    // Address of the stake holder being slashed
        string machineId;       // ID of the machine being slashed
        uint256 slashAmount;    // Amount to be slashed
        uint256 createdAt;      // Timestamp when slash was created
        bool paid;              // Whether the slash has been paid
    }

    /**
     * @dev Structure for approved report information
     */
    struct ApprovedReportInfo {
        address slashToPayAddress;  // Address to receive slash payment
    }

    /**
     * @dev Structure to store comprehensive staking information for each machine
     */
    struct StakeInfo {
        address holder;                 // Address of the stake holder
        uint256 startAtTimestamp;       // Timestamp when staking started
        uint256 lastClaimAtTimestamp;   // Timestamp of last reward claim
        uint256 endAtTimestamp;         // Timestamp when staking ends (0 for indefinite)
        uint256 calcPoint;              // Calculation points for reward calculation
        uint256 reservedAmount;         // Amount reserved for this stake
        uint256[] nftTokenIds;          // Array of staked NFT token IDs
        uint256[] tokenIdBalances;      // Array of NFT token balances
        uint256 nftCount;               // Total count of NFTs staked
        uint256 claimedAmount;          // Total amount of rewards claimed
        bool isRentedByUser;            // Whether the machine is currently rented
        uint256 nextRenterCanRentAt;    // Timestamp when next renter can rent
        string region;                  // Geographic region of the machine
        uint256 originCalcPoint;        // Original calculation points before NFT multiplier
    }

    /**
     * @dev Structure to track staking information per region
     */
    struct RegionStakeInfo {
        uint256 stakedMachineCount;     // Number of machines staked in this region
        uint256 lastUnStakeTime;        // Timestamp of last unstaking in this region
    }

    /**
     * @dev Structure for machine information used by DBC scan
     */
    struct MachineInfoForDBCScan {
        bool isStaking;                 // Whether the machine is currently staking
        string region;                  // Geographic region of the machine
        uint256 hdd;                    // Hard disk drive capacity
        uint256 bandwidth;              // Network bandwidth capacity
        uint256 mem;                    // Memory capacity
        uint256 cpuCors;                // Number of CPU cores
        string projectName;             // Name of the project
        uint256 totalRewardAmount;      // Total rewards earned
        uint256 claimedRewardAmount;    // Total rewards claimed
        uint256 lockedRewardAmount;     // Amount of rewards locked
        uint256 canClaimRewardAmount;   // Amount of rewards available to claim
    }

    // Mappings for slash management
    mapping(uint256 => SlashInfo) public slashId2SlashInfo;        // Maps slash ID to slash information
    mapping(string => uint256) public machine2LastSlashId;          // Maps machine ID to last slash ID
    mapping(address => bool) public dlcClientWalletAddress;         // Maps addresses to DLC client wallet status

    // Mappings for stake holder management
    mapping(address => string[]) public holder2MachineIds;          // Maps holder address to their machine IDs

    // Core staking mappings
    mapping(string => StakeInfo) public machineId2StakeInfos;       // Maps machine ID to staking information

    // Region management mappings
    mapping(string => uint256) public region2Value;                 // Maps region name to its value weight
    mapping(string => RegionStakeInfo) public region2StakeInfo;     // Maps region to staking statistics

    // Contract control variables
    bool public paused;                                             // Whether the contract is paused
    mapping(string => string) public machine2PreRegion;             // Maps machine ID to pre-assigned region

    // Events for staking operations
    event Staked(
        address indexed stakeholder, string machineId, uint256 originCalcPoint, uint256 calcPoint, string region
    );  // Emitted when a machine is staked

    event ReserveDLC(string machineId, uint256 amount);  // Emitted when DLC is reserved for a machine
    event Unstaked(address indexed stakeholder, string machineId, uint256 paybackReserveAmount);  // Emitted when a machine is unstaked
    event Claimed(
        address indexed stakeholder,
        string machineId,
        uint256 totalRewardAmount,
        uint256 moveToUserWalletAmount,
        uint256 moveToReservedAmount,
        bool paidSlash
    );  // Emitted when rewards are claimed

    // Events for machine rental operations
    event RentMachine(string machineId);  // Emitted when a machine is rented
    event EndRentMachine(string machineId);  // Emitted when machine rental ends
    event ReportMachineFault(string machineId, uint256 slashId, address renter);  // Emitted when machine fault is reported
    
    // Events for reward management
    event BurnedInactiveRegionRewards(uint256 amount);  // Emitted when inactive region rewards are burned
    event BurnedInactiveSingleRegionRewards(string region, uint256 amount);  // Emitted when single region rewards are burned
    event DepositReward(uint256 amount);  // Emitted when rewards are deposited
    
    // Events for machine state changes
    event AddBackCalcPointOnOnline(string machineId, uint256 calcPoint);  // Emitted when calc points are restored on machine online
    event MachineRegister(string machineId, uint256 calcPoint);  // Emitted when a machine is registered
    event MachineUnregister(string machineId, uint256 calcPoint);  // Emitted when a machine is unregistered
    
    // Events for slashing operations
    event SlashMachineOnOffline(address indexed stakeHolder, string machineId, uint256 slashAmount);  // Emitted when machine is slashed for going offline
    event PaySlash(string machineId, address to, uint256 slashAmount);  // Emitted when slash payment is made
    
    // Events for administrative operations
    event BurnAddressSet(address indexed burnAddress);  // Emitted when burn address is set
    event MoveToReserveAmount(string machineId, address holder, uint256 amount);  // Emitted when amount is moved to reserve
    event ExitStakingForOffline(string machineId, address holder);  // Emitted when staking is exited due to offline
    event RecoverRewarding(string machineId, address holder);  // Emitted when rewarding is recovered

    /**
     * @dev Modifier to restrict access to only the DBC AI contract
     */
    modifier onlyDBCAIContract() {
        require(msg.sender == address(dbcAIContract), "only dbc AI contract");
        _;
    }

    modifier onlyDLCClientWallet() {
        require(dlcClientWalletAddress[msg.sender] || msg.sender == owner(), "not admin");
        _;
    }

    /**
     * @dev Constructor that disables initializers to prevent implementation contract initialization
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Handles the receipt of multiple ERC1155 token types
     * @return bytes4 The selector to confirm token transfer
     */
    function onERC1155BatchReceived(
        address, /* unusedParameter */
        address, /* unusedParameter */
        uint256[] calldata, /* unusedParameter */
        uint256[] calldata, /* unusedParameter */
        bytes calldata /* unusedParameter */
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    /**
     * @dev Handles the receipt of a single ERC1155 token type
     * @return bytes4 The selector to confirm token transfer
     */
    function onERC1155Received(
        address, /* unusedParameter */
        address, /* unusedParameter */
        uint256, /* unusedParameter */
        uint256, /* unusedParameter */
        bytes calldata /* unusedParameter */
    ) external pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /**
     * @dev Checks if the contract supports a given interface
     * @param interfaceId The interface identifier to check
     * @return bool True if the interface is supported
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }

    /**
     * @dev Initializes the contract with required parameters
     * @param _initialOwner Address of the initial contract owner
     * @param _slashPayToAddress Address to receive slash payments
     * @param _nftToken Address of the NFT token contract
     * @param _rewardToken Address of the reward token contract
     * @param _dbcAIContract Address of the DBC AI contract
     */
    function initialize(
        address _initialOwner,
        address _slashPayToAddress,
        address _nftToken,
        address _rewardToken,
        address _dbcAIContract
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();

        rewardToken = IRewardToken(_rewardToken);
        nftToken = IERC1155(_nftToken);
        dbcAIContract = IDBCAIContract(_dbcAIContract);

        uint256 currentTime = block.timestamp;
        rewardsPerCalcPoint.lastUpdated = currentTime;
        rewardStartAtTimestamp = currentTime;
        lastBurnTime = currentTime;
        slashPayToAddress = _slashPayToAddress;
        canUpgradeAddress = msg.sender;
        setRegions();
    }

    /**
     * @dev Internal function to authorize contract upgrades
     * @param newImplementation Address of the new implementation contract
     */
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        require(newImplementation != address(0), "new implementation is the zero address");
        require(msg.sender == canUpgradeAddress, "only canUpgradeAddress can authorize upgrade");
    }

    /**
     * @dev Sets the address authorized to upgrade the contract
     * @param addr New upgrade authorization address
     */
    function setUpgradeAddress(address addr) external onlyOwner {
        canUpgradeAddress = addr;
    }

    /**
     * @dev Sets the address to receive slash payments
     * @param addr New slash payment address
     */
    function setSlashPayToAddress(address addr) external onlyOwner {
        slashPayToAddress = addr;
    }

    /**
     * @dev Sets the address where burned tokens are sent
     * @param _burnAddress New burn address
     */
    function setBurnAddress(address _burnAddress) external onlyOwner {
        burnAddress = _burnAddress;
        emit BurnAddressSet(_burnAddress);
    }

    /**
     * @dev Sets the reward token contract address
     * @param token New reward token contract address
     */
    function setRewardToken(address token) external onlyOwner {
        rewardToken = IRewardToken(token);
    }

    /**
     * @dev Sets the NFT token contract address
     * @param token New NFT token contract address
     */
    function setNftToken(address token) external onlyOwner {
        nftToken = IERC1155(token);
    }

    /**
     * @dev Sets the timestamp when rewards start being distributed
     * @param timestamp New reward start timestamp
     */
    function setRewardStartAt(uint256 timestamp) external onlyOwner {
        require(timestamp >= block.timestamp, "time must be greater than current block number");
        rewardStartAtTimestamp = timestamp;
    }

    /**
     * @dev Pauses or unpauses the contract
     * @param _paused True to pause, false to unpause
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    /**
     * @dev Sets multiple DLC client wallet addresses
     * @param addrs Array of addresses to be marked as DLC client wallets
     */
    function setDLCClientWallets(address[] calldata addrs) external onlyOwner {
        for (uint256 i = 0; i < addrs.length; i++) {
            require(addrs[i] != address(0), "address is zero");
            require(dlcClientWalletAddress[addrs[i]] == false, "address already added");
            dlcClientWalletAddress[addrs[i]] = true;
        }
    }

    /**
     * @dev Sets the DBC AI contract address
     * @param addr New DBC AI contract address
     */
    function setDBCAIContract(address addr) external onlyOwner {
        dbcAIContract = IDBCAIContract(addr);
    }

    /**
     * @dev Internal function to initialize all supported regions and their values
     * Sets up the geographic regions and their corresponding reward weights
     */
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

    /**
     * @dev Sets a new region for a specific machine
     * @param machineId ID of the machine to update
     * @param newRegion New region to assign to the machine
     */
    function setRegion(string calldata machineId, string calldata newRegion) external onlyDLCClientWallet {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        // require(stakeInfo.nftCount > 0, "not in staking");
        require(region2Value[newRegion] > 0, "invalid region");
        require(keccak256(abi.encodePacked(newRegion)) != keccak256(abi.encodePacked(stakeInfo.region)), "same region");
        machine2PreRegion[machineId] = newRegion;
    }

    /**
     * @dev Calculates the total rewards accumulated in inactive regions
     * @return uint256 Total amount of rewards from inactive regions
     */
    function inactiveRegionRewards() public returns (uint256) {
        uint256 durationInactiveReward = 0;

        for (uint256 i = 0; i < regions.length; i++) {
            string memory region = regions[i];
            uint256 duration = block.timestamp - lastBurnTime;
            if (isInactiveRegion(region)) {
                uint256 regionValue = region2Value[region];
                uint256 dailyRegionRewardAmount = getDailyRewardAmount() * regionValue / totalRegionValue;
                uint256 currentInactiveRegionReward = (duration * dailyRegionRewardAmount / 1 days);
                durationInactiveReward += currentInactiveRegionReward;
                emit BurnedInactiveSingleRegionRewards(region, currentInactiveRegionReward);
            }
        }

        return durationInactiveReward;
    }

    /**
     * @dev Checks if a region is considered inactive
     * @param region Name of the region to check
     * @return bool True if the region is inactive
     */
    function isInactiveRegion(string memory region) internal view returns (bool) {
        uint256 duration = block.timestamp - lastBurnTime;
        RegionStakeInfo memory info = region2StakeInfo[region];
        if (info.stakedMachineCount == 0 && block.timestamp >= info.lastUnStakeTime + duration) {
            return true;
        }
        return false;
    }

    /**
     * @dev Burns rewards accumulated in inactive regions
     * Transfers inactive region rewards to the burn address
     */
    function burnInactiveRegionRewards() internal {
        uint256 durationInactiveReward = inactiveRegionRewards();
        totalBurnedRewardAmount += durationInactiveReward;
        rewardToken.approve(address(this), durationInactiveReward);
        //        rewardToken.burnFrom(address(this), durationInactiveReward);
        require(burnAddress != address(0), "burn address not set");
        rewardToken.transfer(burnAddress, durationInactiveReward);
        lastBurnTime = block.timestamp;

        emit BurnedInactiveRegionRewards(durationInactiveReward);
    }

    /**
     * @dev Initializes locked reward information for a machine if not already set
     * @param machineId ID of the machine
     * @param currentTime Current timestamp
     */
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

    /**
     * @dev Calculates the maximum number of NFTs that can be staked based on elapsed time
     * @return uint256 Maximum NFT count allowed for staking
     */
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

    /**
     * @dev Adds DLC tokens to an existing stake
     * @param machineId ID of the machine to add DLC to
     * @param amount Amount of DLC tokens to add
     */
    function addDLCToStake(string memory machineId, uint256 amount) external nonReentrant {
        require(isStaking(machineId), "machine not staked");
        if (amount == 0) {
            return;
        }
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];

        //        ApprovedReportInfo[] memory approvedReportInfos = pendingSlashedMachineId2Renter[machineId];
        //
        //        if (approvedReportInfos.length > 0) {
        //            require(
        //                amount >= BASE_RESERVE_AMOUNT * approvedReportInfos.length, "amount must be greater than slash amount"
        //            );
        //            for (uint8 i = 0; i < approvedReportInfos.length; i++) {
        //                // pay slash to renters
        //                payToRenterForSlashing(machineId, stakeInfo, approvedReportInfos[i].slashToPayAddress, false);
        //                amount -= BASE_RESERVE_AMOUNT;
        //            }
        //            delete pendingSlashedMachineId2Renter[machineId];
        //        }

        _joinStaking(machineId, stakeInfo.calcPoint, amount + stakeInfo.reservedAmount);
        emit ReserveDLC(machineId, amount);
    }

    /**
     * @dev Validates machine specifications for staking eligibility
     * @param calcPoint Calculation points of the machine
     * @param gpuType GPU type of the machine
     * @param mem Memory size of the machine
     */
    function revertIfMachineInfoCanNotStake(uint256 calcPoint, string memory gpuType, uint256 mem) internal pure {
        require(mem >= 16, "memory size must greater than or equal to 16G");
        require(ToolLib.checkString(gpuType), "gpu type not match");
        require(calcPoint > 0, "machine calc point not found");
    }

    /**
     * @dev Stakes NFTs for a machine to earn rewards
     * @param stakeholder Address of the stakeholder
     * @param machineId ID of the machine to stake
     * @param nftTokenIds Array of NFT token IDs to stake
     * @param nftTokenIdBalances Array of NFT token balances to stake
     */
    function stake(
        address stakeholder,
        string calldata machineId,
        uint256[] calldata nftTokenIds,
        uint256[] calldata nftTokenIdBalances
    ) external nonReentrant {
        (
            address machineOwner,
            ,
            uint256 cpuCores,
            uint256 machineMem,
            string memory region,
            uint256 hdd,
            uint256 bandwidth
        ) = dbcAIContract.machineBandWidthInfos(machineId);

        uint256 calcPoint = bandwidth;
        require(dbcAIContract.freeGpuAmount(machineId) >= 1, "machine not stake enough dbc");
        require(nftTokenIds.length == nftTokenIdBalances.length, "nft token ids and balances length not match");
        require(region2Value[region] > 0, "machine region not found");
        require(calcPoint >= 10, "machine calc point not found");
        require(cpuCores >= 1, "machine cpu cores not found");
        require(machineMem >= 2, "machine memory not enough");
        require(hdd >= 30, "machine hdd not enough");
        require(machineOwner == stakeholder, "machine owner not match");

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

        string memory preRegin = machine2PreRegion[machineId];
        if (keccak256(abi.encodePacked(preRegin)) != keccak256(abi.encodePacked(""))) {
            region = preRegin;
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
            nextRenterCanRentAt: currentTime,
            region: region,
            originCalcPoint: bandwidth
        });

        // machine2PreRegion[machineId] = "";

        _joinStaking(machineId, calcPoint, 0);
        _tryInitMachineLockRewardInfo(machineId, currentTime);

        burnInactiveRegionRewards();
        holder2MachineIds[stakeholder].push(machineId);
        RegionStakeInfo storage regionStakeInfo = region2StakeInfo[region];
        regionStakeInfo.stakedMachineCount += 1;
        dbcAIContract.reportStakingStatus(PROJECT_NAME, StakingType.Free, machineId, 1, true);
        emit Staked(stakeholder, machineId, originCalcPoint, calcPoint, region);
    }

    //    function getPendingSlashCount(string memory machineId) public view returns (uint256) {
    //        return pendingSlashedMachineId2Renter[machineId].length;
    //    }

    /**
     * @dev Checks if a machine is currently being slashed
     * @param machineId ID of the machine to check
     * @return bool True if the machine is in slashing state
     */
    function isInSlashing(string memory machineId) public view returns (bool) {
        uint256 slashId = machine2LastSlashId[machineId];
        if (slashId == 0) {
            return false;
        }

        return (slashId2SlashInfo[slashId].paid == false && slashId2SlashInfo[slashId].slashAmount > 0);
    }

    /**
     * @dev Gets comprehensive reward information for a machine
     * @param machineId ID of the machine
     * @return newRewardAmount Total new reward amount
     * @return canClaimAmount Amount that can be claimed immediately
     * @return lockedAmount Amount that is locked
     * @return claimedAmount Amount already claimed
     */
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

    /**
     * @dev Calculates the total count of NFTs from balance array
     * @param nftTokenIdBalances Array of NFT token balances
     * @return nftCount Total count of NFTs
     */
    function getNFTCount(uint256[] calldata nftTokenIdBalances) internal pure returns (uint256 nftCount) {
        for (uint256 i = 0; i < nftTokenIdBalances.length; i++) {
            nftCount += nftTokenIdBalances[i];
        }

        return nftCount;
    }

    /**
     * @dev Calculates rewards per second for a specific region
     * @param region Name of the region
     * @return uint256 Rewards per second for the region
     */
    function getRegionRewardsPerSeconds(string memory region) public view returns (uint256) {
        uint256 regionValue = region2Value[region];
        uint256 totalRewardPerSecond = getDailyRewardAmount() / 1 days;
        return totalRewardPerSecond * regionValue / totalRegionValue;
    }

    /**
     * @dev Internal function to process reward claims for a machine
     * @param machineId ID of the machine to claim rewards for
     */
    function _claim(string memory machineId) internal {
        require(paused == false, "paused");
        require(rewardStart(), "reward not start yet");
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];

        uint256 machineShares = _getMachineShares(stakeInfo.calcPoint, stakeInfo.reservedAmount);
        uint256 regionRewardsPerSeconds = getRegionRewardsPerSeconds(stakeInfo.region);
        _updateMachineRewardsOfRegion(machineId, machineShares, stakeInfo.region, regionRewardsPerSeconds);
        address stakeholder = stakeInfo.holder;

        uint256 currentTimestamp = block.timestamp;

        bool _isStaking = isStaking(machineId);

        uint256 rewardAmount = getReward(machineId);

        machineId2StakeUnitRewards[machineId].accumulated = 0;

        (uint256 canClaimAmount, uint256 lockedAmount) = _getRewardDetail(rewardAmount);

        (uint256 _dailyReleaseAmount,) = calculateReleaseRewardAndUpdate(machineId);
        canClaimAmount += _dailyReleaseAmount;

        bool slashed = isInSlashing(machineId);
        uint256 moveToReserveAmount = 0;
        if (canClaimAmount > 0 && (_isStaking || slashed)) {
            if (stakeInfo.reservedAmount < BASE_RESERVE_AMOUNT) {
                (uint256 _moveToReserveAmount, uint256 leftAmountCanClaim) =
                    tryMoveReserve(machineId, canClaimAmount, stakeInfo);
                canClaimAmount = leftAmountCanClaim;
                moveToReserveAmount = _moveToReserveAmount;
            }
        }

        bool _paidSlash = false;
        if (slashed && stakeInfo.reservedAmount >= BASE_RESERVE_AMOUNT) {
            uint256 slashId = machine2LastSlashId[machineId];
            payToRenterForSlashing(machineId, stakeInfo, slashPayToAddress, true);
            slashId2SlashInfo[slashId].paid = true;
            _paidSlash = true;
        }

        if (stakeInfo.reservedAmount < BASE_RESERVE_AMOUNT && _isStaking) {
            (uint256 _moveToReserveAmount, uint256 leftAmountCanClaim) =
                tryMoveReserve(machineId, canClaimAmount, stakeInfo);
            canClaimAmount = leftAmountCanClaim;
            moveToReserveAmount = _moveToReserveAmount;
        }

        if (canClaimAmount > 0) {
            require(
                rewardToken.balanceOf(address(this)) - totalReservedAmount >= canClaimAmount,
                "reward token balance not enough"
            );
            rewardToken.transfer(stakeholder, canClaimAmount);
        }

        uint256 totalRewardAmount = canClaimAmount + moveToReserveAmount;
        totalDistributedRewardAmount += totalRewardAmount;
        stakeInfo.claimedAmount += totalRewardAmount;
        stakeInfo.lastClaimAtTimestamp = currentTimestamp;

        if (lockedAmount > 0) {
            machineId2LockedRewardDetail[machineId].totalAmount += lockedAmount;
        }

        emit Claimed(
            stakeholder, machineId, rewardAmount + _dailyReleaseAmount, canClaimAmount, moveToReserveAmount, _paidSlash
        );
    }

    /**
     * @dev Gets all machine IDs staked by a specific stakeholder
     * @param holder Address of the stakeholder
     * @return string[] Array of machine IDs
     */
    function getMachineIdsByStakeholder(address holder) external view returns (string[] memory) {
        return holder2MachineIds[holder];
    }

    /**
     * @dev Gets aggregated reward information for all machines owned by a stakeholder
     * @param holder Address of the stakeholder
     * @return availableRewardAmount Total available reward amount
     * @return canClaimAmount Total amount that can be claimed
     * @return lockedAmount Total locked amount
     * @return claimedAmount Total claimed amount
     */
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

    /**
     * @dev Claims rewards for a specific machine
     * @param machineId ID of the machine to claim rewards for
     */
    function claim(string memory machineId) public nonReentrant {
        require(!isInSlashing(machineId), "machine should restake and paid slash before claim");

        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(stakeInfo.holder == msg.sender, "not stakeholder");

        _claim(machineId);
    }

    /**
     * @dev Internal function to move claimable amount to reserve
     * @param machineId ID of the machine
     * @param canClaimAmount Amount that can be claimed
     * @param stakeInfo Storage reference to stake information
     * @return moveToReserveAmount Amount moved to reserve
     * @return leftAmountCanClaim Remaining amount that can be claimed
     */
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
        if (moveToReserveAmount > 0) {
            emit MoveToReserveAmount(machineId, stakeInfo.holder, moveToReserveAmount);
        }

        return (moveToReserveAmount, canClaimAmount);
    }

    /**
     * @dev Unstakes a machine and withdraws all staked tokens
     * @param machineId ID of the machine to unstake
     */
    function unStake(string calldata machineId) public nonReentrant {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        require(dlcClientWalletAddress[msg.sender] || msg.sender == stakeInfo.holder, "not dlc client wallet or owner");
        require(stakeInfo.startAtTimestamp > 0, "staking not found");
        require(!stakeInfo.isRentedByUser, "machine rented by user");
        (, bool isRegistered) = dbcAIContract.getMachineState(machineId, PROJECT_NAME, STAKING_TYPE);
        require(!isRegistered, "machine still registered");
        _claim(machineId);
        _unStake(machineId, stakeInfo.holder);
    }

    /**
     * @dev Internal function to handle the unstaking process
     * @param machineId ID of the machine to unstake
     * @param stakeholder Address of the stakeholder
     */
    function _unStake(string memory machineId, address stakeholder) internal {
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

        string memory region = stakeInfo.region;
        RegionStakeInfo storage regionStakeInfo = region2StakeInfo[region];
        regionStakeInfo.lastUnStakeTime = block.timestamp;
        regionStakeInfo.stakedMachineCount -= Math.min(regionStakeInfo.stakedMachineCount, 1);
        dbcAIContract.reportStakingStatus(PROJECT_NAME, StakingType.Free, machineId, 1, false);
        emit Unstaked(stakeholder, machineId, reservedAmount);
    }

    /**
     * @dev Removes a machine ID from the holder's machine list
     * @param holder Address of the stakeholder
     * @param machineId ID of the machine to remove
     */
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

    /**
     * @dev Gets the stakeholder address for a specific machine
     * @param machineId ID of the machine
     * @return address Address of the stakeholder
     */
    function getStakeHolder(string calldata machineId) external view returns (address) {
        StakeInfo memory stakeInfo = machineId2StakeInfos[machineId];
        return stakeInfo.holder;
    }

    /**
     * @dev Checks if a machine is currently staking
     * @param machineId ID of the machine to check
     * @return bool True if the machine is actively staking
     */
    function isStaking(string memory machineId) public view returns (bool) {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        bool _isStaking = stakeInfo.holder != address(0) && stakeInfo.startAtTimestamp > 0;
        if (stakeInfo.endAtTimestamp != 0) {
            _isStaking = _isStaking && block.timestamp < stakeInfo.endAtTimestamp;
        }

        return _isStaking;
    }

    function tryPaySlashOnReport(
        StakeInfo memory stakeInfo,
        string memory machineId,
        uint256 slashId,
        address _slashToPayAddress
    ) internal {
        if (stakeInfo.reservedAmount >= BASE_RESERVE_AMOUNT) {
            payToRenterForSlashing(machineId, stakeInfo, _slashToPayAddress, true);
            slashId2SlashInfo[slashId].paid = true;
        }
    }

    function payToRenterForSlashing(
        string memory machineId,
        StakeInfo memory stakeInfo,
        address slashToPayAddress,
        bool alreadyStaked
    ) internal {
        if (alreadyStaked) {
            _joinStaking(machineId, stakeInfo.calcPoint, stakeInfo.reservedAmount - BASE_RESERVE_AMOUNT);
        }
        rewardToken.transfer(slashToPayAddress, BASE_RESERVE_AMOUNT);

        //        paidSlash(machineId);
        emit PaySlash(machineId, slashToPayAddress, BASE_RESERVE_AMOUNT);
    }

    /**
     * @dev Gets the daily reward amount for the entire system
     * @return uint256 Daily reward amount
     */
    function getDailyRewardAmount() public view returns (uint256) {
        return RewardCalculator._getDailyRewardAmount(totalDistributedRewardAmount, totalBurnedRewardAmount);
    }

    //    function _updateRewardPerCalcPoint() internal {
    //        uint256 accumulatedPerShareBefore = rewardsPerCalcPoint.accumulatedPerShare;
    //        rewardsPerCalcPoint = _getUpdatedRewardPerCalcPoint(totalDistributedRewardAmount, totalBurnedRewardAmount);
    //        emit RewardsPerCalcPointUpdate(accumulatedPerShareBefore, rewardsPerCalcPoint.accumulatedPerShare);
    //    }

    /**
     * @dev Calculates machine shares based on calculation points and reserved amount
     * @param calcPoint Calculation points for the machine
     * @param reservedAmount Reserved amount for the machine
     * @return uint256 Machine shares
     */
    function _getMachineShares(uint256 calcPoint, uint256 reservedAmount) public pure returns (uint256) {
        return
            calcPoint * ToolLib.LnUint256(reservedAmount > BASE_RESERVE_AMOUNT ? reservedAmount : BASE_RESERVE_AMOUNT);
    }

    /**
     * @dev Internal function to join or update staking parameters
     * @param machineId ID of the machine
     * @param calcPoint New calculation points
     * @param reserveAmount New reserve amount
     */
    function _joinStaking(string memory machineId, uint256 calcPoint, uint256 reserveAmount) internal {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];

        uint256 oldLnReserved = ToolLib.LnUint256(
            stakeInfo.reservedAmount > BASE_RESERVE_AMOUNT ? stakeInfo.reservedAmount : BASE_RESERVE_AMOUNT
        );

        uint256 machineShares = stakeInfo.calcPoint * oldLnReserved;

        uint256 newLnReserved =
            ToolLib.LnUint256(reserveAmount > BASE_RESERVE_AMOUNT ? reserveAmount : BASE_RESERVE_AMOUNT);

        totalAdjustUnit -= stakeInfo.calcPoint * oldLnReserved;
        totalAdjustUnit += calcPoint * newLnReserved;

        region2totalAdjustUnit[stakeInfo.region] -= stakeInfo.calcPoint * oldLnReserved;
        region2totalAdjustUnit[stakeInfo.region] += calcPoint * newLnReserved;

        // update machine rewards
        //        _updateMachineRewards(machineId, machineShares, totalDistributedRewardAmount, totalBurnedRewardAmount);
        uint256 regionRewardsPerSeconds = getRegionRewardsPerSeconds(stakeInfo.region);
        _updateMachineRewardsOfRegion(machineId, machineShares, stakeInfo.region, regionRewardsPerSeconds);

        totalCalcPoint = totalCalcPoint - stakeInfo.calcPoint + calcPoint;

        stakeInfo.calcPoint = calcPoint;
        if (reserveAmount > stakeInfo.reservedAmount) {
            rewardToken.transferFrom(stakeInfo.holder, address(this), reserveAmount - stakeInfo.reservedAmount);
        }
        if (reserveAmount != stakeInfo.reservedAmount) {
            totalReservedAmount = totalReservedAmount + reserveAmount - stakeInfo.reservedAmount;
            stakeInfo.reservedAmount = reserveAmount;
        }
    }

    /**
     * @dev Calculates the total reward amount for a machine
     * @param machineId ID of the machine
     * @return uint256 Total reward amount
     */
    function getReward(string memory machineId) public view returns (uint256) {
        StakeInfo memory stakeInfo = machineId2StakeInfos[machineId];
        if (stakeInfo.lastClaimAtTimestamp > stakeInfo.endAtTimestamp && stakeInfo.endAtTimestamp > 0) {
            return 0;
        }
        uint256 machineShares = _getMachineShares(stakeInfo.calcPoint, stakeInfo.reservedAmount);
        uint256 regionTotalShares = region2totalAdjustUnit[stakeInfo.region];
        RewardCalculatorLib.UserRewards memory machineRewards = machineId2StakeUnitRewards[machineId];

        uint256 regionRewardsPerSeconds = getRegionRewardsPerSeconds(stakeInfo.region);
        RewardCalculatorLib.RewardsPerShare memory currentRewardPerCalcPoint =
            _getUpdatedRegionRewardPerCalcPoint(regionTotalShares, regionRewardsPerSeconds, stakeInfo.region);
        //            _getUpdatedRewardPerCalcPoint(totalDistributedRewardAmount, totalBurnedRewardAmount, regionTotalShares);
        uint256 rewardAmount = RewardCalculatorLib.calculatePendingMachineRewards(
            machineShares, currentRewardPerCalcPoint.accumulatedPerShare, machineRewards.lastAccumulatedPerShare
        );

        return machineRewards.accumulated + rewardAmount;
    }

    function _reportMachineFault(string memory machineId, uint256 slashId) internal {
        if (!rewardStart()) {
            return;
        }

        StakeInfo memory stakeInfo = machineId2StakeInfos[machineId];
        tryPaySlashOnReport(stakeInfo, machineId, slashId, slashPayToAddress);

        _claim(machineId);
        _unStake(machineId, stakeInfo.holder);
    }

    function addSlashInfoAndReport(SlashInfo memory slashInfo) internal {
        uint256 slashId = machine2LastSlashId[slashInfo.machineId];
        slashId++;
        machine2LastSlashId[slashInfo.machineId] = slashId;
        slashId2SlashInfo[slashId] = slashInfo;
        _reportMachineFault(slashInfo.machineId, slashId);
        emit ReportMachineFault(slashInfo.machineId, slashId, slashPayToAddress);
    }

    function newSlashInfo(address slasher, string memory machineId, uint256 slashAmount)
        internal
        view
        returns (SlashInfo memory)
    {
        SlashInfo memory slashInfo = SlashInfo({
            stakeHolder: slasher,
            machineId: machineId,
            slashAmount: slashAmount,
            createdAt: block.timestamp,
            paid: false
        });
        return slashInfo;
    }

    /**
     * @dev Handles notifications from DBCAI contract about machine status changes
     * @param tp Type of notification (ContractRegister, MachineOffline, MachineOnline)
     * @param machineId ID of the machine (if applicable)
     * @return bool True if notification was processed successfully
     */
    function notify(NotifyType tp, string calldata machineId) external onlyDBCAIContract returns (bool) {
        if (tp == NotifyType.ContractRegister) {
            registered = true;
            return true;
        }

        bool _isStaking = isStaking(machineId);
        if (!_isStaking) {
            return false;
        }

        if (tp == NotifyType.MachineOffline) {
            _stopRewarding(machineId);
        } else if (tp == NotifyType.MachineOnline && isStakingButOffline(machineId)) {
            _recoverRewarding(machineId);
        }
        return true;
    }

    function isStakingButOffline(string calldata machineId) internal view returns (bool) {
        StakeInfo memory stakeInfo = machineId2StakeInfos[machineId];
        return stakeInfo.calcPoint == 0 && stakeInfo.nftCount > 0;
    }

    function _stopRewarding(string memory machineId) internal {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        _joinStaking(machineId, 0, stakeInfo.reservedAmount);

        emit ExitStakingForOffline(machineId, stakeInfo.holder);
    }

    function _recoverRewarding(string memory machineId) internal {
        StakeInfo storage stakeInfo = machineId2StakeInfos[machineId];
        if (stakeInfo.calcPoint != 0) {
            return;
        }
        (,,,,,, uint256 bandwidth) = dbcAIContract.machineBandWidthInfos(machineId);
        bandwidth = bandwidth * stakeInfo.nftCount;
        _joinStaking(machineId, bandwidth, stakeInfo.reservedAmount);
        emit RecoverRewarding(machineId, stakeInfo.holder);
    }

    /**
     * @dev Gets comprehensive machine information for DBC scan
     * @param machineId ID of the machine
     * @return MachineInfoForDBCScan Struct containing all machine information
     */
    function getMachineInfoForDBCScan(string memory machineId) external view returns (MachineInfoForDBCScan memory) {
        (, uint256 canClaimAmount,, uint256 claimedAmount) = getRewardInfo(machineId);
        //        uint256 totalRewardAmount = canClaimAmount + lockedAmount + claimedAmount;
        bool _isStaking = isStaking(machineId);
        (,, uint256 cpuCores, uint256 machineMem, string memory region, uint256 hdd, uint256 bandwidth) =
            dbcAIContract.machineBandWidthInfos(machineId);

        uint256 locked =
            machineId2LockedRewardDetail[machineId].totalAmount - machineId2LockedRewardDetail[machineId].claimedAmount;

        MachineInfoForDBCScan memory machineInfo = MachineInfoForDBCScan({
            isStaking: _isStaking,
            region: region,
            hdd: hdd,
            cpuCors: cpuCores,
            bandwidth: bandwidth,
            mem: machineMem,
            projectName: PROJECT_NAME,
            totalRewardAmount: locked + claimedAmount,
            lockedRewardAmount: locked,
            claimedRewardAmount: claimedAmount,
            canClaimRewardAmount: canClaimAmount
        });

        return machineInfo;
    }

    /**
     * @dev Gets the daily reward amount for a specific region
     * @param _region Name of the region
     * @return uint256 Daily reward amount for the region
     */
    function getRegionDailyRewardAmount(string memory _region) public view returns (uint256) {
        uint256 regionValue = region2Value[_region];
        uint256 regionDailyRewardAmount = (getDailyRewardAmount() * regionValue) / totalRegionValue;
        return regionDailyRewardAmount;
    }

    /**
     * @dev Pre-calculates potential rewards for staking parameters
     * @param region Region where the machine will be staked
     * @param calcPoint Calculation points for the machine
     * @param nftCount Number of NFTs to stake
     * @param reserveAmount Amount to reserve
     * @return uint256 Estimated daily rewards
     */
    function preCalculateRewards(string memory region, uint256 calcPoint, uint256 nftCount, uint256 reserveAmount)
        public
        view
        returns (uint256)
    {
        calcPoint = calcPoint * nftCount;
        uint256 machineShares = _getMachineShares(calcPoint, reserveAmount);
        uint256 regionTotalShares = region2totalAdjustUnit[region] + machineShares;
        RewardCalculatorLib.UserRewards memory machineRewards;
        machineRewards.accumulated = 0;
        machineRewards.lastAccumulatedPerShare = region2RewardPerCalcPoint[region].accumulatedPerShare;

        uint256 regionRewardsPerSeconds = getRegionRewardsPerSeconds(region);

        if (machineRewards.lastAccumulatedPerShare == 0) {
            return regionRewardsPerSeconds * 1 days;
        }

        RewardCalculatorLib.RewardsPerShare memory currentRewardPerCalcPoint =
            _getOneDayUpdatedRegionRewardPerCalcPoint(regionTotalShares, regionRewardsPerSeconds, region);
        //            _getUpdatedRewardPerCalcPoint(totalDistributedRewardAmount, totalBurnedRewardAmount, regionTotalShares);
        uint256 rewardAmount = RewardCalculatorLib.calculatePendingMachineRewards(
            machineShares, currentRewardPerCalcPoint.accumulatedPerShare, machineRewards.lastAccumulatedPerShare
        );

        return machineRewards.accumulated + rewardAmount;
    }
}

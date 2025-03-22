deeplink长租竞赛质押合约接口文档(dbcscan)
================

## 描述
deeplink长租竞赛质押合约是用于管理 NFT 质押的智能合约。它提供了多种功能，包括质押、解质押、领取奖励等。

## 合约地址(测试网)
    质押合约：0x995ddda33a7434c6080f45d98dda62721dd6f019
    nft: 0x905dE58579886C5afe9B6406CFDE82bd6a1087C1
    dlc token: 0xC8b47112D5413c6d06D4BB7573fD903908246614

## 函数接口
### `stake(address holder, string calldata machineId, calldata nftTokenIds,uint256[] calldata nftTokenIdBalances) public nonReentrant`
- 描述：质押nft
- 参数：
    - `holder`: 质押人地址 
    - `machineId`: 机器 ID
    - `nftTokenIds`: NFT Token ID 数组
    - `nftTokenIdBalances`: NFT Token ID 数量数组
- 返回值：无
- 事件：
    - `staked`: 质押NFT成功事件

### `addDLCToStake(string calldata machineId, uint256 amount) public nonReentrant`
- 描述：质押dlc
- 参数：
    - `machineId`: 机器 ID
    - `amount`: 质押金额 可以为0 单位为wei
- 返回值：无
- 事件：
    - `reseveDLC`: 质押DLC成功事件

### `unStake(string calldata machineId) public nonReentrant`
- 描述：解质押 只能被质押人或者管理员钱包调用
- 参数：
    - `machineId`: 机器 ID
- 返回值：无
- 事件：
    - `unStaked`: 解质押成功事件

### `claim(string calldata machineId) public`
- 描述：领取奖励 只能被质押人调用
- 参数：
    - `machineId`: 机器 ID
- 返回值：无
- 事件：
    - `claimed`: 领取奖励成功事件

### `getMachineInfoForDBCScan(string calldata machineId) external view returns (MachineInfoForDBCScan memory)`
- 描述：获取机器信息
- 参数：
    - `machineId`: 机器 ID
- 返回值：`MachineInfoForDBCScan`


### `getDailyRewardAmount() public view returns (uint256)`
- 描述：每日奖励数量

### `getStakeEndTimestamp(string calldata machineId) public view returns(uint256)`
- 描述：获取质押结束时间
- 参数：
    - `machineId`: 机器 ID
- 返回值：uint256 质押结束时间戳(seconds)

```solidity
 struct MachineInfoForDBCScan {
        bool isStaking;  // 是否在质押
        string region; // 地区
        uint256 hdd; // 硬盘
        uint256 bandwidth; // 带宽
        uint256 mem;     // 内存大小 G
        uint256 cpuCors; // cpu核数
        string  projectName;  // 项目名字
        uint256 totalRewardAmount;    // 总奖励数量
        uint256 claimedRewardAmount;  // 已领取奖励数量
        uint256 lockedRewardAmount;    // 锁仓奖励数量
    }
```



## 全局变量
- 'totalStakingGpuCount' uint256 : 当前处于质押状态GPU的总数量

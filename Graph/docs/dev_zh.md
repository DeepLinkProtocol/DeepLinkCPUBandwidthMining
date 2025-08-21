## Development

## graphql主网url：http://54.179.233.88:8032/subgraphs/name/bandwidth-staking-state 

## 对象实体定义:

```graphql
    type StateSummary @entity {
        id: Bytes!
        totalStakingGPUCount: BigInt! # uint256 总机器数
        totalBurnedReward: BigInt! # uint256 总销毁数
        totalReservedAmount: BigInt! # uint256 总质押数
    }
```

```graphql
    type StakeHolder @entity {
    id: Bytes!
    holder: Bytes! # address 矿工地址
    totalCalcPoint: BigInt! # uint256  总的机器原始算力 (不包含质押nft/租用等行为 对算力的增幅)
    fullTotalCalcPoint: BigInt! # uint256 总的机器膨胀算力 (包含质押nft/租用等行为 对算力的增幅)
    totalGPUCount: BigInt! # uint256 总的参与过质押的gpu个数
    totalStakingGPUCount: BigInt! # uint256 总的处于质押中的gpu个数
    rentedGPUCount: BigInt! # uint256 被租用中的gpu个数
    totalReservedAmount: BigInt! # uint256 质押的总金额
    burnedRentFee: BigInt! # uint256 已销毁的租用费用
    totalClaimedRewardAmount: BigInt! # uint256 已领取的奖励金额
    totalReleasedRewardAmount: BigInt! # uint256 已释放的奖励金额
    blockNumber: BigInt!
    blockTimestamp: BigInt!
    transactionHash: Bytes!
```

```graphql
    type MachineInfo @entity {
        id: Bytes!
        holder: Bytes! # address 矿工地址
        holderRef: StakeHolder! @belongsTo(field: "holder")  # 关联的矿工对象
        machineId: String! # string 机器id
        totalCalcPoint: BigInt! # uint256  总的机器原始算力 (不包含质押nft/租用等行为 对算力的增幅)
        totalCalcPointWithNFT: BigInt! # uint256  总的机器算力 (包含质押nft 对算力的增幅)
        fullTotalCalcPoint: BigInt! # uint256 总的机器算力 (包含质押nft/租用等行为 对算力的增幅)
        totalReservedAmount: BigInt! # uint256 质押的总金额
        burnedRentFee: BigInt! # uint256 已销毁的租用费用
        blockNumber: BigInt!
        blockTimestamp: BigInt!
        transactionHash: Bytes!
        
        stakeEndTimestamp: BigInt! # uint256 质押结束时间戳（秒）
        nextCanRentTimestamp: BigInt! # uint256 下次可租用时间戳（秒）
        isStaking: Boolean! # 是否处于质押状态
        online: Boolean! # 是否在线
        registered: Boolean! # 是否注册
        gpuType: String! # string gpu类型

        totalClaimedRewardAmount: BigInt! # uint256 已领取的总奖励金额
        totalReleasedRewardAmount: BigInt! # uint256 已释放的奖励金额
        region: String! # string 区域名字
    }
```

```graphql
    type RegionInfo @entity {
        id: Bytes!
        region: String!   // 区域名字 *
        stakingMachineCount: BigInt! # uint256 // 区域内质押中的机器总数 *
        stakingBandwidth: BigInt! # uint256  // 区域内质押中的总带宽 *
        reservedAmount: BigInt! # uint256  // 区域内质押的总金额 *
        burnedAmount: BigInt! # uint256  // 区域内已销毁的非活跃金额 *
        machineInfos: [MachineInfo!]!  // 区域内的机器信息
    }



```
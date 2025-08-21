# BandWidthStaking 项目文档

本文档概述了 BandWidthStaking 项目，包括其结构、组件和用法。

## 项目结构

该项目分为两个主要部分：`BandWidthStakingContract(智能合约)` 和 `Graph(子图)`。

```
.
├── BandWidthStakingContract/
│   ├── .env.example
│   ├── .gitmodules
│   ├── LICENSE
│   ├── Makefile
│   ├── broadcast/
│   ├── docs/
│   │   └── dev_zh.md
│   ├── foundry.toml
│   ├── lib/
│   │   ├── abdk-libraries-solidity/
│   │   ├── forge-std/
│   │   ├── foundry-devops/
│   │   ├── openzeppelin-contracts/
│   │   ├── openzeppelin-contracts-upgradeable/
│   │   └── openzeppelin-foundry-upgrades/
│   ├── remappings.txt
│   ├── script/
│   │   ├── Deploy.s.sol
│   │   └── Upgrade.s.sol
│   ├── src/
│   │   ├── NFTStaking.sol
│   │   ├── NFTStakingOld.sol
│   │   ├── OldRewardCalculater.sol
│   │   ├── RewardCalculater.sol
│   │   ├── interface/
│   │   └── library/
│   └── test/
│       ├── MockERC1155.t.sol
│       ├── MockRewardToken.sol
│       └── NFTStaking.t.sol
├── Graph/
│   ├── .prettierrc
│   ├── abis/
│   │   └── NFTStaking.json
│   ├── docker-compose.yml
│   ├── docs/
│   │   └── dev_zh.md
│   ├── networks.json
│   ├── package-lock.json
│   ├── package.json
│   ├── schema.graphql
│   ├── src/
│   │   └── nft-staking.ts
│   ├── subgraph.yaml
│   ├── tests/
│   │   ├── nft-staking-utils.ts
│   │   ├── nft-staking.test.ts
│   │   ├── rent-utils.ts
│   │   └── rent.test.ts
│   ├── tsconfig.json
│   └── yarn.lock
├── README.md
└── docs/
    └── doc.md
```

### BandWidthStakingContract

此目录包含用于 NFT 质押功能的 Solidity 智能合约 部署/升级脚本见Makefile。

- **src/**: 包含核心智能合约逻辑。
    - `NFTStaking.sol`: 主要的质押合约。
    - `RewardCalculater.sol`: 处理奖励计算。
- **script/**: 部署和升级脚本。
- **test/**: 智能合约的测试文件。
- **lib/**: 包含第三方库，如 OpenZeppelin。


### Graph

此目录包含用于索引和查询区块链数据的子图。

- **subgraph.yaml**: 子图的清单文件。
- **schema.graphql**: 定义要索引的数据的 GraphQL 模式。
- **src/**: 用于处理来自智能合约事件的映射文件。

### 先决条件

- [Foundry](https://getfoundry.sh/)
- [Node.js](https://nodejs.org/)
- [Yarn](https://yarnpkg.com/)
- [Docker](https://www.docker.com/)

# JUDGE CONTRACTS
***Tiny change to sync legacyV1 branch
## Summary
*The JudgeToken ecosystem is a modular set of contracts thats includes the following:*

- **JudgeToken**: This is the ERC20 token contract that defines the rules for the JUDGE governance token.
- **JudgeTreasury**: This is the project safe treasury that does funding for the Rewards Manager contract, teams, and itself.
- **JudgeStaking**: Staking contract with defined rules for staking and rewards with JudgeToken, open to all participants..
- **RewardsManager**: This is the rewards distributor contract for base and bonus rewards handling.

**The contracts were built with OpenZeppelin Access control for role based administration and also includes robust recovery systems to make accidental transfers of ERC20 tokens**

## *Contracts Overview*

### 1. JudgeToken
*ERC20 token with the following details:*
- **Max Supply**: 500_000_000 JUDGE
- **Burnable**
- **ERC20Permit** (gasless approvals)
- **ERC20Votes**: Delegation style governance


**The JudgeToken contract defines allocation for:** <br>
- Staking Rewards
- Team Funding

### 2. JudgeTreasury
*Acts as the fund manager contract for the ecosystem* <br> <br>
**Features**: 
- Can mint tokens to self
- Can fund rewards manager contracts for staking rewards
- Handles team funding too
- Supports sending bonus rewards to the staking pool.
<br> **NOTE**: Bonus rewards can only be sent to the rewards manager contract if the base quarterly reward for current quarter has been paid
- Includes recovery function for JUDGE and other ERC20 tokens. A defined fee is paid for token recovery.

### 3. Rewards Manager
*Distributes rewards to stakers in the JudgeStaking contract during claim or withdrawals* <br> <br>
**Handles**: 
- Payment of quarterly rewards (sent from Treasury)
- Payment of optional bonus rewards
- Provides JudgeStaking with the hooks below to enable claim: <br>
`sendRewards()` <br>
`sendBonus()`
- **NOTE**: Bonus rewards can only be sent to the rewards manager contract if the base quarterly reward for current quarter has been paid.
- Includes recovery function for JUDGE and other ERC20 tokens. A defined fee is paid for token recovery.

### 4. Judge Staking
*This is the core staking contract where users can lock their JUDGE tokens to earn pro-rata rewards* <br> <br>
**Reward Accounting**: 
- It uses `accJudgePerShare` and `accBonusJudgePerShare` to calculate user earnings over a number of blocks
**Key Functions**: 
- The `deposit()` function allows any address to participate in the staking contract by staking JUDGE tokens
- Users can use the `claimRewards()` function to withdraw their rewards while still having their stakes in the pool
- The `withdraw()` function when called claims pending rewards and withdraws specified amount for the target stake to the user wallet.
- The `withdrawAll()` function when called claims pending rewards and withdraws all the target stake balance to the user wallet.
- The `earlyWithdraw()` function when called claims pending rewards and withdraws specified amount for the target stake to the user wallet (penalty applies). The penalty is dependent on two the defined `earlyWithdrawalPenaltyPercent` and the lockup duration.
- The `emergencyWithdraw()` function is an admin-only, one time function call that returns all stakes and rewards to all participants of the staking pool at the block of calling the function
- It includes the token recovery function (recovery fee applies)

**Integration**:
- Interacts with the Rewards Manager contract to distribute base and bonus rewards

## Security Features
- Built with OpenZeppelin Access Control contract to support role based permissions across all contracts
- Multiple gatekeepers and modifiers to handle edge cases
- Recovery functions for all ERC20 tokens in all contracts except JUDGE Token contract itself

## Deployment Notes
*The contracts are dependent on one another. You can correctly deploy them in this order*
- `JudgeToken.sol`
- `RewardsManager.sol`
- `JudgeStaking.sol`
- `JudgeTreasury.sol` <br> <br>
**Grant neccesary roles across contracts to allow secure and seamless interactions. Some examples below:**
- Grant Judge Treasury address the `MINTER_ROLE()` from Judge Token contract
- Grant Jusge Staking address the `REWARDS_DISTRIBUTOR_ROLE()`

---
## Getting Started (Developer)
### Pre-requisites
- Install foundry on linux or WSL for windows
```shell
$ curl -L https://foundry.paradigm.xyz | bash
```
- Clone Repo
```shell
$ git clone https://github.com/raymondabiola/JUDGE-Token-Contract.git
```
- Change directory
```shell
$ cd JUDGE-Token-Contract
```
- Install solidity dependencies (OZ version 5.3.0 most suitable for this project)
```shell
$ forge install OpenZeppelin/openzeppelin-contracts@v5.3.0
```
- Compile Contracts
```shell
$ forge build
```
- Run test suite
```shell
$ forge test
```
**Deploy Contracts** <br>
*Create a .env file in the project root and input the following inside it:*
- `INFURA_API_URL`, `PRIVATE_KEY`, `ETHERSCAN_API_KEY`
- The infura api url looks like this `INFURA_API_URL=https://sepolia.infura.io/v3/YOUR_PROJECT_ID`. You can get your infura `PROJECT_ID` from the [Infura Website](https://www.infura.io/)
- You can get your etherscan api key from [EtherScan Website](https://etherscan.io/)
*The deploy script is found in `scripts/DeployJudgeContracts.sol`*
- Run the script command below to simulate deployment on sepolia testnet
```shell
$ forge script script/DeployJudgeContracts.s.sol:DeployJudgeContracts --rpc-url $INFURA_API_URL
```
- Run the script command below to actually deploy and also verify the contracts on the sepolia testnet
```shell
$ forge script script/DeployJudgeContracts.s.sol:DeployJudgeContracts \
  --rpc-url $INFURA_API_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --chain-id 11155111
```
**The script will:**
- Deploy all contracts, set key parameters,and grant neccesary roles. You need to grant other needed roles after deployment

## Deployed Instances on [Sepolia Testnet](https://sepolia.etherscan.io/)
- **JudgeToken Contract Address:** [`0x167043a312d6c3b8c4b5b741225173e65ff45d9a`](https://sepolia.etherscan.io/address/0x167043a312d6c3b8c4b5b741225173e65ff45d9a)
- **JudgeTreasury Contract Address:** [`0xa370652da3773ad361b7b8075ccdc25475882a06`](https://sepolia.etherscan.io/address/0xa370652da3773ad361b7b8075ccdc25475882a06)
- **RewardsManager Contract Address:** [`0xf3d4832ed9374ec13d8f1c15dcdc8b88a539dc14`](https://sepolia.etherscan.io/address/0xf3d4832ed9374ec13d8f1c15dcdc8b88a539dc14)
- **JudgeStaking Contract Address:** [`0xf18c858a94661dc4524cd7973a81c910ccb6e6fd`](https://sepolia.etherscan.io/address/0xf18c858a94661dc4524cd7973a81c910ccb6e6fd)

### Help
```shell
$ forge --help
$ anvil --help
$ cast --help
```
## License
MIT

## Built With
[Solidity](https://docs.soliditylang.org/en/v0.8.30/) <br>
[Foundry](https://getfoundry.sh/) <br>
[Openzeppelin](https://docs.openzeppelin.com/) <br>

## Author
Built with 🤍 by Raymond Abiola <br>
Feel free to [follow my Github account](https://github.com/raymondabiola) or fork this repo for learning and testing.

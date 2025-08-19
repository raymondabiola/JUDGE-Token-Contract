# JUDGE CONTRACTS

*The JudgeToken ecosystem is a modular set of contracts thats includes the following:*

- **JudgeToken**: This is the ERC20 token contract that defines the roles for the JUDGE governance token.
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
*Acts as the fund manager contract for the ecosystem* <br>
**Features**: 
- Can mint tokens to self
- Can fund rewards manager contracts for staking rewards
- Handles team funding too
- Supports sending bonus rewards to the staking pool. <br>**NOTE**: Bonus rewards can only be sent to the rewards manager contract if the base quarterly reward for current quarter has been paid.
- Includes recovery function for JUDGE and other ERC20 tokens. A defined fee is paid for token recovery.

### 3. Rewards Manager
*Distributes rewards to stakers in the JudgeStaking contract during claim or withdrawals* <br>
**Handles**: 
- Payment of quarterly rewards (sent from Treasury)
- Payment of optional bonus rewards
- Provides JudgeStaking with the hooks below to enable claim: <br>
`sendRewards()` <br>
`sendBonus()`
- **NOTE**: Bonus rewards can only be sent to the rewards manager contract if the base quarterly reward for current quarter has been paid.
- Includes recovery function for JUDGE and other ERC20 tokens. A defined fee is paid for token recovery.

### 4. Judge Staking
*This is the core staking contract where users can lock their JUDGE tokens to earn pro-rata rewards* <br>
**Reward Accounting**: 
- It uses `accJudgePerShare` and `accBonusJudgePerShare` to calculate user earnings over a number of blocks
**Key Functions**: 
- The `deposit()` function allows any address to participate in the staking contract by staking JUDGE tokens
- Users can use the `claimRewards()` function to withdraw their rewards while still having their stakes in the pool
- The `withdraw()` function when called claims pending rewards and withdraws specified amount for the target stake to the user wallet.
- The `withdrawAll()` function when called claims pending rewards and withdraws all the target stake balance to the user wallet.
- The `earlyWithdraw()` function when called claims pending rewards and withdraws specified amount for the target stake to the user wallet (penalty applies). The penalty is dependent on two the defined `earlyWithdrawalPenaltyPercent` and the lockup duration.

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

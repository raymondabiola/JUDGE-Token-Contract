## JUDGE CONTRACTS

**The JUDGE contracts includes the following:**

- **JudgeToken**: This is the ERC20 token contract that defines the roles for the JUDGE governance token.
- **JudgeTreasury**: This is the project safe treasury that does funding for the Rewards Manager contract, teams, and itself.
- **JudgeStaking**: Staking contract with defined rules for staking and rewards with JudgeToken, open to all participants..
- **RewardsManager**: This is the rewards distributor contract for base and bonus rewards handling.

## Documentation

https://book.getfoundry.sh/

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

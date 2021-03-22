# Debt Ceiling Instant Access Module

Automatic debt ceiling adjustments

## Overview

Minting too much DAI, even if well above collateralization ratios, can become too risky. Hence the *Debt Ceiling*, i.e. the maximum amount of DAI that can be minted for a specific collateral type.

In order to give the debt ceiling more flexibility, this Instant Access Module allows the broader community to adjust the debt ceiling within fixed parameters set forth by token holders.

Check out [MIP27](https://forum.makerdao.com/t/mip27-debt-ceiling-instant-access-module) for more details and discussions.

## Command-line usage

If you're interested in updating the debt ceiling of a collateral type (ETH-B in this example), follow these steps:

### 1. Get the contract addresses from the chainlog

```
$ export MCD_VAT=$(seth call 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F 'getAddress(bytes32)(address)' $(seth --from-ascii MCD_VAT | seth --to-bytes32))
$ export MCD_IAM_AUTO_LINE=$(seth call 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F 'getAddress(bytes32)(address)' $(seth --from-ascii MCD_IAM_AUTO_LINE | seth --to-bytes32))
```

### 2. Get the current debt ceiling from the vat

```
$ seth call $MCD_VAT 'ilks(bytes32)(uint256,uint256,uint256,uint256,uint256)' $(seth --from-ascii ETH-B | seth --to-bytes32) | sed -n 4p | seth --to-fix 45
5009714
```

This means that the current debt ceiling for ETH-B is 5,009,714 DAI.

### 3. Check the maximum debt ceiling from this module

```
$ seth call $MCD_IAM_AUTO_LINE 'ilks(bytes32)(uint256,uint256,uint48,uint48,uint48)' $(seth --from-ascii ETH-B | seth --to-bytes32) | sed -n 1p | seth --to-fix 45
6000000
```

### 4. If the debt ceiling is going to increase, make sure enough time has passed

Get the seconds elapsed since the last time the debt was increased:

```
$ echo "$(date +%s) - $(seth call $MCD_IAM_AUTO_LINE 'ilks(bytes32)(uint256,uint256,uint48,uint48,uint48)' $(seth --from-ascii ETH-B | seth --to-bytes32) | sed -n 5p)" | bc
4288088
```

Compare the above result with the minimum wait time:

```
$ seth call $MCD_IAM_AUTO_LINE 'ilks(bytes32)(uint256,uint256,uint48,uint48,uint48)' $(seth --from-ascii ETH-B | seth --to-bytes32) | sed -n 3p
43200
```

### 5. Update the debt ceiling

```
$ ETH_GAS=80000 seth send $MCD_IAM_AUTO_LINE 'exec(bytes32)' $(seth --from-ascii ETH-B | seth --to-bytes32)
seth-send: Published transaction with 36 bytes of calldata.
seth-send: 0xaeb25b838d1c96be038a065f79fa85c6bbff55ed64a13c7bc3bf83f3e8fa9f94
seth-send: Waiting for transaction receipt........
seth-send: Transaction included in block 23937434.
```

### 6. Check the new debt ceiling in the vat

```
seth call $MCD_VAT 'ilks(bytes32)(uint256,uint256,uint256,uint256,uint256)' $(seth --from-ascii ETH-B | seth --to-bytes32) | sed -n 4p | seth --to-fix 45
5021462
```

## Interface description

### `ilks(bytes32)`

This mapping stores all the information related to an ilk. You can obtain it with the following command:

```
seth call $MCD_IAM_AUTO_LINE 'ilks(bytes32)(uint256,uint256,uint48,uint48,uint48)' $(seth --from-ascii ETH-B | seth --to-bytes32)
50000000000000000000000000000000000000000000000000000
5000000000000000000000000000000000000000000000000000
43200
11723903
1611565389
```

Each line represents a different parameter for this `ilk` type. These are:
1. `line`: the maximum debt ceiling a collateral type can reach using this module
2. `gap`: the expected difference between a collateral's debt ceiling and its total debt
3. `ttl`: the minimum amount of seconds between debt ceiling increases
4. `last`: the block number at which the debt ceiling was updated using this module
5. `lastInc`: the timestamp at which the debt ceiling was increased using this module

### `exec(bytes32)`

This function updates the debt ceiling of a collateral type. It operates as follows:

1. If the collateral type is not part of the module, does nothing.
2. If an update is being made in the same block, does nothing.
3. A new debt ceiling is computed by adding the `gap` parameter to the collateral's current debt.
4. It makes sure this value doesn't exceed the maximum debt ceiling. If it does, sets it to the maximum debt ceiling.
5. If this new value increases the current debt ceiling, it makes sure enough time has passed by checking that the current time is bigger than `lastInc + ttl`. Otherwise does nothing.
6. Updates the debt ceiling in the `Vat` for this particular collateral.
7. Updates the total debt ceiling in the `Vat`.
8. Updates `last`.
9. If there was an increment in the debt ceiling, updates `lastInc`.
10. Emits an `Exec` event.

### `setIlk` and `remIlk`

These two functions allow Governance to add or remove collateral types to/from this module, and to update their parameters. They can only be called by means of an executive spell.

### `wards`, `rely` and `deny`

These are the components of the standard authorization mechanism of DSS. They can only be updated by governance.

## Development

If you want to maintain or update this module, install it by following these steps:

```
git clone https://github.com/makerdao/dss-auto-line --recursive
cd dss-auto-line
make test
```

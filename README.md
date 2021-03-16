# Debt Ceiling Instant Access Module

Automatic debt ceiling adjustments

## overview

Minting too much DAI, even if well above collateralization ratios, can become too risky. Hence the *Debt Ceiling*, i.e. the maximum amount of DAI that can be minted for a specific collateral type.

In order to give this debt ceiling more flexibility, this Instant Access Module allows the broader community to adjust the debt ceiling within fixed parameters set forth by tokenholders.

[MIP27](https://forum.makerdao.com/t/mip27-debt-ceiling-instant-access-module) describes this behavior with more detail.

## command-line usage

If you're interested in updating the debt ceiling of a collateral type (ETH-B in this example), follow these steps:

### 1. get the contract addresses from the chainlog

```
$ MCD_VAT=$(seth call 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F 'getAddress(bytes32)' $(seth --from-ascii MCD_VAT | seth --to-bytes32) | xargs seth --abi-decode "getAddress(bytes32)(address)")
$ MCD_IAM_AUTO_LINE=$(seth call 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F 'getAddress(bytes32)' $(seth --from-ascii MCD_IAM_AUTO_LINE | seth --to-bytes32) | xargs seth --abi-decode "getAddress(bytes32)(address)")
```

### 2. get the current debt ceiling from the vat

```
$ echo "$(seth call $MCD_VAT 'ilks(bytes32)' $(seth --from-ascii ETH-B | seth --to-bytes32) | xargs seth --abi-decode "ilks(bytes32)(uint256,uint256,uint256,uint256,uint256)" | sed -n 4p) / 10 ^ 45" | bc
5009714
```

This means that the current debt ceiling for ETH-B is 5,009,714 DAI.

### 3. check the max debt ceiling from the auto line IAM

```
$ echo "$(seth call $MCD_IAM_AUTO_LINE 'ilks(bytes32)' $(seth --from-ascii ETH-B | seth --to-bytes32) | xargs seth --abi-decode "ilks(bytes32)(uint256,uint256,uint48,uint48,uint48)" | sed -n 1p) / 10 ^ 45" | bc
6000000
```

### 4. if the debt ceiling is going to increase, make sure enough time has passed

get the seconds elapsed since the last time the debt was increased:

```
$ echo "$(date +%s) - $(seth call $MCD_IAM_AUTO_LINE 'ilks(bytes32)' $(seth --from-ascii ETH-B | seth --to-bytes32) | xargs seth --abi-decode "ilks(bytes32)(uint256,uint256,uint48,uint48,uint48)" | sed -n 5p)" | bc
4288088
```

compare the above result with the minimum wait time:

```
$ seth call $MCD_IAM_AUTO_LINE 'ilks(bytes32)' $(seth --from-ascii ETH-B | seth --to-bytes32) | xargs seth --abi-decode "ilks(bytes32)(uint256,uint256,uint48,uint48,uint48)" | sed -n 3p
43200
```

### 5. update the debt ceiling

```
$ seth send --gas 80000 $MCD_IAM_AUTO_LINE 'exec(bytes32)' $(seth --from-ascii ETH-B | seth --to-bytes32)
seth-send: Published transaction with 36 bytes of calldata.
seth-send: 0xaeb25b838d1c96be038a065f79fa85c6bbff55ed64a13c7bc3bf83f3e8fa9f94
seth-send: Waiting for transaction receipt........
seth-send: Transaction included in block 23937434.
```

### 6. check the new debt ceiling in the vat

```
echo "$(seth call $MCD_VAT 'ilks(bytes32)' $(seth --from-ascii ETH-B | seth --to-bytes32) | xargs seth --abi-decode "ilks(bytes32)(uint256,uint256,uint256,uint256,uint256)" | sed -n 4p) / 10 ^ 45" | bc
5021462
```

## interface description

### `ilks(bytes32)`

This mapping stores all the information related to an ilk. You can obtain it with the following command:

```
seth call $MCD_IAM_AUTO_LINE 'ilks(bytes32)' $(seth --from-ascii ETH-B | seth --to-bytes32) | xargs seth --abi-decode "ilks(bytes32)(uint256,uint256,uint48,uint48,uint48)"
50000000000000000000000000000000000000000000000000000
5000000000000000000000000000000000000000000000000000
43200
11723903
1611565389
```

Each line represents a different parameter for this ilk type. These are:
1. `line`: the maximum debt ceiling a collateral type can reach using this module
2. `gap`: the expected difference between a collateral's debt ceiling and its total debt
3. `ttl`: the minimum amount of seconds between debt ceiling increases
4. `last`: the block number at which the debt ceiling was updated using this module
5. `lastInc`: the timestampu at which the debt ceiling was increased using this module

### `exec(bytes32)`

This function updates the debt ceiling of a collateral type. It operates as follows:

1. If the collateral type is not part of the module, return.
2. If an update is being made in the same block, return.
3. A new debt ceiling is computed by adding the `gap` parameter to the collateral's current debt.
4. Make sure this value doesn't exceed the maximum debt ceiling. If it does, set it to the maximum debt ceiling.
5. If this new value increases the current debt ceiling, make sure enough time has passed by checking that the current time is bigger than `lastInc + ttl`. Otherwise return.
6. Update the debt ceiling in the vat for this particular collateral.
7. Update the total debt ceiling in the vat.
8. Update `last`.
9. If there was an increment in the debt ceiling, update `lastInc`.
10. Emit an event.

## development

If you are a developer and want to maintain or update this module, follow these steps:

```
git clone https://github.com/makerdao/dss-auto-line
cd dss-auto-line
dapp update
make test
```

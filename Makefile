all    :; dapp --use solc:0.6.7 build
clean  :; dapp clean
test   :; dapp --use solc:0.6.7 test --verbose
deploy :; dapp --use solc:0.6.7 create DssAutoLine

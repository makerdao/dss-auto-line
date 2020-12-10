all    :; SOLC_FLAGS="--optimize --optimize-runs=1000000" dapp --use solc:0.6.11 build
clean  :; dapp clean
test   :; SOLC_FLAGS="--optimize --optimize-runs=1000000" dapp --use solc:0.6.11 test --verbose
deploy-mainnet :; SOLC_FLAGS="--optimize --optimize-runs=1000000" dapp --use solc:0.6.11 build && dapp create DssAutoLine 0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B
deploy-kovan   :; SOLC_FLAGS="--optimize --optimize-runs=1000000" dapp --use solc:0.6.11 build && dapp create DssAutoLine 0xbA987bDB501d131f766fEe8180Da5d81b34b69d9

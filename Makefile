all    :; nix-build --no-out-link
test   :; nix-build --no-out-link --verbose
deploy-mainnet :; ln -sf -t . $$(nix-build --no-out-link)/dapp/*/{lib,out} && dapp create DssAutoLine 0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B
deploy-kovan   :; ln -sf -t . $$(nix-build --no-out-link)/dapp/*/{lib,out} && dapp create DssAutoLine 0xbA987bDB501d131f766fEe8180Da5d81b34b69d9

{ mkrpkgs ? import (fetchTarball "https://github.com/makerdao/makerpkgs/tarball/master") {}
, dappPkgs ? mkrpkgs.dappPkgsVersions.hevm-0_43_1
}: with dappPkgs;

let
  ds-test-src = fetchFromGitHub {
    owner = "dapphub";
    repo = "ds-test";
    rev = "eb7148d43c1ca6f9890361e2e2378364af2430ba";
    sha256 = "1phnqjkbcqg18mh62c8jq0v8fcwxs8yc4sa6dca4y8pq2k35938k";
  } + "/src";

  ds-test = buildDappPackage {
    src = ds-test-src;
    name = "ds-test";
    doCheck = false;
  };
in buildDappPackage {
  name = "dss-auto-line";
  src = ./src;
  deps = [ ds-test ];
  solc = mkrpkgs.solc-static-versions.solc_0_6_11;
  solcFlags = "--optimize --optimize-runs=1000000";
}

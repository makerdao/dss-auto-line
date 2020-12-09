{ dappPkgs ? (
    import (fetchTarball "https://github.com/makerdao/makerpkgs/tarball/master") {}
  ).dappPkgsVersions.master-20201209
}: with dappPkgs;

mkShell {
  buildInputs = [
    (dapp.override {
      solc = solc-static-versions.solc_0_6_11;
    })
  ];
}

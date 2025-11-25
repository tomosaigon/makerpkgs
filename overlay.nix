{ dapptoolsOverrides ? {} }:

self: super: with super;

let
  inherit (lib) mapAttrs;
  sources = import ./nix/sources.nix;

  dappSources = callPackage
    ./dapptools-overlay.nix
    { inherit dapptoolsOverrides; };

  dappPkgsVersions = mapAttrs
    (_: dappPkgsSrc: (import dappPkgsSrc {
      overrides = self: super: {
        semver-range = super.semver-range.override {
          src = super.fetchurl {
            url = "https://hackage.haskell.org/package/semver-range-0.2.8/semver-range-0.2.8.tar.gz";
            sha256 = "1df663zkcf7y7a8cf5llf111rx4bsflhsi3fr1f840y4kdgxlvkf";
          };
        };
      };
    }))
    dappSources;

  dappPkgs = if dappPkgsVersions ? current
    then dappPkgsVersions.current
    else dappPkgsVersions.default
    ;

  solc-static-versions = mapAttrs (n: v: runCommand "solc-${v.version}-static" {} ''
    mkdir -p $out/bin
    ln -s ${v}/bin/solc* $out/bin/solc
  '') dappPkgs.solc-static-versions;

  makerpkgs = { dapptoolsOverrides ? {} }: rec {
    inherit dappSources dappPkgsVersions dappPkgs solc-static-versions;

    # Inherit derivations from dapptools
    inherit (dappPkgs)
      dapp ethsign seth solc hevm solc-versions go-ethereum-unlimited evmdis
      solidityPackage
      ;

    setzer-mcd = self.callPackage sources.setzer-mcd {};

    sethret = (import sources.sethret { inherit pkgs; }).sethret;

    dapp2nix = import sources.dapp2nix { inherit pkgs; };

    abi-to-dhall = import sources.abi-to-dhall { inherit pkgs; };

    makerCommonScriptBins = with self; [
      coreutils gnugrep gnused findutils
      bc jq
      solc
      dapp ethsign seth
    ];

    makerScriptPackage = self.callPackage ./script-builder.nix {};
  };
in (makerpkgs { inherit dapptoolsOverrides; }) // {
  makerpkgs = makeOverridable makerpkgs { inherit dapptoolsOverrides; };
}

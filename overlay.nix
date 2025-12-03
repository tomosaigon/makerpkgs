{ dapptoolsOverrides ? {} }:

self: super: with super;

let
  inherit (lib) mapAttrs;
  sources = import ./nix/sources.nix;

  dappSources = callPackage
    ./dapptools-overlay.nix
    { inherit dapptoolsOverrides; };

  # 1. Load all the dapp package sets as-is (no extra overlays here).
  rawDappPkgsVersions = mapAttrs
    (_: dappPkgsSrc:
      import dappPkgsSrc {
        overlays = [];
      }
    )
    dappSources;

  # 2. Pick a "donor" package set that has a working hevm.
  #
  #    In the Maker repos this is usually "current"; if not present,
  #    fall back to "default".
  basePkgsForHevm =
    if rawDappPkgsVersions ? current
    then rawDappPkgsVersions.current
    else rawDappPkgsVersions.default;

  # 3. Override ONLY the hevm attribute inside the hevm-0_43_1 package set,
  #    so that anything asking for dappPkgsVersions."hevm-0_43_1".hevm
  #    actually gets the working hevm from basePkgsForHevm.
  dappPkgsVersions = rawDappPkgsVersions // {
    "hevm-0_43_1" =
      rawDappPkgsVersions."hevm-0_43_1" // {
        hevm = basePkgsForHevm.hevm;
      };
  };

  # 4. Keep the usual "current"/"default" selection logic for the main dappPkgs.
  dappPkgs = if dappPkgsVersions ? current
    then dappPkgsVersions.current
    else dappPkgsVersions.default;

  # 5. Static solc wrapper derivations (unchanged from upstream).
  solc-static-versions = mapAttrs (n: v: runCommand "solc-${v.version}-static" {} ''
    mkdir -p $out/bin
    ln -s ${v}/bin/solc* $out/bin/solc
  '') dappPkgs.solc-static-versions;

  # 6. Main makerpkgs attrset.
  makerpkgs = { dapptoolsOverrides ? {} }: rec {
    inherit dappSources dappPkgsVersions dappPkgs solc-static-versions;

    # Inherit derivations from dappPkgs.
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
in
  (makerpkgs { inherit dapptoolsOverrides; }) // {
    makerpkgs = makeOverridable makerpkgs { inherit dapptoolsOverrides; };

    # Globally override the Haskell semver-range package to use the Hackage tarball,
    # so any consumer (hevm, dapp, etc.) avoids the dead dmjio/semver-range@patch-1 GitHub tag.
    haskellPackages = super.haskellPackages.override (old: {
      overrides = lib.composeExtensions
        (old.overrides or (_: _: {}))
        (self-hs: super-hs: {
          semver-range =
            (super-hs.semver-range.override {})
              .overrideAttrs (oldAttrs: {
                src = builtins.trace
                  "SEMRANGE-HASKELL-OVERRIDE: using Hackage semver-range-0.2.8"
                  (super.fetchurl {
                    url    = "https://hackage.haskell.org/package/semver-range-0.2.8/semver-range-0.2.8.tar.gz";
                    sha256 = "1df663zkcf7y7a8cf5llf111rx4bsflhsi3fr1f840y4kdgxlvkf";
                  });
              });
        });
    });
  }
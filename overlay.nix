{ dapptoolsOverrides ? {} }:

self: super: with super;

let
  inherit (lib) mapAttrs;
  sources = import ./nix/sources.nix;

  dappSources = callPackage
    ./dapptools-overlay.nix
    { inherit dapptoolsOverrides; };


  dappPkgsVersions = mapAttrs
    (_: dappPkgsSrc:
      import dappPkgsSrc {
        overlays = [
          (self': super': {

            # Intercept the broken semver-range GitHub tarball used by dapptools/hevm
            fetchzip = args:
              let
                badUrl =
                  "https://github.com/dmjio/semver-range/archive/patch-1.tar.gz";

                hackageUrl =
                  "https://hackage.haskell.org/package/semver-range-0.2.8/semver-range-0.2.8.tar.gz";

                # Read url/urls without changing args yet
                url  = args.url  or "";
                urls = args.urls or [];

                # Normalise to one list for checking
                urlsList =
                  (if url != "" then [ url ] else []) ++ urls;

                needsFix = builtins.elem badUrl urlsList;

                extra =
                  if needsFix then {
                    # Force both url and urls to the Hackage tarball
                    url  = hackageUrl;
                    urls = [ hackageUrl ];
                  } else {};
              in
                super'.fetchzip (args // extra);

            haskellPackages = super'.haskellPackages.override (old: {
              overrides = super'.lib.composeExtensions
                (old.overrides or (_: _: {}))
                (self-hs: super-hs: {
                  semver-range =
                    (super-hs.semver-range.override {})
                      .overrideAttrs (oldAttrs: {
                        src = super'.fetchurl {
                          url =
                            "https://hackage.haskell.org/package/semver-range-0.2.8/semver-range-0.2.8.tar.gz";
                          sha256 =
                            "1df663zkcf7y7a8cf5llf111rx4bsflhsi3fr1f840y4kdgxlvkf";
                        };
                      });
                });
            });

          })
        ];
      }
    )
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

  # Fix semver-range-0.2.8 globally for the default Haskell package set
  # by redefining it from scratch (no dependency on the old patch-1 GitHub tag).
  haskellPackages = super.haskellPackages.override {
    overrides = self: super: {
      semver-range =
        super.callPackage
          ({ mkDerivation
           , base
           , classy-prelude
           , fetchurl
           , hspec
           , parsec
           , QuickCheck
           , text
           , unordered-containers
           }:
           mkDerivation {
             pname = "semver-range";
             version = "0.2.8";

             src = fetchurl {
               url    = "https://hackage.haskell.org/package/semver-range-0.2.8/semver-range-0.2.8.tar.gz";
               sha256 = "1df663zkcf7y7a8cf5llf111rx4bsflhsi3fr1f840y4kdgxlvkf";
             };

             libraryHaskellDepends = [
               base
               classy-prelude
               parsec
               text
               unordered-containers
             ];
             testHaskellDepends = [
               base
               hspec
               QuickCheck
             ];

             description =
               "Representation, manipulation, and de/serialisation of Semantic Versions";
           }) {};
    };
  };
}

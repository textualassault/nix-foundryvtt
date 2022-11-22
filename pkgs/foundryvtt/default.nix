{ lib
, callPackage
, stdenv
, buildNpmPackage
, coreutils
, findutils
, makeWrapper
, nodejs
, openssl
, pngout
, requireFile
, unzip
, gzip
, zstd
, brotli
, pkgs
, usePngout ? !(stdenv.isDarwin && stdenv.isAarch64)
}:

let
  foundryVersion = rec {
    version = "10.0.0+${build}";
    build = "290";
    shortVersion = "${lib.versions.major version}.${build}";
  };

  fetchNpmDeps = args: pkgs.fetchNpmDeps (args // {
    buildInputs = [ unzip ];
    setSourceRoot = ''
      if [[ "$curSrc" =~ FoundryVTT-${foundryVersion.shortVersion}.zip$ ]]; then
        sourceRoot=$(pwd)/resources/app
      fi
    '';
  });
in
buildNpmPackage.override { inherit fetchNpmDeps; } {
  pname = "foundryvtt";
  inherit (foundryVersion) version;

  src = requireFile {
    name = "FoundryVTT-${foundryVersion.shortVersion}.zip";
    sha256 = "sha256-OGjHsTbFMIRfsT8sZE/vtf1z+T+H2yp5R1MJndv0Vao=";
    url = "https://foundryvtt.com";
  };

  outputs = [ "out" "gzip" "zstd" "brotli" ];

  nativeBuildInputs = [ makeWrapper unzip gzip zstd brotli ];

  setSourceRoot = "sourceRoot=$(pwd)/resources/app";

  patches = [ ./package-lock-json.patch ];

  makeCacheWritable = true;
  npmDepsHash = "sha256-qQ9myNBdXmS+rl3Tb1Iy0k3/dU8LBhIVJhExqxvbIrs=";

  dontNpmBuild = true;

  postInstall = ''
    foundryvtt=$out/lib/node_modules/foundryvtt

    mkdir -p "$out/bin" "$out/libexec"
    ln -s "$foundryvtt/main.js" "$out/libexec/foundryvtt"
    chmod a+x "$out/libexec/foundryvtt"

    makeWrapper "$out/libexec/foundryvtt" "$out/bin/foundryvtt" \
      --prefix PATH : "${lib.getBin openssl}/bin"

    ln -s "$foundryvtt/public" "$out/public"

    # Run PNG images through `pngout` if it’s available.
    ${if usePngout then ''
      find "$foundryvtt/public" -name '*.png' -exec "${lib.getBin pngout}/bin/pngout" {} -k1 -y \;
    '' else ""}

    # Precompress assets for use with e.g., Caddy
    for method in gzip zstd brotli; do
      mkdir -p ''${!method}
      cp -R "$foundryvtt/public/"* ''${!method}
      find ''${!method} -name '*.png' -delete -or -name '*.jpg' -delete \
        -or -name '*.webp' -delete -or -name '*.wav' -delete -or -name '*.ico' -delete \
        -or -name '*.icns' -delete
    done

    find "$gzip" -type f -exec gzip -9 {} +
    find "$zstd" -type f -exec zstd -19 --rm {} +
    find "$brotli" -type f -exec brotli -9 --rm {} +
  '';

  meta = {
    homepage = "https://foundryvtt.com";
    description = "A self-hosted, modern, and developer-friendly roleplaying platform.";
    #license = lib.licenses.unfree;
    platforms = lib.lists.intersectLists nodejs.meta.platforms openssl.meta.platforms;
  };
}

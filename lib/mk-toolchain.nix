{ callPackage, lib, stdenv, zlib }:

name:
{ date, components }:

with builtins;
with lib;

let
  combine = callPackage ./combine.nix { };
  rpath = "${zlib}/lib:$out/lib";
in let
  toolchain = mapAttrs (component: source:
    stdenv.mkDerivation {
      pname = "${component}-nightly";
      version = source.date or date;
      src = fetchurl { inherit (source) url sha256; };
      installPhase = ''
        patchShebangs install.sh
        CFG_DISABLE_LDCONFIG=1 ./install.sh --prefix=$out

        rm $out/lib/rustlib/{components,install.log,manifest-*,rust-installer-version,uninstall.sh} || true

        ${optionalString stdenv.isLinux ''
          if [ -d $out/bin ]; then
            for file in $(find $out/bin -type f); do
              if isELF "$file"; then
                patchelf \
                  --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
                  --set-rpath ${rpath} \
                  "$file" || true
              fi
            done
          fi

          if [ -d $out/lib ]; then
            for file in $(find $out/lib -type f); do
              if isELF "$file"; then
                patchelf --set-rpath ${rpath} "$file" || true
              fi
            done
          fi

          ${optionalString (component == "rustc") ''
            for file in $(find $out/lib/rustlib/*/bin -type f); do
              if isELF "$file"; then
                patchelf \
                  --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
                  --set-rpath $out/lib \
                  "$file" || true
              fi
            done
          ''}

          ${optionalString (component == "llvm-tools-preview") ''
            for file in $out/lib/rustlib/*/bin/*; do
              patchelf \
                --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
                --set-rpath $out/lib/rustlib/*/lib \
                "$file" || true
            done
          ''}
        ''}

        ${optionalString (component == "clippy-preview") ''
          ${optionalString stdenv.isLinux ''
            patchelf \
              --set-rpath ${toolchain.rustc}/lib:${rpath} \
              $out/bin/clippy-driver || true
          ''}
          ${optionalString stdenv.isDarwin ''
            install_name_tool \
              -add_rpath ${toolchain.rustc}/lib \
              $out/bin/clippy-driver || true
          ''}
        ''}

        ${optionalString (component == "miri-preview") ''
          ${optionalString stdenv.isLinux ''
            patchelf \
              --set-rpath ${toolchain.rustc}/lib $out/bin/miri || true
          ''}
          ${optionalString stdenv.isDarwin ''
            install_name_tool \
              -add_rpath ${toolchain.rustc}/lib $out/bin/miri || true
          ''}
        ''}

        ${optionalString (component == "rls-preview") ''
          ${optionalString stdenv.isLinux ''
            patchelf \
              --set-rpath ${toolchain.rustc}/lib $out/bin/rls || true
          ''}
          ${optionalString stdenv.isDarwin ''
            install_name_tool \
              -add_rpath ${toolchain.rustc}/lib $out/bin/rls || true
          ''}
        ''}
      '';
      dontStrip = true;
      meta.platforms = platforms.all;
    }) components;

  toolchain' = toolchain // {
    toolchain = combine "${name}-${date}" (attrValues toolchain);

    rustc =
      combine "${name}-with-std-${date}" (with toolchain; [ rustc rust-std ])
      // {
        unwrapped = toolchain.rustc;
      };
    rustc-unwrapped = toolchain.rustc;

    clippy = toolchain.clippy-preview;
    miri = toolchain.miri-preview;
    rls = toolchain.rls-preview;
    rustfmt = toolchain.rustfmt-preview;
  };
in toolchain' // {
  withComponents = componentNames:
    combine "${name}-with-components-${date}"
    (attrVals componentNames toolchain');
}

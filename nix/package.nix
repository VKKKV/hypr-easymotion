/**
* nix/package.nix
* 构建渲染器，并把 Lua 模块、LICENSE 与 README 一并装进 $out。
*/
{
  lib,
  stdenv,
  zig,
  pkg-config,
  wayland,
  wayland-protocols,
  wayland-scanner,
  cairo,
  pango,
  libxkbcommon,
  glib,
  src,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "hypr-easymotion";
  version = "0.1.0";

  inherit src;

  nativeBuildInputs = [zig pkg-config wayland wayland-scanner wayland-protocols];
  buildInputs = [wayland cairo pango libxkbcommon glib];

  # build.zig 把 wayland-scanner 的输出写进 ./.zig-cache/protocol，
  # 构建树必须可写，且不能带上次的旧 glue。
  postPatch = ''
    rm -rf .zig-cache zig-out
  '';

  buildPhase = ''
    runHook preBuild
    export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-global-cache
    zig build -Doptimize=ReleaseSafe --prefix $out \
      --cache-dir $TMPDIR/zig-cache --build-id=sha1
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -d $out/share/hypr-easymotion
    install -m644 easymotion/*.lua $out/share/hypr-easymotion/
    install -Dm644 LICENSE $out/share/licenses/${finalAttrs.pname}/LICENSE
    install -Dm644 README.md $out/share/doc/${finalAttrs.pname}/README.md
    runHook postInstall
  '';

  meta = {
    description = "Hyprland easymotion window hints: Lua config module plus a Zig Wayland layer-shell renderer";
    homepage = "https://git.k174.dev/k/hypr-easymotion";
    license = lib.licenses.gpl3Plus;
    mainProgram = "easymotion-render";
    platforms = lib.platforms.linux;
    maintainers = [];
  };
})

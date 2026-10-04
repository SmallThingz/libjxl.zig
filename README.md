# JPEG XL for Zig

Zig **0.17.0** image encoding and decoding, backed by libjxl **0.11.1**.
The native `std.Build` graph compiles pinned libjxl, Highway, skcms and Brotli
sources directly. It does not invoke CMake, Python, shell build scripts, or a
system libjxl installation.

```zig
const jxl = @import("jxl");

const bytes = try jxl.encode(allocator, .{
    .width = 2,
    .height = 1,
    .format = .rgb,
    .pixels = &.{ 255, 0, 0, 0, 255, 0 },
}, .{});
defer allocator.free(bytes);

var image = try jxl.decode(allocator, bytes, .{});
defer image.deinit();
// image.pixels contains packed 8-bit sRGB pixels.
```

`ImageView` borrows its pixel slice for the duration of `encode`. The encoded
slice belongs to the caller. `decode` returns an owning `Image`; do not duplicate
its ownership, and call `deinit` exactly once. The allocator must outlive the
returned allocation. The codec's custom allocation hooks use that allocator;
upstream C++ containers may also use the system allocator. Calls
have no global initialization or mutable wrapper state.

Supported formats are `.gray`, `.gray_alpha`, `.rgb`, and `.rgba`, with straight
alpha. Encoding defaults to exact lossless pixels. Set `distance` to a positive
value for lossy compression, `effort` from 1 through 9, and `container = true`
for the JPEG XL container rather than a bare codestream.

Decoding produces 8-bit sRGB and applies the encoded orientation. Higher bit
depths are quantized to that output representation. Original-profile (non-XYB)
images must have structured sRGB color metadata; other original profiles,
including opaque ICC profiles, return `UnsupportedColorProfile` because libjxl
0.11.1 does not reliably convert those samples to the requested output profile.
Animation and non-alpha extra channels return `UnsupportedImage`. Metadata boxes
are not returned; trailing metadata after the image payload is not validated.
`max_bytes` limits the decoded pixel buffer (default 256 MiB),
not total codec working memory. A bounded allocator limits allocations routed
through the hooks, but cannot impose a process-wide memory budget.
Malformed data, premature EOF, invalid dimensions/options and allocation failures
return Zig errors. Advanced users may access `jxl.raw` with upstream C ownership
rules; the normal image API does not require raw handles or pointers.

## Build and use

Add this package with `zig fetch --save=jxl <package-url>` and import its module:

```zig
const dependency = b.dependency("jxl", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("jxl", dependency.module("jxl"));
```

```sh
zig build check -j1
zig build test -j2
zig build example -j2
zig build test -Doptimize=safe -j2
zig build test-build -Dtarget=aarch64-linux-gnu -j2
```

`test-build` compiles without executing target code. Foreign-target compilation
alone does not establish runtime compatibility. `zig build` installs the static
native library; Zig consumers should use the `jxl` module so headers, native
linking and generated configuration propagate automatically.

`check` type-checks the wrapper and its tests without compiling or linking the
native C++ libraries. `bindings` only generates the C declarations. Neither is a
substitute for the linked codec tests.

The default `-Dsimd=false` uses scalar Highway, disables AVX-512 fast encoding,
and uses the target baseline for skcms. This avoids Zig/Clang issue
[30907](https://codeberg.org/ziglang/zig/issues/30907) without requiring AVX-512
hardware. Compiler-selected baseline instructions still follow `-Dcpu`.
`-Dsimd=true` enables upstream SIMD dispatch. On affected x86 compilers, qualify
that configuration with an explicit `+evex512` CPU feature, for example:

```sh
zig build test-build -Dsimd=true -Dcpu=baseline+avx512f+avx512bw+avx512dq+avx512vl+evex512 -j2
```

That is a compile-only check. Do not run the resulting executable on hardware
that lacks the requested features. No SIMD performance claim is made here.

## API migration

This replaces the old C-shaped wrapper: global `init`, mirrored C structures,
and handle-based `Encoder`/`Decoder` methods are removed. Use `encode`, `decode`,
`ImageView`, and `Image` for still images; use the explicitly named `raw` escape
hatch for upstream features outside that API. The old build feature switches
are replaced by a single pinned native configuration and the `simd` option.

The wrapper uses the repository LICENSE. Native dependencies retain their own
licenses in their fetched source packages.

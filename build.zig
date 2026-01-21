const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
  const target = b.standardTargetOptions(.{});
  const optimize = b.standardOptimizeOption(.{});
  const build_jxl = b.option(bool, "static_jxl", "Build libjxl from source (use static linking)") orelse true;

  const mod = b.addModule("jxl", .{
    .root_source_file = b.path("root.zig"),
    .link_libc = true,
    .target = target,
    .optimize = optimize,
  });

  const options_step = b.addOptions();
  try initFeatures(b);
  options_step.addOption(bool, "boxes", features.boxes);
  options_step.addOption(bool, "threading", features.threading);
  options_step.addOption(bool, "jpeg_transcode", features.jpeg_transcode);
  options_step.addOption(bool, "3d_icc_tonemapping", features.@"3d_icc_tonemapping");
  options_step.addOption(bool, "jpegxl_tcmalloc", features.jpegxl_tcmalloc);
  options_step.addOption(bool, "icc", b.option(bool, "icc", "Enable support for ICC") orelse build_jxl);
  options_step.addOption(bool, "gain_map", b.option(bool, "gain_map", "Enable support for gain maps") orelse build_jxl);
  mod.addImport("config", options_step.createModule());

  const include_paths = b.option([]const []const u8, "include_paths", "the paths to include for the libjxl module")
    orelse if (build_jxl) &.{} else &[_][]const u8{"/usr/include/"};
  const r_paths = b.option([]const []const u8, "r_paths", "the paths to add to the rpath for the libjxl module")
    orelse if (build_jxl) &.{} else  &[_][]const u8{"/usr/lib/"};

  for (include_paths) |path| mod.addIncludePath(.{ .cwd_relative = path });
  for (r_paths) |path| mod.addRPath(.{ .cwd_relative = path });

  if (build_jxl) {
    try initOptions(b, target, optimize);
    mod.linkLibrary(try createJxl(b));
  } else {
    mod.linkSystemLibrary("jxl_cms", .{});
    if (features.threading) mod.linkSystemLibrary("jxl_threads", .{});
    mod.linkSystemLibrary("jxl", .{});
  }

  addTestStep(b, mod, target, optimize) catch {};
}

fn exists(path: []const u8) bool {
  std.fs.cwd().access(path, .{}) catch return false;
  return true;
}

fn addTestStep(b: *std.Build, mod: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !void {
  const test_step = b.step("test", "Run tests");
  const test_file_name = "test.zig";
  const test_runner_name = "test_runner.zig";

  // we don't care about time-of-check time-of-use race conditions as this is a simple test runner
  if (!exists(test_file_name)) return error.MissingTestFile;
  if (!exists(test_runner_name)) return error.MissingTestRunner;

  const tests = b.addTest(.{
    .root_module = b.createModule(.{
      .root_source_file = b.path(test_file_name),
      .target = target,
      .optimize = optimize,
    }),
    .test_runner = .{
      .path = b.path(test_runner_name),
      .mode = .simple,
    }
  });

  tests.root_module.addImport("jxl", mod);
  const run_tests = b.addRunArtifact(tests);
  test_step.dependOn(&run_tests.step);
}

const Features = struct {
  pub const Cms = enum { skcms, lcms2 };
  cms: Cms,
  boxes: bool,
  threading: bool,
  jpeg_transcode: bool,
  // jpeg_lib: bool,
  @"3d_icc_tonemapping": bool,
  jpegxl_tcmalloc: bool,
};

var features: Features = undefined;

fn initFeatures(b: *std.Build) !void {
  const threading = b.option(bool, "threading", "Enable Threading support") orelse true;
  features = .{
    .cms = b.option(Features.Cms, "cms", "Enable Color Management System") orelse .skcms,
    .boxes = b.option(bool, "boxes", "Enable support for the JXL container format (ISOBMFF \"boxes\")") orelse true,
    .threading = threading,
    .jpeg_transcode = b.option(bool, "jpeg_transcode", "Enable JPEG transcoding support") orelse true,
    // .jpeg_lib = b.option(bool, "jpeg_lib", "Builds the Jpegli library, a higher-performance JPEG encoder/decoder included in the JXL project") orelse true,
    .@"3d_icc_tonemapping" = b.option(bool, "3d_icc_tonemapping", "Enable 3D ICC tonemapping support, Essential for high-quality HDR-to-SDR conversion.") orelse true,
    .jpegxl_tcmalloc = b.option(bool, "jpegxl_tcmalloc", "Enable tcmalloc (speed up in multithreaded mode)") orelse threading,
  };
}

const Options = struct {
  target: std.Build.ResolvedTarget,
  optimize: std.builtin.OptimizeMode,
  c_flags: []const []const u8 = &[_][]const u8{ "-std=c11" },
  cxx_flags: []const []const u8 = &[_][]const u8{ "-std=c++20", "-fno-rtti", "-fno-omit-frame-pointer", "-fno-exceptions" },
  extensions: struct {
    sse4_2: bool,
    sse4_1: bool,
    avx2: bool,
    fma: bool,
    bmi: bool,
    bmi2: bool,
    avx512f: bool,
    avx512vl: bool,
    avx512bw: bool,
    avx512dq: bool,
    evex512: bool,
  },
  strip: bool,
  unwind_tables: std.builtin.UnwindTables,
  stack_protector: bool,
  stack_check: bool,
  red_zone: bool,
  omit_frame_pointer: bool,
  error_tracing: bool,
};
var options: Options = undefined;

const Feature = std.Target.x86.Feature;

fn initOptions(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !void {
  options = .{
    .target = target,
    .optimize = optimize,
    .extensions = undefined,
    .strip = b.option(bool, "lib_strip", "Strip symbols. Wrapper option is handled saperately") orelse (optimize != .Debug),
    .unwind_tables = b.option(std.builtin.UnwindTables, "lib_unwind_tables", "Unwind tables. Wrapper option is handled saperately") orelse .none,
    .stack_protector = b.option(bool, "lib_stack_protector", "Enable stack protection. Wrapper option is handled saperately") orelse false,
    .stack_check = b.option(bool, "lib_stack_check", "Enable stack check. Wrapper option is handled saperately") orelse (optimize == .Debug),
    .red_zone = b.option(bool, "lib_red_zone", "Enable red zone (saves instructions). Wrapper option is handled saperately") orelse true,
    .omit_frame_pointer = b.option(bool, "lib_omit_frame_pointer", "Enable omit frame pointer. Wrapper option is handled saperately") orelse true,
    .error_tracing = b.option(bool, "lib_error_tracing", "Enable error tracing. Wrapper option is handled saperately") orelse (optimize == .Debug),
  };

  options.extensions = .{
    .sse4_2 = target.result.cpu.has(.x86, .sse4_2),
    .sse4_1 = target.result.cpu.has(.x86, .sse4_1),
    .avx2 = target.result.cpu.has(.x86, .avx2),
    .fma = target.result.cpu.has(.x86, .fma),
    .bmi = target.result.cpu.has(.x86, .bmi),
    .bmi2 = target.result.cpu.has(.x86, .bmi2),
    .avx512f = target.result.cpu.has(.x86, .avx512f),
    .avx512vl = target.result.cpu.has(.x86, .avx512vl),
    .avx512bw = target.result.cpu.has(.x86, .avx512bw),
    .avx512dq = target.result.cpu.has(.x86, .avx512dq),
    .evex512 = target.result.cpu.has(.x86, .evex512),
  };
}

pub fn createJxl(b: *std.Build) !*std.Build.Step.Compile {
  const jxl_dep = b.dependency("libjxl", .{});
  const lib = b.addLibrary(.{
    .name = "jxl",
    .root_module = b.createModule(.{
      .target = options.target,
      .optimize = options.optimize,
      .strip = options.strip,
      .unwind_tables = options.unwind_tables,
      .stack_protector = options.stack_protector,
      .stack_check = options.stack_check,
      .red_zone = options.red_zone,
      .omit_frame_pointer = options.omit_frame_pointer,
      .error_tracing = options.error_tracing,
      .link_libc = true,
    }),
    .linkage = .static,
  });

  lib.addIncludePath(.{.cwd_relative = "/usr/include/"});
  lib.linkLibCpp();

  lib.root_module.addCMacro("JXL_INTERNAL_LIBRARY_BUILD", "1");
  if (options.extensions.avx512f) lib.root_module.addCMacro("FJXL_ENABLE_AVX512", "1");
  if (options.extensions.avx2) lib.root_module.addCMacro("FJXL_ENABLE_AVX2", "1");
  if (options.extensions.sse4_1) lib.root_module.addCMacro("FJXL_ENABLE_SSE4", "1");

  lib.root_module.addCMacro("JPEGXL_ENABLE_SKCMS", if (features.cms == .skcms) "1" else "0");
  lib.root_module.addCMacro("JPEGXL_ENABLE_LCMS2", if (features.cms == .lcms2) "1" else "0");
  switch (features.cms) {
    .skcms => try skcmsLib(b, lib),
    .lcms2 => try lcms2Lib(b, lib),
  }
  lib.root_module.addCMacro("JPEGXL_ENABLE_BOXES", if (features.boxes) "1" else "0");
  lib.root_module.addCMacro("JXL_THREADING", if (features.threading) "1" else "0");
  lib.root_module.addCMacro("JPEGXL_ENABLE_TRANSCODE_JPEG", if (features.jpeg_transcode) "1" else "0");
  // lib.root_module.addCMacro("JPEGXL_ENABLE_JPEGLI_LIBJPEG", if (features.jpeg_lib) "1" else "0");
  lib.root_module.addCMacro("JXL_ENABLE_3D_ICC_TONEMAPPING", if (features.@"3d_icc_tonemapping") "1" else "0");
  // lib.root_module.addCMacro("JPEGXL_ENABLE_TCMALLOC", if (features.jpegxl_tcmalloc) "1" else "0");

  lib.addConfigHeader(b.addConfigHeader(.{
    .style = .{ .cmake = jxl_dep.path("lib/jxl/version.h.in") },
    .include_path = "lib/jxl/version.h",
  }, .{
    .JPEGXL_VERSION = "0.11.1",
    .JPEGXL_MAJOR_VERSION = @as(u32, 0),
    .JPEGXL_MINOR_VERSION = @as(u32, 11),
    .JPEGXL_PATCH_VERSION = @as(u32, 1),
    .JPEGXL_NUMERIC_VERSION = @as(u32, 0x000B01),
  }));

  lib.addIncludePath(jxl_dep.path("")); 
  lib.addIncludePath(jxl_dep.path("include"));
  try addSourcesProcedural(b, lib, jxl_dep.path(""));

  try highwayLib(b, lib);
  try brotliLib(b, lib);

  return lib;
}

/// tests, benchmarks, and other non-library artifacts.
pub fn addSourcesProcedural(
  b: *std.Build,
  lib: *std.Build.Step.Compile,
  root_lazy: std.Build.LazyPath,
) !void {
  const search_root_abs = root_lazy.getPath2(b, &lib.step);

  var dir = try std.fs.cwd().openDir(search_root_abs, .{ .iterate = true });
  var walker = try dir.walk(b.allocator);
  defer walker.deinit();

  while (try walker.next()) |entry| {
    if (entry.kind != .file) continue;

    const path = entry.path;
    const ext = std.fs.path.extension(path);

    const is_c = std.mem.eql(u8, ext, ".c");
    const is_cpp = std.mem.eql(u8, ext, ".cpp") or std.mem.eql(u8, ext, ".cc");
    const is_source = is_c or is_cpp;
    if (!is_source) continue;

    // Skips tests, benchmarks, fuzzers, and CLI-only tools.
    const is_excluded = blk: {
      if (std.mem.indexOf(u8, path, "test") != null) break :blk true;
      if (std.mem.indexOf(u8, path, "benchmark") != null) break :blk true;
      if (std.mem.indexOf(u8, path, "bench_") != null) break :blk true;
      if (std.mem.indexOf(u8, path, "gbench") != null) break :blk true;
      if (std.mem.indexOf(u8, path, "fuzz") != null) break :blk true;
      if (std.mem.indexOf(u8, path, "nothing.cc") != null) break :blk true;
      if (std.mem.startsWith(u8, path, "plugins/")) break :blk true;
      if (std.mem.startsWith(u8, path, "tools/")) break :blk true;
      if (std.mem.startsWith(u8, path, "jpegli/")) break :blk true;
      if (std.mem.startsWith(u8, path, "extras/")) break :blk true;

      // Exclude threading code if threading is disabled
      if (features.threading and std.mem.indexOf(u8, path, "thread") != null) break :blk true;

      // Exclude main entry points for CLI tools
      const base = std.fs.path.basename(path);
      if (std.mem.eql(u8, base, "brotli.c")) break :blk true;
      if (std.mem.eql(u8, base, "cjxl_main.cc")) break :blk true;
      if (std.mem.eql(u8, base, "djxl_main.cc")) break :blk true;

      break :blk false;
    };

    if (is_excluded) continue;

    lib.addCSourceFile(.{
      .file = root_lazy.path(b, path),
      .flags = if (is_c) options.c_flags else options.cxx_flags,
    });
  }
}

fn skcmsLib(b: *std.Build, lib: *std.Build.Step.Compile) !void {
  const dep = b.dependency("skcms", .{});
  lib.addIncludePath(dep.path(""));

  if (options.extensions.avx512f and options.extensions.evex512) {
    lib.root_module.addCMacro("SKCMS_FORCE_AVX512", "1");
  }
  if (options.extensions.avx2 and options.extensions.fma and options.extensions.bmi2) {
    lib.root_module.addCMacro("SKCMS_FORCE_HSW", "1"); // "HSW" (Haswell) is the skcms target for AVX2 + FMA + BMI2
  }
  if (options.extensions.avx2) {
    lib.root_module.addCMacro("SKCMS_FORCE_AVX2", "1");
  }

  lib.addCSourceFile(.{.file = dep.path("skcms.cc"), .flags = options.cxx_flags});
}

fn lcms2Lib(b: *std.Build, lib: *std.Build.Step.Compile) !void {
  const dep = b.dependency("lcms2", .{});
  lib.addIncludePath(dep.path("include"));
  // Modern compilers (C++17/C11) deprecate the 'register' keyword.
  // LCMS2 is an older codebase, so we disable that keyword to prevent errors.
  lib.root_module.addCMacro("CMS_NO_REGISTER_KEYWORD", "1");
  try addSourcesProcedural(b, lib, dep.path("src"));
}

/// Procedurally adds Google Highway (SIMD abstraction)
fn highwayLib(b: *std.Build, lib: *std.Build.Step.Compile) !void {
  const dep = b.dependency("highway", .{});
  lib.root_module.addCMacro("HWY_STATIC_DEFINE", "1");
  lib.root_module.addCMacro("HWY_COMPILE_ALL_ATTRIBUTES", "1"); // use clang __attribute__ syntax

  lib.addIncludePath(dep.path(""));
  try addSourcesProcedural(b, lib, dep.path("hwy"));
}

/// Procedurally adds Brotli (Entropy coding)
fn brotliLib(b: *std.Build, lib: *std.Build.Step.Compile) !void {
  const dep = b.dependency("brotli", .{});
  lib.addIncludePath(dep.path("c/include"));
  try addSourcesProcedural(b, lib, dep.path("c"));
}

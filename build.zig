const std = @import("std");
const sources = @import("sources.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const simd = b.option(bool, "simd", "Enable Highway SIMD dispatch (requires compiler support)") orelse false;
    const jxl = b.dependency("libjxl", .{});
    const highway = b.dependency("highway", .{});
    const brotli = b.dependency("brotli", .{});
    const skcms = b.dependency("skcms", .{});
    const generated = b.addWriteFiles();
    _ = generated.add("jxl/jxl_export.h", "#define JXL_EXPORT\n#define JXL_NO_EXPORT\n#define JXL_DEPRECATED __attribute__((deprecated))\n#define JXL_DEPRECATED_EXPORT JXL_EXPORT JXL_DEPRECATED\n#define JXL_DEPRECATED_NO_EXPORT JXL_NO_EXPORT JXL_DEPRECATED\n");
    _ = generated.add("jxl/jxl_threads_export.h", "#define JXL_THREADS_EXPORT\n#define JXL_THREADS_NO_EXPORT\n");
    _ = generated.add("jxl/jxl_cms_export.h", "#define JXL_CMS_EXPORT\n#define JXL_CMS_NO_EXPORT\n");
    const version = b.addConfigHeader(.{ .style = .{ .cmake = jxl.path("lib/jxl/version.h.in") }, .include_path = "jxl/version.h" }, .{
        .JPEGXL_MAJOR_VERSION = @as(u32, 0),
        .JPEGXL_MINOR_VERSION = @as(u32, 11),
        .JPEGXL_PATCH_VERSION = @as(u32, 1),
    });
    const native = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true, .link_libcpp = true });
    native.addIncludePath(jxl.path(""));
    native.addIncludePath(jxl.path("lib/include"));
    native.addIncludePath(highway.path(""));
    native.addIncludePath(brotli.path("c/include"));
    native.addIncludePath(skcms.path(""));
    native.addIncludePath(generated.getDirectory());
    native.addConfigHeader(version);
    native.addCMacro("JXL_STATIC_DEFINE", "1");
    native.addCMacro("JXL_INTERNAL_LIBRARY_BUILD", "1");
    native.addCMacro("JPEGXL_ENABLE_SKCMS", "1");
    native.addCMacro("JPEGXL_ENABLE_LCMS2", "0");
    native.addCMacro("JPEGXL_ENABLE_BOXES", "1");
    native.addCMacro("JPEGXL_ENABLE_TRANSCODE_JPEG", "1");
    native.addCMacro("JXL_THREADING", "1");
    native.addCMacro("JXL_ENABLE_3D_ICC_TONEMAPPING", "1");
    native.addCMacro("HWY_STATIC_DEFINE", "1");
    if (!simd) native.addCMacro("HWY_COMPILE_ONLY_SCALAR", "1");
    if (!simd) native.addCMacro("FJXL_ENABLE_AVX512", "0");
    if (!simd) native.addCMacro("SKCMS_NO_RUNTIME_CPU_DETECTION", "1");
    const cpp_flags = &.{ "-std=c++17", "-fno-exceptions", "-fno-rtti" };
    native.addCSourceFiles(.{ .root = jxl.path(""), .files = sources.jxl, .flags = cpp_flags });
    native.addCSourceFiles(.{ .root = highway.path(""), .files = &.{ "hwy/abort.cc", "hwy/aligned_allocator.cc", "hwy/per_target.cc", "hwy/targets.cc" }, .flags = cpp_flags });
    native.addCSourceFiles(.{ .root = skcms.path(""), .files = &.{"skcms.cc"}, .flags = cpp_flags });
    native.addCSourceFiles(.{ .root = brotli.path(""), .files = sources.brotli, .flags = &.{"-std=c11"} });
    const lib = b.addLibrary(.{ .name = "jxl", .linkage = .static, .root_module = native });
    b.installArtifact(lib);
    const mod = b.addModule("jxl", .{ .root_source_file = b.path("root.zig"), .target = target, .optimize = optimize });
    mod.addIncludePath(jxl.path("lib/include"));
    mod.addIncludePath(generated.getDirectory());
    mod.addConfigHeader(version);
    mod.linkLibrary(lib);
    const bindings = b.addTranslateC(.{
        .root_source_file = generated.add("jxl.h", "#include <jxl/encode.h>\n#include <jxl/decode.h>\n#include <jxl/cms.h>\n"),
        .target = target,
        .optimize = optimize,
    });
    bindings.addIncludePath(jxl.path("lib/include"));
    bindings.addIncludePath(generated.getDirectory());
    bindings.addConfigHeader(version);
    mod.addImport("jxl_c", bindings.createModule());
    b.step("bindings", "Generate Zig declarations from the pinned C headers").dependOn(&bindings.step);
    const check_module = b.createModule(.{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "jxl_c", .module = bindings.createModule() }},
    });
    const wrapper_check = b.addTest(.{ .root_module = check_module, .use_llvm = true });
    b.step("check", "Type-check the wrapper and tests without building native libraries").dependOn(&wrapper_check.step);
    const tests = b.addTest(.{ .root_module = mod, .use_llvm = true, .use_lld = target.result.ofmt != .macho });
    b.step("test", "Run codec and ownership tests").dependOn(&b.addRunArtifact(tests).step);
    b.step("test-build", "Compile tests without executing target code").dependOn(&tests.step);
    const example = b.addExecutable(.{ .name = "roundtrip", .use_llvm = true, .use_lld = target.result.ofmt != .macho, .root_module = b.createModule(.{
        .root_source_file = b.path("examples/roundtrip.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    example.root_module.addImport("jxl", mod);
    b.step("example", "Run the in-memory image round trip").dependOn(&b.addRunArtifact(example).step);
}

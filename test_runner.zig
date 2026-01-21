const std = @import("std");
const builtin = @import("builtin");
// const jxl = if (@hasDecl((@import("root")), "c")) @import("root") else @import("jxl");

pub fn main() !void {
  const test_fns: []const std.builtin.TestFn = builtin.test_functions;
  // try jxl.init(.{});

  var passed: usize = 0;
  var failed: usize = 0;
  var skipped: usize = 0;

  for (test_fns) |test_fn| {
    if (test_fn.func()) |_| {
      std.debug.print("{s} => OK\n", .{test_fn.name});
      passed += 1;
    } else |err| {
      if (err == error.SkipZigTest) {
        std.debug.print("{s} => SKIPPED\n", .{test_fn.name});
        skipped += 1;
      } else {
        std.debug.print("{s} => FAILED ({s})\n", .{test_fn.name, @errorName(err)});
        std.debug.dumpStackTrace(@errorReturnTrace().?.*);
        failed += 1;
      }
    }
  }

  std.debug.print("\nTest Summary: {} passed, {} failed, {} skipped\n", .{ passed, failed, skipped });
  if (failed > 0) std.process.exit(1);
}

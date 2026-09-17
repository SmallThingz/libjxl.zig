const std = @import("std");
const jxl = @import("jxl");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const pixels = [_]u8{ 255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255 };
    const encoded = try jxl.encode(allocator, .{
        .width = 2,
        .height = 2,
        .format = .rgb,
        .pixels = &pixels,
    }, .{});
    defer allocator.free(encoded);
    var image = try jxl.decode(allocator, encoded, .{});
    defer image.deinit();
    if (!std.mem.eql(u8, &pixels, image.pixels)) return error.RoundTripMismatch;
    std.debug.print("JPEG XL: {d} bytes, {d}x{d}, exact pixels\n", .{ encoded.len, image.width, image.height });
}

//! Allocator-owned JPEG XL still images. No global initialization is required.
const std = @import("std");
/// Advanced upstream API. Raw handles obey upstream ownership rules.
pub const raw = @cImport({
    @cInclude("jxl/encode.h");
    @cInclude("jxl/decode.h");
});

pub const PixelFormat = enum(u3) {
    gray = 1,
    gray_alpha = 2,
    rgb = 3,
    rgba = 4,
    pub fn channels(self: PixelFormat) usize {
        return @intFromEnum(self);
    }
    fn cFormat(self: PixelFormat) raw.JxlPixelFormat {
        return .{ .num_channels = @intFromEnum(self), .data_type = raw.JXL_TYPE_UINT8, .endianness = raw.JXL_NATIVE_ENDIAN, .@"align" = 0 };
    }
};

/// Borrowed, tightly packed, row-major 8-bit sRGB pixels. Alpha is straight.
pub const ImageView = struct {
    width: u32,
    height: u32,
    format: PixelFormat,
    pixels: []const u8,
};

/// Owns pixels allocated by decode. Do not copy ownership; call deinit once.
pub const Image = struct {
    width: u32,
    height: u32,
    format: PixelFormat,
    pixels: []u8,
    allocator: std.mem.Allocator,
    pub fn deinit(self: *Image) void {
        self.allocator.free(self.pixels);
        self.* = undefined;
    }
    pub fn view(self: Image) ImageView {
        return .{ .width = self.width, .height = self.height, .format = self.format, .pixels = self.pixels };
    }
};
pub const EncodeOptions = struct {
    /// Zero is mathematically lossless; positive values select perceptual loss.
    distance: f32 = 0,
    effort: u8 = 7,
    container: bool = false,
};
pub const DecodeOptions = struct {
    /// Reject larger decoded pixel buffers before allocating them.
    max_bytes: usize = 256 * 1024 * 1024,
};
pub const Error = error{ OutOfMemory, InvalidDimensions, InvalidPixelBuffer, InvalidOptions, EncodeFailed, InvalidData, TruncatedData, UnsupportedImage, ImageTooLarge };

fn pixelBytes(width: u32, height: u32, format: PixelFormat) Error!usize {
    if (width == 0 or height == 0) return error.InvalidDimensions;
    const count = std.math.mul(usize, width, height) catch return error.ImageTooLarge;
    return std.math.mul(usize, count, format.channels()) catch error.ImageTooLarge;
}

// The header records each allocation length so C callbacks can use arbitrary Zig
// allocators without a global map. Context remains stack-stable until destruction.
const Memory = struct {
    allocator: std.mem.Allocator,
    failed: bool = false,
    const header_size = 64;
    fn manager(self: *Memory) raw.JxlMemoryManager {
        return .{ .@"opaque" = self, .alloc = alloc, .free = free };
    }
    fn alloc(context: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque {
        const self: *Memory = @ptrCast(@alignCast(context.?));
        const total = std.math.add(usize, size, header_size) catch {
            self.failed = true;
            return null;
        };
        const bytes = self.allocator.alignedAlloc(u8, .@"64", total) catch {
            self.failed = true;
            return null;
        };
        const len: *usize = @ptrCast(bytes.ptr);
        len.* = total;
        return bytes.ptr + header_size;
    }
    fn free(context: ?*anyopaque, address: ?*anyopaque) callconv(.c) void {
        const ptr = address orelse return;
        const self: *Memory = @ptrCast(@alignCast(context.?));
        const base: [*]align(64) u8 = @alignCast(@as([*]u8, @ptrCast(ptr)) - header_size);
        const len: *const usize = @ptrCast(base);
        self.allocator.free(base[0..len.*]);
    }
    fn encodeError(self: Memory) Error {
        return if (self.failed) error.OutOfMemory else error.EncodeFailed;
    }
    fn decodeError(self: Memory) Error {
        return if (self.failed) error.OutOfMemory else error.InvalidData;
    }
};

/// Returns caller-owned bytes; release with allocator.free. Input is borrowed only
/// for this call. The codec's custom memory-manager hooks use this allocator;
/// upstream C++ containers may also allocate through the system allocator.
pub fn encode(allocator: std.mem.Allocator, image: ImageView, options: EncodeOptions) Error![]u8 {
    if (image.pixels.len != try pixelBytes(image.width, image.height, image.format)) return error.InvalidPixelBuffer;
    if (!std.math.isFinite(options.distance) or options.distance < 0 or options.distance > 25 or options.effort < 1 or options.effort > 9) return error.InvalidOptions;
    var memory: Memory = .{ .allocator = allocator };
    const manager = memory.manager();
    const enc = raw.JxlEncoderCreate(&manager) orelse return error.OutOfMemory;
    defer raw.JxlEncoderDestroy(enc);
    if (options.container and raw.JxlEncoderUseContainer(enc, raw.JXL_TRUE) != raw.JXL_ENC_SUCCESS) return memory.encodeError();
    var info: raw.JxlBasicInfo = undefined;
    raw.JxlEncoderInitBasicInfo(&info);
    info.xsize = image.width;
    info.ysize = image.height;
    info.bits_per_sample = 8;
    info.num_color_channels = if (image.format.channels() <= 2) 1 else 3;
    info.num_extra_channels = if (image.format == .rgba or image.format == .gray_alpha) 1 else 0;
    info.alpha_bits = if (info.num_extra_channels == 1) 8 else 0;
    info.uses_original_profile = if (options.distance == 0) raw.JXL_TRUE else raw.JXL_FALSE;
    if (raw.JxlEncoderSetBasicInfo(enc, &info) != raw.JXL_ENC_SUCCESS) return memory.encodeError();
    var color: raw.JxlColorEncoding = undefined;
    raw.JxlColorEncodingSetToSRGB(&color, if (info.num_color_channels == 1) raw.JXL_TRUE else raw.JXL_FALSE);
    if (raw.JxlEncoderSetColorEncoding(enc, &color) != raw.JXL_ENC_SUCCESS) return memory.encodeError();
    const settings = raw.JxlEncoderFrameSettingsCreate(enc, null) orelse return memory.encodeError();
    if (raw.JxlEncoderSetFrameDistance(settings, options.distance) != raw.JXL_ENC_SUCCESS or
        raw.JxlEncoderSetFrameLossless(settings, if (options.distance == 0) raw.JXL_TRUE else raw.JXL_FALSE) != raw.JXL_ENC_SUCCESS or
        raw.JxlEncoderFrameSettingsSetOption(settings, raw.JXL_ENC_FRAME_SETTING_EFFORT, options.effort) != raw.JXL_ENC_SUCCESS) return memory.encodeError();
    const format = image.format.cFormat();
    if (raw.JxlEncoderAddImageFrame(settings, &format, image.pixels.ptr, image.pixels.len) != raw.JXL_ENC_SUCCESS) return memory.encodeError();
    raw.JxlEncoderCloseInput(enc);
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    while (true) {
        var buffer: [4096]u8 = undefined;
        var next: [*c]u8 = &buffer;
        var available: usize = buffer.len;
        const status = raw.JxlEncoderProcessOutput(enc, &next, &available);
        try output.appendSlice(allocator, buffer[0 .. buffer.len - available]);
        switch (status) {
            raw.JXL_ENC_SUCCESS => return output.toOwnedSlice(allocator),
            raw.JXL_ENC_NEED_MORE_OUTPUT => {},
            else => return memory.encodeError(),
        }
    }
}

/// Decode a complete still image to tightly packed 8-bit sRGB pixels. Animated
/// images and non-alpha extra channels are rejected rather than silently lost.
pub fn decode(allocator: std.mem.Allocator, input: []const u8, options: DecodeOptions) Error!Image {
    if (input.len < 2) return error.TruncatedData;
    const signature = raw.JxlSignatureCheck(input.ptr, input.len);
    if (signature == raw.JXL_SIG_INVALID) return error.InvalidData;
    if (signature == raw.JXL_SIG_NOT_ENOUGH_BYTES) return error.TruncatedData;
    var memory: Memory = .{ .allocator = allocator };
    const manager = memory.manager();
    const dec = raw.JxlDecoderCreate(&manager) orelse return error.OutOfMemory;
    defer raw.JxlDecoderDestroy(dec);
    if (raw.JxlDecoderSetUnpremultiplyAlpha(dec, raw.JXL_TRUE) != raw.JXL_DEC_SUCCESS) return memory.decodeError();
    if (raw.JxlDecoderSubscribeEvents(dec, raw.JXL_DEC_BASIC_INFO | raw.JXL_DEC_COLOR_ENCODING | raw.JXL_DEC_FULL_IMAGE) != raw.JXL_DEC_SUCCESS or
        raw.JxlDecoderSetInput(dec, input.ptr, input.len) != raw.JXL_DEC_SUCCESS) return memory.decodeError();
    // Keep input open so premature EOF is distinguishable from corrupt data.
    var result: ?Image = null;
    errdefer if (result) |*image| image.deinit();
    var complete = false;
    while (true) switch (raw.JxlDecoderProcessInput(dec)) {
        raw.JXL_DEC_BASIC_INFO => {
            var info: raw.JxlBasicInfo = undefined;
            if (raw.JxlDecoderGetBasicInfo(dec, &info) != raw.JXL_DEC_SUCCESS) return memory.decodeError();
            if (info.have_animation != 0 or (info.num_color_channels != 1 and info.num_color_channels != 3) or info.num_extra_channels != @as(u32, if (info.alpha_bits > 0) 1 else 0)) return error.UnsupportedImage;
            const format: PixelFormat = @enumFromInt(info.num_color_channels + @as(u32, if (info.alpha_bits > 0) 1 else 0));
            const size = try pixelBytes(info.xsize, info.ysize, format);
            if (size > options.max_bytes) return error.ImageTooLarge;
            result = .{ .width = info.xsize, .height = info.ysize, .format = format, .pixels = try allocator.alloc(u8, size), .allocator = allocator };
        },
        raw.JXL_DEC_COLOR_ENCODING => {
            const image = result orelse return error.InvalidData;
            var color: raw.JxlColorEncoding = undefined;
            raw.JxlColorEncodingSetToSRGB(&color, if (image.format.channels() <= 2) raw.JXL_TRUE else raw.JXL_FALSE);
            if (raw.JxlDecoderSetPreferredColorProfile(dec, &color) != raw.JXL_DEC_SUCCESS) return memory.decodeError();
        },
        raw.JXL_DEC_NEED_IMAGE_OUT_BUFFER => {
            const image = result orelse return error.InvalidData;
            const format = image.format.cFormat();
            var size: usize = 0;
            if (raw.JxlDecoderImageOutBufferSize(dec, &format, &size) != raw.JXL_DEC_SUCCESS or size != image.pixels.len) return error.InvalidData;
            if (raw.JxlDecoderSetImageOutBuffer(dec, &format, image.pixels.ptr, image.pixels.len) != raw.JXL_DEC_SUCCESS) return memory.decodeError();
        },
        raw.JXL_DEC_FULL_IMAGE => complete = true,
        raw.JXL_DEC_SUCCESS => return if (complete) result orelse error.InvalidData else error.InvalidData,
        raw.JXL_DEC_NEED_MORE_INPUT => return error.TruncatedData,
        else => return memory.decodeError(),
    };
}

test "lossless pixels and alpha survive both codestream and container" {
    const allocator = std.testing.allocator;
    for ([_]PixelFormat{ .gray, .gray_alpha, .rgb, .rgba }) |format| {
        var pixels: [8 * 7 * 4]u8 = undefined;
        for (&pixels, 0..) |*value, i| value.* = @truncate(i * 37 + i / 3);
        const view: ImageView = .{ .width = 8, .height = 7, .format = format, .pixels = pixels[0 .. 8 * 7 * format.channels()] };
        for ([_]bool{ false, true }) |container| {
            const bytes = try encode(allocator, view, .{ .container = container, .effort = 1 });
            defer allocator.free(bytes);
            var image = try decode(allocator, bytes, .{});
            defer image.deinit();
            try std.testing.expectEqual(view.width, image.width);
            try std.testing.expectEqual(view.height, image.height);
            try std.testing.expectEqual(format, image.format);
            try std.testing.expectEqualSlices(u8, view.pixels, image.pixels);
        }
    }
}

test "invalid inputs and decoded size limit" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidData, decode(allocator, "not a JPEG XL file", .{}));
    try std.testing.expectError(error.TruncatedData, decode(allocator, &.{0xff}, .{}));
    const view: ImageView = .{ .width = 2, .height = 1, .format = .rgb, .pixels = &.{ 1, 2, 3, 4, 5, 6 } };
    try std.testing.expectError(error.InvalidOptions, encode(allocator, view, .{ .distance = std.math.nan(f32) }));
    const encoded = try encode(allocator, view, .{ .effort = 1 });
    defer allocator.free(encoded);
    try std.testing.expectError(error.ImageTooLarge, decode(allocator, encoded, .{ .max_bytes = 5 }));
    try std.testing.expectError(error.TruncatedData, decode(allocator, encoded[0 .. encoded.len / 2], .{}));
}

test "lossy encode preserves image content within a bounded error" {
    const allocator = std.testing.allocator;
    var pixels: [32 * 32 * 3]u8 = undefined;
    for (0..32) |y| for (0..32) |x| {
        pixels[(y * 32 + x) * 3] = @intCast(x * 7);
        pixels[(y * 32 + x) * 3 + 1] = @intCast(y * 7);
        pixels[(y * 32 + x) * 3 + 2] = @intCast((x + y) * 3);
    };
    const encoded = try encode(allocator, .{ .width = 32, .height = 32, .format = .rgb, .pixels = &pixels }, .{ .distance = 1, .effort = 3 });
    defer allocator.free(encoded);
    var image = try decode(allocator, encoded, .{});
    defer image.deinit();
    var squared_error: u64 = 0;
    for (pixels, image.pixels) |a, b| {
        const difference = @as(i32, a) - b;
        squared_error += @intCast(difference * difference);
    }
    try std.testing.expect(squared_error / pixels.len < 100);
}

fn allocationRoundTrip(allocator: std.mem.Allocator) !void {
    const input: ImageView = .{ .width = 1, .height = 1, .format = .rgb, .pixels = &.{ 20, 60, 100 } };
    const encoded = try encode(allocator, input, .{ .effort = 1 });
    defer allocator.free(encoded);
    var image = try decode(allocator, encoded, .{});
    defer image.deinit();
    try std.testing.expectEqualSlices(u8, input.pixels, image.pixels);
}

test "allocator failures release intermediate codec and output allocations" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationRoundTrip, .{});
}

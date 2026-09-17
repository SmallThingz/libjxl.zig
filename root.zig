//! Allocator-owned JPEG XL still images. No global initialization is required.
const std = @import("std");
/// Advanced upstream API. Raw handles obey upstream ownership rules.
pub const raw = @cImport({
    @cInclude("jxl/encode.h");
    @cInclude("jxl/decode.h");
    @cInclude("jxl/cms.h");
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
pub const Error = error{ OutOfMemory, InvalidDimensions, InvalidPixelBuffer, InvalidOptions, EncodeFailed, InvalidData, TruncatedData, UnsupportedImage, UnsupportedColorProfile, ImageTooLarge };

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

/// Decode a still image payload to tightly packed 8-bit sRGB pixels. Animated
/// images and non-alpha extra channels are rejected rather than silently lost.
/// Metadata boxes after the image payload are neither returned nor validated.
pub fn decode(allocator: std.mem.Allocator, input: []const u8, options: DecodeOptions) Error!Image {
    if (input.len < 2) return error.TruncatedData;
    const signature = raw.JxlSignatureCheck(input.ptr, input.len);
    if (signature == raw.JXL_SIG_INVALID) return error.InvalidData;
    if (signature == raw.JXL_SIG_NOT_ENOUGH_BYTES) return error.TruncatedData;
    var memory: Memory = .{ .allocator = allocator };
    const manager = memory.manager();
    const dec = raw.JxlDecoderCreate(&manager) orelse return error.OutOfMemory;
    var result: ?Image = null;
    errdefer if (result) |*image| image.deinit();
    // Destroy the decoder before releasing its borrowed output buffer on error.
    defer raw.JxlDecoderDestroy(dec);
    if (raw.JxlDecoderSetCms(dec, raw.JxlGetDefaultCms().*) != raw.JXL_DEC_SUCCESS) return memory.decodeError();
    if (raw.JxlDecoderSetUnpremultiplyAlpha(dec, raw.JXL_TRUE) != raw.JXL_DEC_SUCCESS) return memory.decodeError();
    if (raw.JxlDecoderSubscribeEvents(dec, raw.JXL_DEC_BASIC_INFO | raw.JXL_DEC_COLOR_ENCODING | raw.JXL_DEC_FULL_IMAGE) != raw.JXL_DEC_SUCCESS or
        raw.JxlDecoderSetInput(dec, input.ptr, input.len) != raw.JXL_DEC_SUCCESS) return memory.decodeError();
    // Keep input open so premature EOF is distinguishable from corrupt data.
    var complete = false;
    var original_profile = false;
    while (true) switch (raw.JxlDecoderProcessInput(dec)) {
        raw.JXL_DEC_BASIC_INFO => {
            var info: raw.JxlBasicInfo = undefined;
            if (raw.JxlDecoderGetBasicInfo(dec, &info) != raw.JXL_DEC_SUCCESS) return memory.decodeError();
            original_profile = info.uses_original_profile != 0;
            if (info.have_animation != 0 or (info.num_color_channels != 1 and info.num_color_channels != 3) or info.num_extra_channels != @as(u32, if (info.alpha_bits > 0) 1 else 0)) return error.UnsupportedImage;
            const format: PixelFormat = @enumFromInt(info.num_color_channels + @as(u32, if (info.alpha_bits > 0) 1 else 0));
            const size = try pixelBytes(info.xsize, info.ysize, format);
            if (size > options.max_bytes) return error.ImageTooLarge;
            const pixels = try allocator.alloc(u8, size);
            result = .{ .width = info.xsize, .height = info.ysize, .format = format, .pixels = pixels, .allocator = allocator };
        },
        raw.JXL_DEC_COLOR_ENCODING => {
            const image = result orelse return error.InvalidData;
            // libjxl 0.11.1 does not reliably transform original-profile
            // (non-XYB) pixels, even after SetCms/SetOutputColorProfile.
            // Reject those profiles instead of mislabelling their samples.
            if (original_profile) {
                var source: raw.JxlColorEncoding = undefined;
                if (raw.JxlDecoderGetColorAsEncodedProfile(dec, raw.JXL_COLOR_PROFILE_TARGET_ORIGINAL, &source) != raw.JXL_DEC_SUCCESS or
                    source.white_point != raw.JXL_WHITE_POINT_D65 or
                    source.transfer_function != raw.JXL_TRANSFER_FUNCTION_SRGB or
                    (image.format.channels() > 2 and (source.color_space != raw.JXL_COLOR_SPACE_RGB or source.primaries != raw.JXL_PRIMARIES_SRGB)) or
                    (image.format.channels() <= 2 and source.color_space != raw.JXL_COLOR_SPACE_GRAY)) return error.UnsupportedColorProfile;
            }
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

test "validation precedes native calls and output owns its pixels" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidDimensions, encode(allocator, .{ .width = 0, .height = 1, .format = .gray, .pixels = &.{} }, .{}));
    try std.testing.expectError(error.InvalidPixelBuffer, encode(allocator, .{ .width = 2, .height = 2, .format = .rgb, .pixels = &.{1} }, .{}));
    const input: ImageView = .{ .width = 2, .height = 1, .format = .rgba, .pixels = &.{ 2, 4, 6, 0, 8, 10, 12, 255 } };
    const bytes = try encode(allocator, input, .{ .effort = 1 });
    var image = decode(allocator, bytes, .{}) catch |err| {
        allocator.free(bytes);
        return err;
    };
    allocator.free(bytes);
    defer image.deinit();
    try std.testing.expectEqualSlices(u8, input.pixels, image.pixels);
    image.pixels[0] = 99;
    try std.testing.expectEqual(@as(u8, 2), input.pixels[0]);
    try std.testing.expectEqual(@as(u8, 99), image.view().pixels[0]);
}

test "every incomplete codestream prefix is rejected" {
    const allocator = std.testing.allocator;
    var pixels: [8 * 8 * 3]u8 = undefined;
    for (&pixels, 0..) |*pixel, index| pixel.* = @truncate(index * 19);
    const bytes = try encode(allocator, .{ .width = 8, .height = 8, .format = .rgb, .pixels = &pixels }, .{ .effort = 1 });
    defer allocator.free(bytes);
    for (0..bytes.len) |length| {
        if (decode(allocator, bytes[0..length], .{})) |owned| {
            var image = owned;
            image.deinit();
            return error.AcceptedTruncatedImage;
        } else |err| switch (err) {
            error.TruncatedData, error.InvalidData => {},
            else => return err,
        }
    }
}

test "animated streams return UnsupportedImage" {
    const enc = raw.JxlEncoderCreate(null) orelse return error.OutOfMemory;
    defer raw.JxlEncoderDestroy(enc);
    var info: raw.JxlBasicInfo = undefined;
    raw.JxlEncoderInitBasicInfo(&info);
    info.xsize = 1;
    info.ysize = 1;
    info.bits_per_sample = 8;
    info.num_color_channels = 3;
    info.uses_original_profile = raw.JXL_TRUE;
    info.have_animation = raw.JXL_TRUE;
    info.animation.tps_numerator = 10;
    info.animation.tps_denominator = 1;
    try std.testing.expectEqual(@as(raw.JxlEncoderStatus, raw.JXL_ENC_SUCCESS), raw.JxlEncoderSetBasicInfo(enc, &info));
    var color: raw.JxlColorEncoding = undefined;
    raw.JxlColorEncodingSetToSRGB(&color, raw.JXL_FALSE);
    try std.testing.expectEqual(@as(raw.JxlEncoderStatus, raw.JXL_ENC_SUCCESS), raw.JxlEncoderSetColorEncoding(enc, &color));
    const settings = raw.JxlEncoderFrameSettingsCreate(enc, null) orelse return error.OutOfMemory;
    try std.testing.expectEqual(@as(raw.JxlEncoderStatus, raw.JXL_ENC_SUCCESS), raw.JxlEncoderSetFrameLossless(settings, raw.JXL_TRUE));
    var frame: raw.JxlFrameHeader = undefined;
    raw.JxlEncoderInitFrameHeader(&frame);
    frame.duration = 1;
    try std.testing.expectEqual(@as(raw.JxlEncoderStatus, raw.JXL_ENC_SUCCESS), raw.JxlEncoderSetFrameHeader(settings, &frame));
    const format = PixelFormat.rgb.cFormat();
    const first = [_]u8{ 255, 0, 0 };
    const second = [_]u8{ 0, 255, 0 };
    try std.testing.expectEqual(@as(raw.JxlEncoderStatus, raw.JXL_ENC_SUCCESS), raw.JxlEncoderAddImageFrame(settings, &format, &first, first.len));
    try std.testing.expectEqual(@as(raw.JxlEncoderStatus, raw.JXL_ENC_SUCCESS), raw.JxlEncoderAddImageFrame(settings, &format, &second, second.len));
    raw.JxlEncoderCloseInput(enc);
    var bytes: [4096]u8 = undefined;
    var next: [*c]u8 = &bytes;
    var available: usize = bytes.len;
    try std.testing.expectEqual(@as(raw.JxlEncoderStatus, raw.JXL_ENC_SUCCESS), raw.JxlEncoderProcessOutput(enc, &next, &available));
    try std.testing.expectError(error.UnsupportedImage, decode(std.testing.allocator, bytes[0 .. bytes.len - available], .{}));
}

fn fixtureGray(width: u32, height: u32, pixels: []const u8, orientation: raw.JxlOrientation, linear: bool, sixteen_bit: bool) ![]u8 {
    const enc = raw.JxlEncoderCreate(null) orelse return error.OutOfMemory;
    defer raw.JxlEncoderDestroy(enc);
    var info: raw.JxlBasicInfo = undefined;
    raw.JxlEncoderInitBasicInfo(&info);
    info.xsize = width;
    info.ysize = height;
    info.bits_per_sample = if (sixteen_bit) 16 else 8;
    info.num_color_channels = 1;
    info.uses_original_profile = raw.JXL_TRUE;
    info.orientation = orientation;
    try std.testing.expectEqual(@as(raw.JxlEncoderStatus, raw.JXL_ENC_SUCCESS), raw.JxlEncoderSetBasicInfo(enc, &info));
    var color: raw.JxlColorEncoding = undefined;
    if (linear) raw.JxlColorEncodingSetToLinearSRGB(&color, raw.JXL_TRUE) else raw.JxlColorEncodingSetToSRGB(&color, raw.JXL_TRUE);
    try std.testing.expectEqual(@as(raw.JxlEncoderStatus, raw.JXL_ENC_SUCCESS), raw.JxlEncoderSetColorEncoding(enc, &color));
    const settings = raw.JxlEncoderFrameSettingsCreate(enc, null) orelse return error.OutOfMemory;
    try std.testing.expectEqual(@as(raw.JxlEncoderStatus, raw.JXL_ENC_SUCCESS), raw.JxlEncoderSetFrameLossless(settings, raw.JXL_TRUE));
    try std.testing.expectEqual(@as(raw.JxlEncoderStatus, raw.JXL_ENC_SUCCESS), raw.JxlEncoderFrameSettingsSetOption(settings, raw.JXL_ENC_FRAME_SETTING_EFFORT, 1));
    var format = PixelFormat.gray.cFormat();
    if (sixteen_bit) format.data_type = raw.JXL_TYPE_UINT16;
    try std.testing.expectEqual(@as(raw.JxlEncoderStatus, raw.JXL_ENC_SUCCESS), raw.JxlEncoderAddImageFrame(settings, &format, pixels.ptr, pixels.len));
    raw.JxlEncoderCloseInput(enc);
    var bytes: [4096]u8 = undefined;
    var next: [*c]u8 = &bytes;
    var available: usize = bytes.len;
    try std.testing.expectEqual(@as(raw.JxlEncoderStatus, raw.JXL_ENC_SUCCESS), raw.JxlEncoderProcessOutput(enc, &next, &available));
    return std.testing.allocator.dupe(u8, bytes[0 .. bytes.len - available]);
}

test "non-square orientations produce oriented dimensions and pixels" {
    const allocator = std.testing.allocator;
    const cases = [_]struct { orientation: raw.JxlOrientation, width: u32, height: u32, expected: [6]u8 }{
        .{ .orientation = 3, .width = 2, .height = 3, .expected = .{ 6, 5, 4, 3, 2, 1 } },
        .{ .orientation = 6, .width = 3, .height = 2, .expected = .{ 5, 3, 1, 6, 4, 2 } },
        .{ .orientation = 8, .width = 3, .height = 2, .expected = .{ 2, 4, 6, 1, 3, 5 } },
    };
    for (cases) |case| {
        const bytes = try fixtureGray(2, 3, &.{ 1, 2, 3, 4, 5, 6 }, case.orientation, false, false);
        defer allocator.free(bytes);
        var image = try decode(allocator, bytes, .{});
        defer image.deinit();
        try std.testing.expectEqual(case.width, image.width);
        try std.testing.expectEqual(case.height, image.height);
        try std.testing.expectEqualSlices(u8, &case.expected, image.pixels);
    }
}

test "unsupported original profile is rejected and sRGB 16-bit data is quantized" {
    const allocator = std.testing.allocator;
    const linear = try fixtureGray(1, 1, &.{128}, 1, true, false);
    defer allocator.free(linear);
    try std.testing.expectError(error.UnsupportedColorProfile, decode(allocator, linear, .{}));
    const pixels = [_]u16{ 0, 32768, 65535 };
    const high_depth = try fixtureGray(3, 1, std.mem.sliceAsBytes(&pixels), 1, false, true);
    defer allocator.free(high_depth);
    var quantized = try decode(allocator, high_depth, .{});
    defer quantized.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0, 128, 255 }, quantized.pixels);
}

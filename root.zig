const std = @import("std");
const config = @import("config");
const builtin = @import("builtin");

pub const c = @cImport({
  @cInclude("jxl/cms.h");
  @cInclude("jxl/cms_interface.h");
  @cInclude("jxl/codestream_header.h");
  @cInclude("jxl/color_encoding.h");
  @cInclude("jxl/compressed_icc.h");
  @cInclude("jxl/encode.h");
  @cInclude("jxl/decode.h");
  @cInclude("jxl/gain_map.h");
  @cInclude("jxl/memory_manager.h");
  @cInclude("jxl/parallel_runner.h");
  @cInclude("jxl/resizable_parallel_runner.h");
  @cInclude("jxl/stats.h");
  @cInclude("jxl/thread_parallel_runner.h");
  @cInclude("jxl/types.h");
  @cInclude("jxl/version.h");
});

pub const InitOptions = struct {
  /// This must be true for you to be able to call Codestream.BasicInfo.default
  codestream_basic_info: bool = true,
  /// This must be true for you to be able to call Codestream.ExtraChannelInfo.default
  codestream_extra_channel_info: bool = true,
  /// This must be true for you to be able to call Frame.BlendInfo.default
  frame_blend_info: bool = true,
  /// This must be true for you to be able to call Frame.Header.default
  frame_header: bool = true,
};

pub fn init(options: InitOptions) !void {
  if (options.codestream_basic_info) Codestream.BasicInfo._default_value = ._default();
  if (options.codestream_extra_channel_info) {
    inline for (@typeInfo(Codestream.ExtraChannelInfo._DefaultValues).@"struct".fields) |f| {
      @field(Codestream.ExtraChannelInfo._default_values, f.name) = ._default(@field(Codestream.ExtraChannelType, f.name));
    }
  }
  if (options.frame_blend_info) Frame.BlendInfo._default_value = ._default();
  if (options.frame_header) Frame.Header._default_value = ._default();
  Encoder._version_value = Encoder._version();
  Decoder._version_value = Decoder._version();
}

pub const Cms = struct {
  /// Represents an input or output colorspace to a color transform, as a serialized ICC profile.
  pub const ColorProfile = extern struct {
    /// The serialized ICC profile. This is guaranteed to be present and valid.
    icc: ICCData,

    /// Structured representation of the colorspace, if applicable. If all fields
    /// are different from their "unknown" value, then this is equivalent to the
    /// ICC representation of the colorspace. If some are "unknown", those that are
    /// not are still valid and can still be used on their own if they are useful.
    color_encoding: ColorEncoding,

    /// Number of components per pixel. This can be deduced from the other
    /// representations of the colorspace but is provided for convenience and
    /// validation.
    num_channels: usize,

    pub const ICCData = extern struct {
      data: [*]const u8,
      size: usize,

      test {
        const T = @FieldType(c.JxlColorProfile, "icc");
        std.debug.assert(@sizeOf(@This()) == @sizeOf(T));
        inline for (@typeInfo(T).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
          std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
          std.debug.assert(@bitOffsetOf(@This(), f.name) == @bitOffsetOf(T, cf.name));
        }
      }
    };

    test {
      const T = c.JxlColorProfile;
      std.debug.assert(@sizeOf(@This()) == @sizeOf(T));
      inline for (@typeInfo(T).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(@This(), f.name) == @bitOffsetOf(T, cf.name));
      }
    }
  };

  /// Interface for performing colorspace transforms. The @c init function can be
  /// called several times to instantiate several transforms, including before
  /// other transforms have been destroyed.
  pub const Interface = extern struct {
    /// CMS-specific data that will be passed to @ref set_fields_from_icc.
    _set_fields_data: ?*anyopaque,
    /// Populates a @ref JxlColorEncoding from an ICC profile.
    _set_fields_from_icc_fn: ?SetFieldsFromIccFn,

    /// CMS-specific data that will be passed to @ref init.
    _init_data: ?*anyopaque,
    /// Prepares a colorspace transform as described in the documentation of @ref
    /// jpegxl_cms_init_func.
    _init_fn: InitFn,
    /// Returns a buffer that can be used as input to @c run.
    _get_src_buf_fn: GetBufferFn,
    /// Returns a buffer that can be used as output from @c run.
    _get_dst_buf_fn: GetBufferFn,
    /// Executes the transform on a batch of pixels, per @ref jpegxl_cms_run_func.
    _run_fn: RunFn,
    /// Cleans up the transform.
    _destroy_fn: DestroyFn,

    /// Creates a CMS Interface from a Zig struct.
    ///
    /// @param Instance: The type returned by `init` representing a specific transform session.
    /// @param cms_ctx: Must implement `fn init(self, ...)` to create an Instance.
    /// @param icc_ctx: May implement `fn setFieldsFromIcc(self, ...)` (Optional).
    /// 
    /// The context struct `Sub` must implement:
    /// - `fn init(self: *Sub, num_threads: usize, pixels_per_thread: usize, input: *const ColorProfile, output: *const ColorProfile, intensity: f32) !?*Instance`
    /// 
    /// The `Instance` type returned by `init` must implement:
    /// - `fn run(instance: *Instance, thread_id: usize, input: [*]const f32, output: [*]f32, num_pixels: usize) bool`
    /// - `fn getSrcBuf(instance: *Instance, thread_id: usize) ?[*]f32`
    /// - `fn getDstBuf(instance: *Instance, thread_id: usize) ?[*]f32`
    /// - optional `fn destroy(instance: *Instance) void`
    /// 
    /// Additionally, `Sub` may implement:
    /// - optional `fn setFieldsFromIcc(self: *Sub, icc: []const u8, encoding: *ColorEncoding, is_cmyk: *bool) bool`
    /// Creates a CMS Interface from two Zig contexts.
    /// 
    ///
    /// Creates a CMS Interface from Zig contexts.
    /// 
    /// The `cms_ctx` must implement:
    /// - `fn init(self: *Sub, num_threads: usize, pixels_per_thread: usize, in: *const ColorProfile, out: *const ColorProfile, intensity: f32) !*Instance`
    ///   Prepares a transformation session. Returns a pointer to a worker instance.
    /// 
    /// The `Instance` type returned by `init` must implement:
    /// - `fn run(self: *Instance, thread_id: usize, input: [*]const f32, output: [*]f32, num_pixels: usize) bool`
    ///   Executes the color transform for a batch of pixels.
    /// - `fn getSrcBuf(self: *Instance, thread_id: usize) ?[*]f32`
    ///   Returns a thread-local buffer for input data.
    /// - `fn getDstBuf(self: *Instance, thread_id: usize) ?[*]f32`
    ///   Returns a thread-local buffer for output data.
    /// - `fn destroy(self: *Instance) void`
    ///   Cleans up the instance context when the transform is no longer needed.
    /// 
    /// The `icc_ctx` (IccSub) may implement:
    /// - `fn setFieldsFromIcc(self: *IccSub, icc: []const u8, encoding: *ColorEncoding, is_cmyk: *bool) bool`
    ///   Parses raw ICC profile data to populate structured color encoding fields.
    pub fn fromContext(cms_ctx: anytype, icc_ctx: anytype) @This() {
      const CmsT = @TypeOf(cms_ctx);
      const IccT = @TypeOf(icc_ctx);
      const CmsSub = if (@typeInfo(CmsT) == .pointer) @typeInfo(CmsT).pointer.child else CmsT;
      const IccSub = if (@typeInfo(IccT) == .pointer) @typeInfo(IccT).pointer.child else IccT;

      const InstanceT = @typeInfo(@FieldType(CmsT, "init")).@"fn".return_type.?;
      const InstanceP = if (@typeInfo(InstanceT) == .error_union) @typeInfo(InstanceT).error_union.payload else InstanceT;

      const VTable = struct {
        fn getCms(p: ?*anyopaque) *CmsSub { return @alignCast(@ptrCast(p.?)); }
        fn getIcc(p: ?*anyopaque) *IccSub { return @alignCast(@ptrCast(p.?)); }
        fn getInstance(p: ?*anyopaque) InstanceP { return @alignCast(@ptrCast(p.?)); }

        fn setFields(p: ?*anyopaque, icc_ptr: ?[*]const u8, icc_size: usize, c_enc: ?*ColorEncoding, cmyk: ?*c.JXL_BOOL) callconv(.c) c.JXL_BOOL {
          var is_cmyk: bool = false;
          const ok = getIcc(p).setFieldsFromIcc(icc_ptr.?[0..icc_size], c_enc.?, &is_cmyk);
          if (cmyk) |out| out.* = if (is_cmyk) c.JXL_TRUE else c.JXL_FALSE;
          return if (ok) c.JXL_TRUE else c.JXL_FALSE;
        }

        fn init(p: ?*anyopaque, num_threads: usize, pixels_per_thread: usize, in: ?*const ColorProfile, out: ?*const ColorProfile, intensity: f32) callconv(.c) ?*anyopaque {
          return @ptrCast(getCms(p).init(num_threads, pixels_per_thread, in.?, out.?, intensity) catch null);
        }

        fn getSrcBuf(p: ?*anyopaque, thread: usize) callconv(.c) ?[*]f32 {
          return getInstance(p).getSrcBuf(thread);
        }

        fn getDstBuf(p: ?*anyopaque, thread: usize) callconv(.c) ?[*]f32 {
          return getInstance(p).getDstBuf(thread);
        }

        fn run(p: ?*anyopaque, thread: usize, in: ?[*]const f32, out: ?[*]f32, num_pix: usize) callconv(.c) c.JXL_BOOL {
          return if (getInstance(p).run(thread, in.?, out.?, num_pix)) c.JXL_TRUE else c.JXL_FALSE;
        }

        fn destroy(p: ?*anyopaque) callconv(.c) void {
          getInstance(p).destroy();
        }
      };

      return .{
        ._set_fields_data = if (@bitSizeOf(IccSub) == 0) null else @ptrCast(icc_ctx),
        ._set_fields_from_icc_fn = if (@hasDecl(IccSub, "setFieldsFromIcc")) &VTable.setFields else null,
        ._init_data = if (@bitSizeOf(CmsSub) == 0) null else @ptrCast(cms_ctx),
        ._init_fn = &VTable.init,
        ._get_src_buf_fn = &VTable.getSrcBuf,
        ._get_dst_buf_fn = &VTable.getDstBuf,
        ._run_fn = &VTable.run,
        ._destroy_fn = &VTable.destroy,
      };
    }

    test {
      const T = c.JxlCmsInterface;
      std.debug.assert(@sizeOf(@This()) == @sizeOf(T));
      inline for (@typeInfo(T).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(@This(), f.name) == @bitOffsetOf(T, cf.name));
      }
    }

    /// CMS interface function to parse an ICC profile and populate @p c and @p cmyk with the data.
    pub const SetFieldsFromIccFn = *const fn (
      user_data: ?*anyopaque,
      icc_data: ?[*]const u8,
      icc_size: usize,
      color_encoding: ?*ColorEncoding,
      cmyk: ?*c.JXL_BOOL
    ) callconv(.c) c.JXL_BOOL;

    /// CMS interface function to allocate and return the data needed for parallel transforms.
    pub const InitFn = *const fn (
      init_data: ?*anyopaque,
      num_threads: usize,
      pixels_per_thread: usize,
      input_profile: ?*const ColorProfile,
      output_profile: ?*const ColorProfile,
      intensity_target: f32,
    ) callconv(.c) ?*anyopaque;

    /// CMS interface function to return a buffer for thread-local storage.
    pub const GetBufferFn = *const fn (user_data: ?*anyopaque, thread: usize) callconv(.c) ?[*]f32;

    /// CMS interface function to execute one transform batch.
    pub const RunFn = *const fn (
      user_data: ?*anyopaque,
      thread: usize,
      input_buffer: ?[*]const f32,
      output_buffer: ?[*]f32,
      num_pixels: usize,
    ) callconv(.c) c.JXL_BOOL;

    /// CMS interface function to perform clean-up.
    pub const DestroyFn = *const fn (user_data: ?*anyopaque) callconv(.c) void;

    /// Returns the default CMS interface provided by libjxl.
    pub fn getDefault() *const @This() {
      return @ptrCast(c.JxlGetDefaultCms().?);
    }

    /// Forwarding wrapper for _set_fields_from_icc_fn.
    pub fn setFieldsFromIcc(self: *const @This(), icc: []const u8, encoding: *ColorEncoding, is_cmyk: *bool) bool {
      if (self._set_fields_from_icc_fn) |f| {
        var c_cmyk: c.JXL_BOOL = c.JXL_FALSE;
        const res = f(self._set_fields_data, icc.ptr, icc.len, encoding, &c_cmyk);
        is_cmyk.* = c_cmyk == c.JXL_TRUE;
        return res == c.JXL_TRUE;
      }
      return false;
    }

    pub const Instance = struct {
      _interface: *const Interface,
      _user_data: *opaque{},

      pub fn getSrcBuf(self: @This(), thread_id: usize) error{Failed}![*]f32 {
        return self._interface._get_src_buf_fn(@ptrCast(self._user_data), thread_id) orelse error.Failed;
      }

      pub fn getDstBuf(self: @This(), thread_id: usize) error{Failed}![*]f32 {
        return self._interface._get_dst_buf_fn(@ptrCast(self._user_data), thread_id) orelse error.Failed;
      }

      pub fn run(self: @This(), thread_id: usize, input: [*]const f32, output: [*]f32, num_pixels: usize) error{Failed}!void {
        if (self._interface._run_fn(@ptrCast(self._user_data), thread_id, input, output, num_pixels) != c.JXL_TRUE) return error.Failed;
      }

      pub fn deinit(self: @This()) void {
        self._interface._destroy_fn(@ptrCast(self._user_data));
      }
    };

    /// Prepares a colorspace transform.
    pub fn init(
      self: *const @This(),
      num_threads: usize,
      pixels_per_thread: usize,
      input: *const ColorProfile,
      output: *const ColorProfile,
      intensity: f32,
    ) error{Failed}!Instance {
      return .{
        ._interface = self,
        ._user_data = @ptrCast(self._init_fn(self._init_data, num_threads, pixels_per_thread, input, output, intensity) orelse return error.Failed),
      };
    }
  };
};

pub const Codestream = struct {
  /// Image orientation metadata.
  /// Values 1..8 match the EXIF definitions.
  /// The name indicates the operation to perform to transform from the encoded
  /// image to the display image.
  pub const Orientation = enum(c.JxlOrientation) {
    identity = @bitCast(c.JXL_ORIENT_IDENTITY),
    flip_horizontal = @bitCast(c.JXL_ORIENT_FLIP_HORIZONTAL),
    rotate_180 = @bitCast(c.JXL_ORIENT_ROTATE_180),
    flip_vertical = @bitCast(c.JXL_ORIENT_FLIP_VERTICAL),
    transpose = @bitCast(c.JXL_ORIENT_TRANSPOSE),
    rotate_90_cw = @bitCast(c.JXL_ORIENT_ROTATE_90_CW),
    anti_transpose = @bitCast(c.JXL_ORIENT_ANTI_TRANSPOSE),
    rotate_90_ccw = @bitCast(c.JXL_ORIENT_ROTATE_90_CCW),
  };

  /// Given type of an extra channel.
  pub const ExtraChannelType = enum(c.JxlExtraChannelType) {
    alpha = @bitCast(c.JXL_CHANNEL_ALPHA),
    depth = @bitCast(c.JXL_CHANNEL_DEPTH),
    spot_color = @bitCast(c.JXL_CHANNEL_SPOT_COLOR),
    selection_mask = @bitCast(c.JXL_CHANNEL_SELECTION_MASK),
    black = @bitCast(c.JXL_CHANNEL_BLACK),
    cfa = @bitCast(c.JXL_CHANNEL_CFA),
    thermal = @bitCast(c.JXL_CHANNEL_THERMAL),
    unknown = @bitCast(c.JXL_CHANNEL_UNKNOWN),
    optional = @bitCast(c.JXL_CHANNEL_OPTIONAL),
    _, // future expansion
  };

  /// The codestream animation header, optionally present in the beginning of
  /// the codestream, and if it is it applies to all animation frames, unlike @ref
  /// JxlFrameHeader which applies to an individual frame.
  pub const AnimationHeader = extern struct {
    /// Numerator of ticks per second of a single animation frame time unit
    tps_numerator: u32,
    /// Denominator of ticks per second of a single animation frame time unit
    tps_denominator: u32,
    /// Amount of animation loops, or 0 to repeat infinitely
    num_loops: u32,
    /// Whether animation time codes are present at animation frames in the
    /// codestream
    have_timecodes: Types.Bool,

    test {
      const T = c.JxlAnimationHeader;
      std.debug.assert(@sizeOf(@This()) == @sizeOf(T));
      inline for (@typeInfo(T).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(@This(), f.name) == @bitOffsetOf(T, cf.name));
      }
    }
  };

  /// Basic image information. This information is available from the file
  /// signature and first part of the codestream header.
  pub const BasicInfo = extern struct {
    /// Whether the codestream is embedded in the container format. If true,
    /// metadata information and extensions may be available in addition to the
    /// codestream.
    have_container: Types.Bool,
    /// Width of the image in pixels, before applying orientation.
    xsize: u32,
    /// Height of the image in pixels, before applying orientation.
    ysize: u32,
    /// Original image color channel bit depth.
    bits_per_sample: u32,
    /// Original image color channel floating point exponent bits, or 0 if they
    /// are unsigned integer.
    exponent_bits_per_sample: u32,
    /// Upper bound on the intensity level present in the image in nits.
    intensity_target: f32,
    /// Lower bound on the intensity level present in the image.
    min_nits: f32,
    /// See the description of @see linear_below.
    relative_to_max_display: Types.Bool,
    /// Interpretation depends on relative_to_max_display.
    linear_below: f32,
    /// Whether the data in the codestream is encoded in the original color profile.
    uses_original_profile: Types.Bool,
    /// Indicates a preview image exists near the beginning of the codestream.
    have_preview: Types.Bool,
    /// Indicates animation frames exist in the codestream.
    have_animation: Types.Bool,
    /// Image orientation, value 1-8 matching EXIF.
    orientation: Orientation,
    /// Number of color channels encoded in the image (1 or 3).
    num_color_channels: u32,
    /// Number of additional image channels.
    num_extra_channels: u32,
    /// Bit depth of the encoded alpha channel, or 0 if none.
    alpha_bits: u32,
    /// Alpha channel floating point exponent bits, or 0 if unsigned.
    alpha_exponent_bits: u32,
    /// Whether the alpha channel is premultiplied.
    alpha_premultiplied: Types.Bool,
    /// Dimensions of encoded preview image.
    preview: PreviewHeader,
    /// Animation header with global animation properties.
    animation: AnimationHeader,
    /// Intrinsic width of the image.
    intrinsic_xsize: u32,
    /// Intrinsic height of the image.
    intrinsic_ysize: u32,
    /// Padding for forwards-compatibility.
    padding: [100]u8,

    test {
      const T = c.JxlBasicInfo;
      std.debug.assert(@sizeOf(@This()) == @sizeOf(T));
      inline for (@typeInfo(T).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(@This(), f.name) == @bitOffsetOf(T, cf.name));
      }
    }

    pub fn default() @This() { return _default_value; }
    var _default_value: @This() = undefined;
    pub fn _default() @This() {
      var self: @This() = undefined;
      c.JxlEncoderInitBasicInfo(@ptrCast(&self));
      return self;
    }

    /// The codestream preview header
    pub const PreviewHeader = extern struct {
      /// Preview width in pixels
      xsize: u32,
      /// Preview height in pixels
      ysize: u32,

      test {
        const T = c.JxlPreviewHeader;
        std.debug.assert(@sizeOf(@This()) == @sizeOf(T));
        inline for (@typeInfo(T).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
          std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
          std.debug.assert(@bitOffsetOf(@This(), f.name) == @bitOffsetOf(T, cf.name));
        }
      }
    };
  };

  /// Information for a single extra channel.
  pub const ExtraChannelInfo = extern struct {
    /// Given type of an extra channel.
    type: ExtraChannelType,
    /// Total bits per sample for this channel.
    bits_per_sample: u32,
    /// Floating point exponent bits per channel, or 0 if unsigned.
    exponent_bits_per_sample: u32,
    /// The exponent the channel is downsampled by on each axis.
    dim_shift: u32,
    /// Length of the extra channel name in bytes, excludes null terminator.
    name_length: u32,
    /// Whether alpha channel uses premultiplied alpha.
    alpha_premultiplied: Types.Bool,
    /// Spot color of the current spot channel in linear RGBA.
    spot_color: [4]f32,
    /// Only applicable if type is JXL_CHANNEL_CFA.
    cfa_channel: u32,

    test {
      const T = c.JxlExtraChannelInfo;
      std.debug.assert(@sizeOf(@This()) == @sizeOf(T));
      inline for (@typeInfo(T).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(@This(), f.name) == @bitOffsetOf(T, cf.name));
      }
    }

    pub fn default(comptime channel_type: Codestream.ExtraChannelType) @This() {
      return @field(_default_values, @tagName(channel_type));
    }

    const _DefaultValues = @Type(.{
      .@"struct" = .{
        .layout = .auto,
        .backing_integer = null,
        .fields = blk: {
          var filtered_fields: []const std.builtin.Type.EnumField = &.{};
          for (@typeInfo(Codestream.ExtraChannelType).@"enum".fields) |f| {
            filtered_fields = filtered_fields ++ &[_]std.builtin.Type.EnumField{f};
          }
          var fields: [filtered_fields.len]std.builtin.Type.StructField = undefined;
          for (filtered_fields, 0..) |f, i| {
            fields[i] = .{
              .name = f.name,
              .type = @This(),
              .default_value_ptr = null,
              .is_comptime = false,
              .alignment = @alignOf(@This()),
            };
          }
          const const_fields: [filtered_fields.len]std.builtin.Type.StructField = fields;
          break :blk &const_fields;
        },
        .decls = &[_]std.builtin.Type.Declaration{},
        .is_tuple = false,
      },
    });
    var _default_values: _DefaultValues = undefined;
    pub fn _default(channel_type: Codestream.ExtraChannelType) @This() {
      var self: @This() = undefined;
      c.JxlEncoderInitExtraChannelInfo(@intFromEnum(channel_type), @ptrCast(&self));
      return self;
    }
  };

  /// Extensions in the codestream header. Getting this is not yet implemented
  pub const HeaderExtensions = extern struct {
    /// Extension bits.
    extensions: u64,

    test {
      const T = c.JxlHeaderExtensions;
      std.debug.assert(@sizeOf(@This()) == @sizeOf(T));
      inline for (@typeInfo(T).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(@This(), f.name) == @bitOffsetOf(T, cf.name));
      }
    }
  };
};

pub const Frame = struct {
  /// Frame blend modes.
  pub const BlendMode = enum(c.JxlBlendMode) {
    replace = @bitCast(c.JXL_BLEND_REPLACE),
    add = @bitCast(c.JXL_BLEND_ADD),
    blend = @bitCast(c.JXL_BLEND_BLEND),
    muladd = @bitCast(c.JXL_BLEND_MULADD),
    mul = @bitCast(c.JXL_BLEND_MUL),
  };

  /// The information about blending the color channels or a single extra channel.
  pub const BlendInfo = extern struct {
    /// Blend mode.
    blendmode: BlendMode,
    /// Reference frame ID to use as the 'bottom' layer (0-3).
    source: u32,
    /// Which extra channel to use as the 'alpha' channel.
    alpha: u32,
    /// Clamp values to [0,1] for the purpose of blending.
    clamp: Types.Bool,

    test {
      const T = c.JxlBlendInfo;
      std.debug.assert(@sizeOf(@This()) == @sizeOf(T));
      inline for (@typeInfo(T).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(@This(), f.name) == @bitOffsetOf(T, cf.name));
      }
    }

    pub fn default() @This() { return _default_value; }
    var _default_value: @This() = undefined;
    pub fn _default() @This() {
      var self: @This() = undefined;
      c.JxlEncoderInitBlendInfo(@ptrCast(&self));
      return self;
    }
  };

  /// The information about layers.
  pub const LayerInfo = extern struct {
    /// Whether cropping is applied for this frame.
    have_crop: Types.Bool,
    /// Horizontal offset of the frame (can be negative).
    crop_x0: i32,
    /// Vertical offset of the frame (can be negative).
    crop_y0: i32,
    /// Width of the frame (number of columns).
    xsize: u32,
    /// Height of the frame (number of rows).
    ysize: u32,
    /// The blending info for the color channels.
    blend_info: BlendInfo,
    /// After blending, save the frame as reference frame with this ID (0-3).
    save_as_reference: u32,

    test {
      const T = c.JxlLayerInfo;
      std.debug.assert(@sizeOf(@This()) == @sizeOf(T));
      inline for (@typeInfo(T).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(@This(), f.name) == @bitOffsetOf(T, cf.name));
      }
    }
  };

  /// The header of one displayed frame or non-coalesced layer.
  pub const Header = extern struct {
    /// How long to wait after rendering in ticks.
    duration: u32,
    /// SMPTE timecode of the current frame in form 0xHHMMSSFF, or 0.
    timecode: u32,
    /// Length of the frame name in bytes, excludes null terminator.
    name_length: u32,
    /// Indicates this is the last animation frame.
    is_last: Types.Bool,
    /// Information about the layer in case of no coalescing.
    layer_info: LayerInfo,

    test {
      const T = c.JxlFrameHeader;
      std.debug.assert(@sizeOf(@This()) == @sizeOf(T));
      inline for (@typeInfo(T).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(@This(), f.name) == @bitOffsetOf(T, cf.name));
      }
    }

    pub fn default() @This() { return _default_value; }
    var _default_value: @This() = undefined;
    pub fn _default() @This() {
      var self: @This() = undefined;
      c.JxlEncoderInitFrameHeader(@ptrCast(&self));
      return self;
    }
  };
};

/// Opaque structure that holds the JPEG XL decoder.
///
/// Allocated and initialized with @ref JxlDecoderCreate().
/// Cleaned up and deallocated with @ref JxlDecoderDestroy().
pub const Decoder = opaque {
  /// Decoder library version.
  ///
  /// @return the decoder library version as an integer:
  /// MAJOR_VERSION * 1000000 + MINOR_VERSION * 1000 + PATCH_VERSION. For example,
  /// version 1.2.3 would return 1002003.
  pub fn version() u32 { return _version_value; }
  var _version_value: u32 = undefined;
  pub fn _version() u32 { return c.JxlDecoderVersion(); }

  /// The result of @ref JxlSignatureCheck.
  pub const Signature = enum(c.JxlSignature) {
    /// Not enough bytes were passed to determine if a valid signature was found.
    not_enough_bytes = @bitCast(c.JXL_SIG_NOT_ENOUGH_BYTES),

    /// No valid JPEG XL header was found.
    invalid = @bitCast(c.JXL_SIG_INVALID),

    /// A valid JPEG XL codestream signature was found, that is a JPEG XL image
    /// without container.
    codestream = @bitCast(c.JXL_SIG_CODESTREAM),

    /// A valid container signature was found, that is a JPEG XL image embedded
    /// in a box format container.
    container = @bitCast(c.JXL_SIG_CONTAINER),
  };

  /// JPEG XL signature identification.
  ///
  /// Checks if the passed buffer contains a valid JPEG XL signature. The passed @p
  /// buf of size @p size doesn't need to be a full image, only the beginning of the file.
  ///
  /// @return a flag indicating if a JPEG XL signature was found and what type.
  pub fn signatureCheck(buf: []const u8) Signature {
    return @enumFromInt(c.JxlSignatureCheck(buf.ptr, buf.len));
  }

  /// Creates an instance of @ref JxlDecoder and initializes it.
  ///
  /// @p memory_manager will be used for all the library dynamic allocations made
  /// from this instance. The parameter may be NULL, in which case the default
  /// allocator will be used. See jxl/memory_manager.h for details.
  ///
  /// @param memory_manager custom allocator function. It may be NULL. The memory
  ///        manager will be copied internally.
  /// @return pointer to initialized @ref JxlDecoder otherwise
  pub fn create(memory_manager: ?*const MemoryManager) !*@This() {
    return @ptrCast(c.JxlDecoderCreate(@ptrCast(memory_manager)) orelse return error.OutOfMemory);
  }

  /// Re-initializes a @ref JxlDecoder instance, so it can be re-used for decoding
  /// another image. All state and settings are reset as if the object was
  /// newly created with @ref JxlDecoderCreate, but the memory manager is kept.
  ///
  /// @param dec instance to be re-initialized.
  pub fn reset(dec: *@This()) void {
    c.JxlDecoderReset(@ptrCast(dec));
  }

  /// Deinitializes and frees @ref JxlDecoder instance.
  ///
  /// @param dec instance to be cleaned up and deallocated.
  pub fn deinit(dec: *@This()) void {
    c.JxlDecoderDestroy(@ptrCast(dec));
  }

  /// Return value for @ref JxlDecoderProcessInput. The values from ::JXL_DEC_BASIC_INFO onwards are optional informative
  /// events that can be subscribed to, they are never returned if they have not been registered with @ref JxlDecoderSubscribeEvents.
  pub const Status = enum(c.JxlDecoderStatus) {
    /// Function call finished successfully, or decoding is finished and there is nothing more to be done.
    success = @bitCast(c.JXL_DEC_SUCCESS),

    /// An error occurred, for example invalid input file or out of memory.
    @"error" = @bitCast(c.JXL_DEC_ERROR),

    /// The decoder needs more input bytes to continue. Before the next @ref Decoder.processInput call, more input data must be set, by calling
    /// @ref Decoder.releaseInput (if input was set previously) and then calling @ref Decoder.setInput.
    need_more_input = @bitCast(c.JXL_DEC_NEED_MORE_INPUT),

    /// The decoder is able to decode a preview image and requests setting a preview output buffer using @ref JxlDecoderSetPreviewOutBuffer.
    need_preview_out_buffer = @bitCast(c.JXL_DEC_NEED_PREVIEW_OUT_BUFFER),

    /// The decoder requests an output buffer to store the full resolution image, which can be set with @ref Decoder.setImageOutBuffer or with @ref Decoder.SetImageOutCallback.
    need_image_out_buffer = @bitCast(c.JXL_DEC_NEED_IMAGE_OUT_BUFFER),

    /// The JPEG reconstruction buffer is too small for reconstructed JPEG
    /// codestream to fit. @ref JxlDecoderSetJPEGBuffer must be called again to
    /// make room for remaining bytes.
    jpeg_need_more_output = @bitCast(c.JXL_DEC_JPEG_NEED_MORE_OUTPUT),

    /// The box contents output buffer is too small. @ref JxlDecoderSetBoxBuffer must be called again to make room for remaining bytes.
    box_need_more_output = @bitCast(c.JXL_DEC_BOX_NEED_MORE_OUTPUT),

    /// Informative event: Basic information such as image dimensions and extra channels. This event occurs max once per image.
    basic_info = @bitCast(c.JXL_DEC_BASIC_INFO),

    /// Informative event: Color encoding or ICC profile from the codestream header.
    color_encoding = @bitCast(c.JXL_DEC_COLOR_ENCODING),

    /// Informative event: Preview image, a small frame, decoded.
    preview_image = @bitCast(c.JXL_DEC_PREVIEW_IMAGE),

    /// Informative event: Beginning of a frame. @ref Decoder.getFrameHeader can be used at this point.
    frame = @bitCast(c.JXL_DEC_FRAME),

    /// Informative event: full frame (or layer, in case coalescing is disabled) is decoded.
    full_image = @bitCast(c.JXL_DEC_FULL_IMAGE),

    /// Informative event: JPEG reconstruction data decoded.
    jpeg_reconstruction = @bitCast(c.JXL_DEC_JPEG_RECONSTRUCTION),

    /// Informative event: The header of a box of the container format (BMFF) is decoded.
    box = @bitCast(c.JXL_DEC_BOX),

    /// Informative event: a progressive step in decoding the frame is reached.
    frame_progression = @bitCast(c.JXL_DEC_FRAME_PROGRESSION),

    /// The box being decoded is now complete. This is only emitted if a buffer was set for the box.
    box_complete = @bitCast(c.JXL_DEC_BOX_COMPLETE),

    _, // future expansion

    pub const Set = error {
      DecoderError,
      DecoderNeedMoreInput,
      DecoderNeedPreviewOutBuffer,
      DecoderNeedImageOutBuffer,
      DecoderJpegNeedMoreOutput,
      DecoderBoxNeedMoreOutput,
      DecoderBasicInfo,
      DecoderColorEncoding,
      DecoderPreviewImage,
      DecoderFrame,
      DecoderFullImage,
      DecoderJpegReconstruction,
      DecoderBox,
      DecoderFrameProgression,
      DecoderBoxComplete,
      UnknownDecoderError,
    };

    pub fn check(self: c_uint) !void {
      return switch (@as(@This(), @enumFromInt(self))) {
        .success => {},
        .@"error" => Set.DecoderError,
        .need_more_input => Set.DecoderNeedMoreInput,
        .need_preview_out_buffer => Set.DecoderNeedPreviewOutBuffer,
        .need_image_out_buffer => Set.DecoderNeedImageOutBuffer,
        .jpeg_need_more_output => Set.DecoderJpegNeedMoreOutput,
        .box_need_more_output => Set.DecoderBoxNeedMoreOutput,
        .basic_info => Set.DecoderBasicInfo,
        .color_encoding => Set.DecoderColorEncoding,
        .preview_image => Set.DecoderPreviewImage,
        .frame => Set.DecoderFrame,
        .full_image => Set.DecoderFullImage,
        .jpeg_reconstruction => Set.DecoderJpegReconstruction,
        .box => Set.DecoderBox,
        .frame_progression => Set.DecoderFrameProgression,
        .box_complete => Set.DecoderBoxComplete,
        else => error.UnknownDecoderError
      };
    }
  };

  /// Types of progressive detail.
  /// Setting a progressive detail with value N implies all progressive details
  /// with smaller or equal value.
  pub const ProgressiveDetail = enum(c.JxlProgressiveDetail) {
    /// after completed kRegularFrames
    frames = @bitCast(c.kFrames),
    /// after completed DC (1:8)
    dc = @bitCast(c.kDC),
    /// after completed AC passes that are the last pass for their resolution
    /// target.
    last_passes = @bitCast(c.kLastPasses),
    /// after completed AC passes that are not the last pass for their resolution
    /// target.
    passes = @bitCast(c.kPasses),
    /// during DC frame when lower resolution are completed (1:32, 1:16)
    dc_progressive = @bitCast(c.kDCProgressive),
    /// after completed groups
    dc_groups = @bitCast(c.kDCGroups),
    /// after completed groups
    groups = @bitCast(c.kGroups),
  };

  /// Rewinds decoder to the beginning. The same input must be given again from
  /// the beginning of the file and the decoder will emit events from the beginning
  /// again. When rewinding (as opposed to @ref JxlDecoderReset), the decoder can
  /// keep state about the image, which it can use to skip to a requested frame
  /// more efficiently with @ref JxlDecoderSkipFrames. Settings such as parallel
  /// runner or subscribed events are kept.
  pub fn rewind(dec: *@This()) void {
    c.JxlDecoderRewind(@ptrCast(dec));
  }

  /// Makes the decoder skip the next `amount` frames. It still needs to process
  /// the input, but will not output the frame events. It can be more efficient
  /// when skipping frames, and even more so when using this after @ref DecoderRewind.
  pub fn skipFrames(dec: *@This(), amount: usize) void {
    c.JxlDecoderSkipFrames(@ptrCast(dec), amount);
  }

  /// Skips processing the current frame. Can be called after frame processing
  /// already started, signaled by a ::JXL_DEC_NEED_IMAGE_OUT_BUFFER event,
  /// but before the corresponding ::JXL_DEC_FULL_IMAGE event.
  pub fn skipCurrentFrame(dec: *@This()) !void {
    return Status.check(c.JxlDecoderSkipCurrentFrame(@ptrCast(dec)));
  }

  /// Set the parallel runner for multithreading. May only be set before starting decoding.
  pub const setParallelRunner = if (config.threading) _setParallelRunner else null;

  fn _setParallelRunner(dec: *@This(), parallel_runner: ParallelRunner.RunnerFn, parallel_runner_opaque: ?*ParallelRunner) !void {
    return Status.check(c.JxlDecoderSetParallelRunner(@ptrCast(dec), parallel_runner, @ptrCast(parallel_runner_opaque)));
  }

  /// Returns a hint indicating how many more bytes the decoder is expected to
  /// need to make @ref JxlDecoderGetBasicInfo available after the next @ref
  /// JxlDecoderProcessInput call.
  pub fn sizeHintBasicInfo(dec: *const @This()) usize {
    return c.JxlDecoderSizeHintBasicInfo(@ptrCast(dec));
  }

  /// Select for which informative events, i.e. ::JXL_DEC_BASIC_INFO, etc., the
  /// decoder should return with a status.
  pub fn subscribeEvents(dec: *@This(), events_wanted: i32) !void {
    return Status.check(c.JxlDecoderSubscribeEvents(@ptrCast(dec), events_wanted));
  }

  /// Enables or disables preserving of as-in-bitstream pixeldata
  /// orientation.
  pub fn setKeepOrientation(dec: *@This(), skip_reorientation: bool) !void {
    return Status.check(c.JxlDecoderSetKeepOrientation(@ptrCast(dec), @intFromBool(skip_reorientation)));
  }

  /// Enables or disables preserving of associated alpha channels. If
  /// unpremul_alpha is set to ::JXL_FALSE then for associated alpha channel,
  /// the pixel data is returned with premultiplied colors.
  pub fn setUnpremultiplyAlpha(dec: *@This(), unpremul_alpha: bool) !void {
    return Status.check(c.JxlDecoderSetUnpremultiplyAlpha(@ptrCast(dec), @intFromBool(unpremul_alpha)));
  }

  /// Enables or disables rendering spot colors. By default, spot colors
  /// are rendered, which is OK for viewing the decoded image.
  pub fn setRenderSpotcolors(dec: *@This(), render_spotcolors: bool) !void {
    return Status.check(c.JxlDecoderSetRenderSpotcolors(@ptrCast(dec), @intFromBool(render_spotcolors)));
  }

  /// Enables or disables coalescing of zero-duration frames. By default, frames
  /// are returned with coalescing enabled, i.e. all frames have the image
  /// dimensions, and are blended if needed.
  pub fn setCoalescing(dec: *@This(), coalescing: bool) !void {
    return Status.check(c.JxlDecoderSetCoalescing(@ptrCast(dec), @intFromBool(coalescing)));
  }

  /// Decodes JPEG XL file using the available bytes. Requires input has been
  /// set with @ref JxlDecoderSetInput.
  pub fn processInput(dec: *@This()) !void {
    return Status.check(c.JxlDecoderProcessInput(@ptrCast(dec)));
  }

  /// Sets input data for @ref JxlDecoderProcessInput. The data is owned by the
  /// caller and may be used by the decoder until @ref JxlDecoderReleaseInput is
  /// called or the decoder is destroyed or reset so must be kept alive until then.
  pub fn setInput(dec: *@This(), data: []const u8) !void {
    return Status.check(c.JxlDecoderSetInput(@ptrCast(dec), data.ptr, data.len));
  }

  /// Releases input which was provided with @ref JxlDecoderSetInput.
  pub fn releaseInput(dec: *@This()) usize {
    return c.JxlDecoderReleaseInput(@ptrCast(dec));
  }

  /// Marks the input as finished, indicates that no more @ref JxlDecoderSetInput
  /// will be called.
  pub fn closeInput(dec: *@This()) void {
    c.JxlDecoderCloseInput(@ptrCast(dec));
  }

  /// Outputs the basic image information, such as image dimensions, bit depth and
  /// all other JxlBasicInfo fields, if available.
  pub fn getBasicInfo(dec: *const @This(), info: ?*Codestream.BasicInfo) !void {
    return Status.check(c.JxlDecoderGetBasicInfo(@ptrCast(dec), @ptrCast(info)));
  }

  /// Outputs information for extra channel at the given index. The index must be
  /// smaller than num_extra_channels in the associated @ref JxlBasicInfo.
  pub fn getExtraChannelInfo(dec: *const @This(), index: usize, info: ?*Codestream.ExtraChannelInfo) !void {
    return Status.check(c.JxlDecoderGetExtraChannelInfo(@ptrCast(dec), index, @ptrCast(info)));
  }

  /// Outputs name for extra channel at the given index in UTF-8.
  pub fn getExtraChannelName(dec: *const @This(), index: usize, name: []u8) !void {
    return Status.check(c.JxlDecoderGetExtraChannelName(@ptrCast(dec), index, name.ptr, name.len));
  }

  /// Defines which color profile to get: the profile from the codestream
  /// metadata header, which represents the color profile of the original image,
  /// or the color profile from the pixel data produced by the decoder. Both are
  /// the same if the JxlBasicInfo has uses_original_profile set.
  pub const ColorProfileTarget = enum(c.JxlColorProfileTarget) {
    /// Get the color profile of the original image from the metadata.
    original = @bitCast(c.JXL_COLOR_PROFILE_TARGET_ORIGINAL),

    /// Get the color profile of the pixel data the decoder outputs.
    data = @bitCast(c.JXL_COLOR_PROFILE_TARGET_DATA),
  };

  /// Outputs the color profile as JPEG XL encoded structured data, if available.
  /// This is an alternative to an ICC Profile, which can represent a more limited
  /// amount of color spaces, but represents them exactly through enum values.
  pub fn getColorAsEncodedProfile(dec: *const @This(), target: ColorProfileTarget, color_encoding: ?*ColorEncoding) !void {
    return Status.check(c.JxlDecoderGetColorAsEncodedProfile(@ptrCast(dec), @intFromEnum(target), @ptrCast(color_encoding)));
  }

  pub fn _getICCProfileSize(dec: *const @This(), target: ColorProfileTarget, size: ?*usize) !void {
    return Status.check(c.JxlDecoderGetICCProfileSize(@ptrCast(dec), @intFromEnum(target), size));
  }

  /// Outputs the size in bytes of the ICC profile returned by @ref JxlDecoderGetColorAsICCProfile, if available,
  /// or indicates there is none available.
  pub fn getICCProfileSize(dec: *const @This(), target: ColorProfileTarget) !usize {
    var size: usize = undefined;
    try _getICCProfileSize(dec, target, &size);
    return size;
  }

  pub fn getICCProfileStatus(dec: *const @This(), target: ColorProfileTarget) !void {
    return _getICCProfileSize(dec, target, null);
  }

  /// Outputs ICC profile if available. The profile is only available if @ref getICCProfileSize returns success.
  pub fn getColorAsICCProfile(dec: *const @This(), target: ColorProfileTarget, icc_profile: []u8) !void {
    return Status.check(c.JxlDecoderGetColorAsICCProfile(@ptrCast(dec), @intFromEnum(target), icc_profile.ptr, icc_profile.len));
  }

  /// Sets the desired output color profile of the decoded image by calling
  /// @ref JxlDecoderSetOutputColorProfile, passing on @c color_encoding and
  /// setting @c icc_data to NULL.
  pub fn setPreferredColorProfile(dec: *@This(), color_encoding: *const ColorEncoding) !void {
    return Status.check(c.JxlDecoderSetPreferredColorProfile(@ptrCast(dec), @ptrCast(color_encoding)));
  }

  /// Requests that the decoder perform tone mapping to the peak display luminance
  /// passed as @c desired_intensity_target, if appropriate.
  pub fn setDesiredIntensityTarget(dec: *@This(), desired_intensity_target: f32) !void {
    return Status.check(c.JxlDecoderSetDesiredIntensityTarget(@ptrCast(dec), desired_intensity_target));
  }

  pub const OutputColorProfile = union(enum) {
    color_encoding: *const ColorEncoding,
    icc_data: []const u8,
    none: void,
  };
  /// Sets the desired output color profile of the decoded image either from a color encoding or an ICC profile.
  /// Valid calls of this function have either @c color_encoding or @c icc_data set to NULL.
  pub fn setOutputColorProfile(dec: *@This(), profile: OutputColorProfile) !void {
    return Status.check(c.JxlDecoderSetOutputColorProfile(
        @ptrCast(dec),
        if (profile == .color_encoding) @ptrCast(profile.color_encoding) else null,
        if (profile == .icc_data) profile.icc_data.ptr else null,
        if (profile == .icc_data) profile.icc_data.len else 0,
    ));
  }

  /// Sets the color management system (CMS) that will be used for color conversion (if applicable) during decoding.
  pub fn setCms(dec: *@This(), cms: Cms.Interface) !void {
    return Status.check(c.JxlDecoderSetCms(@ptrCast(dec), @bitCast(cms)));
  }

  /// Returns the minimum size in bytes of the preview image output pixel buffer for the given format.
  pub fn previewOutBufferSize(dec: *const @This(), format: *const Types.PixelFormat) !usize {
    var size: usize = undefined;
    try Status.check(c.JxlDecoderPreviewOutBufferSize(@ptrCast(dec), @ptrCast(format), &size));
    return size;
  }

  /// Sets the buffer to write the low-resolution preview image to.
  pub fn setPreviewOutBuffer(dec: *@This(), format: *const Types.PixelFormat, buffer: []u8) !void {
    return Status.check(c.JxlDecoderSetPreviewOutBuffer(@ptrCast(dec), @ptrCast(format), buffer.ptr, buffer.len));
  }

  /// Outputs the information from the frame, such as duration when have_animation.
  /// give null to check if the information is available.
  pub fn getFrameHeader(dec: *const @This(), header: ?*Frame.Header) !void {
    return Status.check(c.JxlDecoderGetFrameHeader(@ptrCast(dec), @ptrCast(header)));
  }

  /// Outputs name for the current frame.
  pub fn getFrameName(dec: *const @This(), name: []u8) !void {
    return Status.check(c.JxlDecoderGetFrameName(@ptrCast(dec), name.ptr, name.len));
  }

  /// Outputs the blend information for the current frame for a specific extra channel.
  pub fn getExtraChannelBlendInfo(dec: *const @This(), index: usize, blend_info: *Frame.BlendInfo) !void {
    return Status.check(c.JxlDecoderGetExtraChannelBlendInfo(@ptrCast(dec), index, @ptrCast(blend_info)));
  }

  /// Returns the minimum size in bytes of the image output pixel buffer for the given format.
  pub fn imageOutBufferSize(dec: *const @This(), format: *const Types.PixelFormat, size: *usize) !void {
    return Status.check(c.JxlDecoderImageOutBufferSize(@ptrCast(dec), @ptrCast(format), size));
  }

  /// Sets the buffer to write the full resolution image to.
  pub fn setImageOutBuffer(dec: *@This(), format: *const Types.PixelFormat, buffer: []u8) !void {
    return Status.check(c.JxlDecoderSetImageOutBuffer(@ptrCast(dec), @ptrCast(format), buffer.ptr, buffer.len));
  }

  /// Function type for @ref JxlDecoderSetImageOutCallback.
  ///
  /// The callback may be called simultaneously by different threads when using a
  /// threaded parallel runner, on different pixels.
  ///
  /// @param opaque optional user data, as given to @ref
  ///     JxlDecoderSetImageOutCallback.
  /// @param x horizontal position of leftmost pixel of the pixel data.
  /// @param y vertical position of the pixel data.
  /// @param num_pixels amount of pixels included in the pixel data, horizontally.
  ///     This is not the same as xsize of the full image, it may be smaller.
  /// @param pixels pixel data as a horizontal stripe, in the format passed to @ref
  ///     JxlDecoderSetImageOutCallback. The memory is not owned by the user, and
  ///     is only valid during the time the callback is running.
  pub const ImageOutCallback = *const fn (@"opaque": ?*anyopaque, x: usize, y: usize, num_pixels: usize, pixels: ?*const anyopaque) callconv(.c) void;

  /// Initialization callback for @ref JxlDecoderSetMultithreadedImageOutCallback.
  ///
  /// @param init_opaque optional user data, as given to @ref
  ///     JxlDecoderSetMultithreadedImageOutCallback.
  /// @param num_threads maximum number of threads that will call the @c run
  ///     callback concurrently.
  /// @param num_pixels_per_thread maximum number of pixels that will be passed in
  ///     one call to @c run.
  /// @return a pointer to data that will be passed to the @c run callback, or
  ///     @c NULL if initialization failed.
  pub const ImageOutInitCallback = *const fn (init_opaque: ?*anyopaque, num_threads: usize, num_pixels_per_thread: usize) callconv(.c) ?*anyopaque;

  /// Worker callback for @ref JxlDecoderSetMultithreadedImageOutCallback.
  ///
  /// @param run_opaque user data returned by the @c init callback.
  /// @param thread_id number in `[0, num_threads)` identifying the thread of the
  ///     current invocation of the callback.
  /// @param x horizontal position of the first (leftmost) pixel of the pixel data.
  /// @param y vertical position of the pixel data.
  /// @param num_pixels number of pixels in the pixel data. May be less than the
  ///     full @c xsize of the image, and will be at most equal to the @c
  ///     num_pixels_per_thread that was passed to @c init.
  /// @param pixels pixel data as a horizontal stripe, in the format passed to @ref
  ///     JxlDecoderSetMultithreadedImageOutCallback. The data pointed to
  ///     remains owned by the caller and is only guaranteed to outlive the current
  ///     callback invocation.
  pub const ImageOutRunCallback = *const fn (
    run_opaque: ?*anyopaque,
    thread_id: usize,
    x: usize,
    y: usize,
    num_pixels: usize,
    pixels: ?*const anyopaque,
  ) callconv(.c) void;

  /// Destruction callback for @ref JxlDecoderSetMultithreadedImageOutCallback,
  /// called after all invocations of the @c run callback to perform any
  /// appropriate clean-up of the @c run_opaque data returned by @c init.
  ///
  /// @param run_opaque user data returned by the @c init callback.
  pub const ImageOutDestroyCallback = *const fn (run_opaque: ?*anyopaque) callconv(.c) void;

  pub const ImageOutListener = struct {
    ctx: ?*anyopaque,
    callback_fn: @typeInfo(c.JxlImageOutCallback).optional.child,

    /// Creates an `ImageOutListener` from a pointer to an object.
    /// 
    /// The provided `context` must be a pointer to a type that implements a method with the following signature:
    /// `fn onImageOut(self: *Self, x: usize, y: usize, num_pixels: usize, pixels: ?*const anyopaque) void`
    pub fn fromContext(context: anytype) ImageOutListener {
      const T = @TypeOf(context);
      const PtrInfo = @typeInfo(T);
      if (PtrInfo != .pointer) @compileError("Context must be a pointer");
      const Child = PtrInfo.pointer.child;

      return .{
        .ctx = @ptrCast(context),
        .callback_fn = struct {
          fn wrapper(
            ctx: ?*anyopaque,
            x: usize,
            y: usize,
            num_pixels: usize,
            pixels: ?*const anyopaque,
          ) callconv(.c) void {
            // Cast back to the original Zig type
            const self: *Child = @ptrCast(@alignCast(ctx.?));
            // Call the expected 'onImageOut' method on that type
            self.onImageOut(x, y, num_pixels, pixels);
          }
        }.wrapper,
      };
    }
  };

  /// Sets pixel output callback. This is an alternative to @ref Decoder.setImageOutBuffer.
  pub fn setImageOutCallback(dec: *@This(), format: *const Types.PixelFormat, listener: ImageOutListener) !void {
    return Status.check(c.JxlDecoderSetImageOutCallback(@ptrCast(dec), @ptrCast(format), listener.callback_fn, listener.ctx));
  }

  /// Similar to @ref JxlDecoderSetImageOutCallback except that the callback is allowed an initialization phase.
  pub fn setMultithreadedImageOutCallback(
    dec: *@This(),
    format: *const Types.PixelFormat,
    init_callback: ImageOutInitCallback,
    run_callback: ImageOutRunCallback,
    destroy_callback: ImageOutDestroyCallback,
    init_opaque: ?*anyopaque,
  ) !void {
    return Status.check(c.JxlDecoderSetMultithreadedImageOutCallback(
      @ptrCast(dec),
      @ptrCast(format),
      init_callback,
      run_callback,
      destroy_callback,
      init_opaque,
    ));
  }

  /// Returns the minimum size in bytes of an extra channel pixel buffer for the given format.
  pub fn extraChannelBufferSize(
    dec: *const @This(),
    format: *const Types.PixelFormat,
    size: *usize,
    index: u32,
  ) !void {
    return Status.check(c.JxlDecoderExtraChannelBufferSize(@ptrCast(dec), @ptrCast(format), size, index));
  }

  /// Sets the buffer to write an extra channel to.
  pub fn setExtraChannelBuffer(
    dec: *@This(),
    format: *const Types.PixelFormat,
    buffer: []u8,
    index: u32,
  ) !void {
    return Status.check(c.JxlDecoderSetExtraChannelBuffer(@ptrCast(dec), @ptrCast(format), buffer.ptr, buffer.len, index));
  }

  /// Sets output buffer for reconstructed JPEG codestream.
  pub fn setJPEGBuffer(dec: *@This(), data: []u8) !void {
    return Status.check(c.JxlDecoderSetJPEGBuffer(@ptrCast(dec), data.ptr, data.len));
  }

  /// Releases buffer which was provided with @ref JxlDecoderSetJPEGBuffer.
  pub fn releaseJPEGBuffer(dec: *@This()) usize {
    return c.JxlDecoderReleaseJPEGBuffer(@ptrCast(dec));
  }

  /// Sets output buffer for box output codestream.
  pub fn setBoxBuffer(dec: *@This(), data: []u8) !void {
    return Status.check(c.JxlDecoderSetBoxBuffer(@ptrCast(dec), data.ptr, data.len));
  }

  /// Releases buffer which was provided with @ref JxlDecoderSetBoxBuffer.
  pub fn releaseBoxBuffer(dec: *@This()) usize {
    return c.JxlDecoderReleaseBoxBuffer(@ptrCast(dec));
  }

  /// Configures whether to get boxes in raw mode or in decompressed mode.
  pub fn setDecompressBoxes(dec: *@This(), decompress: bool) !void {
    return Status.check(c.JxlDecoderSetDecompressBoxes(@ptrCast(dec), @intFromBool(decompress)));
  }

  /// Outputs the type of the current box, after a ::JXL_DEC_BOX event occurred.
  /// @param decompressed: JXL_FALSE to get the raw box type ("brob"), JXL_TRUE to get underlying type.
  pub fn getBoxType(dec: *@This(), decompressed: bool) !Types.BoxType {
    var out_type: Types.BoxType = undefined;
    try Status.check(c.JxlDecoderGetBoxType(@ptrCast(dec), @as(*[4]u8, @ptrCast(&out_type)), @intFromBool(decompressed)));
    return out_type;
  }

  /// Returns the size of a box as it appears in the container file, after the @ref
  /// JXL_DEC_BOX event. This includes all the box headers.
  pub fn getBoxSizeRaw(dec: *const @This()) !u64 {
    var size: u64 = undefined;
    try Status.check(c.JxlDecoderGetBoxSizeRaw(@ptrCast(dec), &size));
    return size;
  }

  /// Returns the size of the contents of a box, after the @ref
  /// JXL_DEC_BOX event. This does not include any of the headers of the box.
  pub fn getBoxSizeContents(dec: *const @This()) !u64 {
    var size: u64 = undefined;
    try Status.check(c.JxlDecoderGetBoxSizeContents(@ptrCast(dec), &size));
    return size;
  }

  /// Configures at which progressive steps in frame decoding these @ref JXL_DEC_FRAME_PROGRESSION event occurs.
  pub fn setProgressiveDetail(dec: *@This(), detail: ProgressiveDetail) !void {
    return Status.check(c.JxlDecoderSetProgressiveDetail(@ptrCast(dec), @intFromEnum(detail)));
  }

  /// Returns the intended downsampling ratio for the progressive frame produced by @ref JxlDecoderFlushImage.
  pub fn getIntendedDownsamplingRatio(dec: *@This()) usize {
    return c.JxlDecoderGetIntendedDownsamplingRatio(@ptrCast(dec));
  }

  /// Outputs progressive step towards the decoded image so far when only partial input was received.
  pub fn flushImage(dec: *@This()) !void {
    return Status.check(c.JxlDecoderFlushImage(@ptrCast(dec)));
  }

  /// Sets the bit depth of the output buffer or callback.
  pub fn setImageOutBitDepth(dec: *@This(), bit_depth: *const Types.BitDepth) !void {
    return Status.check(c.JxlDecoderSetImageOutBitDepth(@ptrCast(dec), @ptrCast(bit_depth)));
  }
};

/// Opaque structure that holds the JPEG XL encoder.
///
/// Allocated and initialized with @ref JxlEncoderCreate().
/// Cleaned up and deallocated with @ref JxlEncoderDestroy().
pub const Encoder = opaque {
  /// Encoder library version.
  ///
  /// @return the encoder library version as an integer:
  /// MAJOR_VERSION * 1000000 + MINOR_VERSION * 1000 + PATCH_VERSION. For example,
  /// version 1.2.3 would return 1002003.
  pub fn version() u32 { return _version_value; }
  var _version_value: u32 = undefined;
  pub fn _version() u32 { return c.JxlEncoderVersion(); }

  /// Return value for multiple encoder functions.
  pub const Status = enum(c.JxlEncoderStatus) {
    /// Function call finished successfully, or encoding is finished and there is
    /// nothing more to be done.
    success = @bitCast(c.JXL_ENC_SUCCESS),

    /// An error occurred, for example out of memory.
    @"error" = @bitCast(c.JXL_ENC_ERROR),

    /// The encoder needs more output buffer to continue encoding.
    need_more_output = @bitCast(c.JXL_ENC_NEED_MORE_OUTPUT),

    _, // future expansion

    pub const Set = error {
      EncoderError,
      EncoderNeedMoreOutput,
      UnknownEncoderError,
    };

    pub fn check(self: c_uint) !void {
      return switch (@as(@This(), @enumFromInt(self))) {
        .success => {},
        .@"error" => Set.EncoderError,
        .need_more_output => Set.EncoderNeedMoreOutput,
        else => error.UnknownEncoderError
      };
    }
  };

  /// Error conditions:
  /// API usage errors have the 0x80 bit set to 1
  /// Other errors have the 0x80 bit set to 0
  pub const Error = enum(c.JxlEncoderError) {
    /// No error
    ok = @bitCast(c.JXL_ENC_ERR_OK),
    /// Generic encoder error due to unspecified cause
    generic = @bitCast(c.JXL_ENC_ERR_GENERIC),
    /// Out of memory
    oom = @bitCast(c.JXL_ENC_ERR_OOM),
    /// JPEG bitstream reconstruction data could not be represented
    jbrd = @bitCast(c.JXL_ENC_ERR_JBRD),
    /// Input is invalid
    bad_input = @bitCast(c.JXL_ENC_ERR_BAD_INPUT),
    /// The encoder doesn't (yet) support this.
    not_supported = @bitCast(c.JXL_ENC_ERR_NOT_SUPPORTED),
    /// The encoder API is used in an incorrect way.
    api_usage = @bitCast(c.JXL_ENC_ERR_API_USAGE),
    _, // future expansion
  };

  /// Id of encoder options for a frame.
  pub const FrameSettingId = enum(c.JxlEncoderFrameSettingId) {
    /// Sets encoder effort/speed level without affecting decoding speed. 
    effort = @bitCast(c.JXL_ENC_FRAME_SETTING_EFFORT),
    /// Sets the decoding speed tier for the provided options. 
    decoding_speed = @bitCast(c.JXL_ENC_FRAME_SETTING_DECODING_SPEED),
    /// Sets resampling option. 
    resampling = @bitCast(c.JXL_ENC_FRAME_SETTING_RESAMPLING),
    /// Similar to resampling, but for extra channels.
    extra_channel_resampling = @bitCast(c.JXL_ENC_FRAME_SETTING_EXTRA_CHANNEL_RESAMPLING),
    /// Indicates the frame added is already downsampled.
    already_downsampled = @bitCast(c.JXL_ENC_FRAME_SETTING_ALREADY_DOWNSAMPLED),
    /// Adds noise to the image emulating photographic film noise.
    photon_noise = @bitCast(c.JXL_ENC_FRAME_SETTING_PHOTON_NOISE),
    /// Enables adaptive noise generation.
    noise = @bitCast(c.JXL_ENC_FRAME_SETTING_NOISE),
    /// Enables or disables dots generation.
    dots = @bitCast(c.JXL_ENC_FRAME_SETTING_DOTS),
    /// Enables or disables patches generation.
    patches = @bitCast(c.JXL_ENC_FRAME_SETTING_PATCHES),
    /// Edge preserving filter level, -1 to 3.
    epf = @bitCast(c.JXL_ENC_FRAME_SETTING_EPF),
    /// Enables or disables the gaborish filter.
    gaborish = @bitCast(c.JXL_ENC_FRAME_SETTING_GABORISH),
    /// Enables modular encoding.
    modular = @bitCast(c.JXL_ENC_FRAME_SETTING_MODULAR),
    /// Enables or disables preserving color of invisible pixels.
    keep_invisible = @bitCast(c.JXL_ENC_FRAME_SETTING_KEEP_INVISIBLE),
    /// Determines the order in which 256x256 regions are stored.
    group_order = @bitCast(c.JXL_ENC_FRAME_SETTING_GROUP_ORDER),
    /// Determines the horizontal position of center for center-first group order.
    group_order_center_x = @bitCast(c.JXL_ENC_FRAME_SETTING_GROUP_ORDER_CENTER_X),
    /// Determines the center for the center-first group order.
    group_order_center_y = @bitCast(c.JXL_ENC_FRAME_SETTING_GROUP_ORDER_CENTER_Y),
    /// Enables or disables progressive encoding for modular mode.
    responsive = @bitCast(c.JXL_ENC_FRAME_SETTING_RESPONSIVE),
    /// Set the progressive mode for the AC coefficients of VarDCT (spectral).
    progressive_ac = @bitCast(c.JXL_ENC_FRAME_SETTING_PROGRESSIVE_AC),
    /// Set the progressive mode for AC (quantization).
    qprogressive_ac = @bitCast(c.JXL_ENC_FRAME_SETTING_QPROGRESSIVE_AC),
    /// Set the progressive mode using lower-resolution DC images for VarDCT.
    progressive_dc = @bitCast(c.JXL_ENC_FRAME_SETTING_PROGRESSIVE_DC),
    /// Use Global channel palette if colors < % of range.
    channel_colors_global_percent = @bitCast(c.JXL_ENC_FRAME_SETTING_CHANNEL_COLORS_GLOBAL_PERCENT),
    /// Use Local channel palette if colors < % of range.
    channel_colors_group_percent = @bitCast(c.JXL_ENC_FRAME_SETTING_CHANNEL_COLORS_GROUP_PERCENT),
    /// Use color palette if amount of colors <= this amount.
    palette_colors = @bitCast(c.JXL_ENC_FRAME_SETTING_PALETTE_COLORS),
    /// Enables or disables delta palette.
    lossy_palette = @bitCast(c.JXL_ENC_FRAME_SETTING_LOSSY_PALETTE),
    /// Color transform for internal encoding.
    color_transform = @bitCast(c.JXL_ENC_FRAME_SETTING_COLOR_TRANSFORM),
    /// Reversible color transform for modular encoding.
    modular_color_space = @bitCast(c.JXL_ENC_FRAME_SETTING_MODULAR_COLOR_SPACE),
    /// Group size for modular encoding.
    modular_group_size = @bitCast(c.JXL_ENC_FRAME_SETTING_MODULAR_GROUP_SIZE),
    /// Predictor for modular encoding.
    modular_predictor = @bitCast(c.JXL_ENC_FRAME_SETTING_MODULAR_PREDICTOR),
    /// Fraction of pixels used to learn MA trees as a percentage.
    modular_ma_tree_learning_percent = @bitCast(c.JXL_ENC_FRAME_SETTING_MODULAR_MA_TREE_LEARNING_PERCENT),
    /// Number of extra (previous-channel) MA tree properties to use.
    modular_nb_prev_channels = @bitCast(c.JXL_ENC_FRAME_SETTING_MODULAR_NB_PREV_CHANNELS),
    /// Enable or disable CFL for lossless JPEG recompression.
    jpeg_recon_cfl = @bitCast(c.JXL_ENC_FRAME_SETTING_JPEG_RECON_CFL),
    /// Prepare the frame for indexing in the frame index box.
    frame_index_box = @bitCast(c.JXL_ENC_FRAME_INDEX_BOX),
    /// Sets brotli encode effort for use in JPEG recompression.
    brotli_effort = @bitCast(c.JXL_ENC_FRAME_SETTING_BROTLI_EFFORT),
    /// Enables or disables brotli compression of metadata boxes from JPEG.
    jpeg_compress_boxes = @bitCast(c.JXL_ENC_FRAME_SETTING_JPEG_COMPRESS_BOXES),
    /// Control what kind of buffering is used.
    buffering = @bitCast(c.JXL_ENC_FRAME_SETTING_BUFFERING),
    /// Keep or discard Exif metadata boxes derived from a JPEG frame.
    jpeg_keep_exif = @bitCast(c.JXL_ENC_FRAME_SETTING_JPEG_KEEP_EXIF),
    /// Keep or discard XMP metadata boxes derived from a JPEG frame.
    jpeg_keep_xmp = @bitCast(c.JXL_ENC_FRAME_SETTING_JPEG_KEEP_XMP),
    /// Keep or discard JUMBF metadata boxes derived from a JPEG frame.
    jpeg_keep_jumbf = @bitCast(c.JXL_ENC_FRAME_SETTING_JPEG_KEEP_JUMBF),
    /// Enable/Disable quality decisions based on full image heuristics.
    use_full_image_heuristics = @bitCast(c.JXL_ENC_FRAME_SETTING_USE_FULL_IMAGE_HEURISTICS),
    /// Disable perceptual optimizations.
    disable_perceptual_heuristics = @bitCast(c.JXL_ENC_FRAME_SETTING_DISABLE_PERCEPTUAL_HEURISTICS),
  };

  /// Creates an instance of @ref JxlEncoder and initializes it.
  pub fn create(memory_manager: ?*const MemoryManager) !*@This() {
    return @ptrCast(c.JxlEncoderCreate(@ptrCast(memory_manager)) orelse return error.OutOfMemory);
  }

  /// Deinitializes and frees @ref JxlEncoder instance.
  pub fn deinit(self: *@This()) void {
    c.JxlEncoderDestroy(@ptrCast(self));
  }

  /// Re-initializes a @ref JxlEncoder instance, so it can be re-used for encoding
  /// another image.
  pub fn reset(self: *@This()) void {
    c.JxlEncoderReset(@ptrCast(self));
  }

  /// Sets the color management system (CMS) that will be used for color conversion (if applicable) during encoding.
  pub fn setCms(self: *@This(), cms: Cms.Interface) void {
    c.JxlEncoderSetCms(@ptrCast(self), @bitCast(cms));
  }

  /// Set the parallel runner for multithreading. May only be set before starting encoding.
  pub const setParallelRunner = if (config.threading) _setParallelRunner else null;

  fn _setParallelRunner(self: *@This(), parallel_runner: ParallelRunner.RunnerFn, parallel_runner_opaque: ?*ParallelRunner) !void {
    return Status.check(c.JxlEncoderSetParallelRunner(@ptrCast(self), parallel_runner, @ptrCast(parallel_runner_opaque)));
  }

  /// Get the (last) error code in case ::JXL_ENC_ERROR was returned.
  pub fn getError(self: *@This()) Error {
    return @enumFromInt(c.JxlEncoderGetError(@ptrCast(self)));
  }

  /// Encodes a JPEG XL file using the available bytes.
  /// @param next_out: pointer to next bytes to write to.
  /// @param avail_out: amount of bytes available starting from *next_out.
  pub fn processOutput(self: *@This(), next_out: *[*]u8, avail_out: *usize) !void {
    return Status.check(c.JxlEncoderProcessOutput(@ptrCast(self), @ptrCast(next_out), avail_out));
  }

  /// Function type for @ref JxlEncoderSetDebugImageCallback.
  pub const DebugImageCallback = *const fn (
    @"opaque": ?*anyopaque,
    label: [*c]const u8,
    xsize: usize,
    ysize: usize,
    color: [*c]const c.JxlColorEncoding,
    pixels: [*c]const u16,
  ) callconv(.c) void;

  /// Settings and metadata for a single image frame. This includes encoder options
  /// for a frame such as compression quality and speed.
  ///
  /// Allocated and initialized with @ref JxlEncoderFrameSettingsCreate().
  /// Cleaned up and deallocated when the encoder is destroyed with
  /// @ref JxlEncoderDestroy().
  pub const FrameSettings = opaque {
    /// Sets the frame information for this frame to the encoder.
    pub fn setFrameHeader(self: *@This(), frame_header: *const Frame.Header) !void {
      return Status.check(c.JxlEncoderSetFrameHeader(@ptrCast(self), @ptrCast(frame_header)));
    }

    /// Sets blend info of an extra channel.
    pub fn setExtraChannelBlendInfo(self: *@This(), index: usize, blend_info: *const Frame.BlendInfo) !void {
      return Status.check(c.JxlEncoderSetExtraChannelBlendInfo(@ptrCast(self), index, @ptrCast(blend_info)));
    }

    /// Sets the name of the animation frame. 
    /// The maximum possible name length is 1071 bytes.
    pub fn setFrameName(self: *@This(), frame_name: [*:0]const u8) !void {
      return Status.check(c.JxlEncoderSetFrameName(@ptrCast(self), frame_name));
    }

    /// Sets the bit depth of the input buffer.
    pub fn setFrameBitDepth(self: *@This(), bit_depth: *const Types.BitDepth) !void {
      return Status.check(c.JxlEncoderSetFrameBitDepth(@ptrCast(self), @ptrCast(bit_depth)));
    }

    /// Sets the buffer to read JPEG encoded bytes from for the next frame to encode.
    pub fn addJPEGFrame(self: *const @This(), buffer: []const u8) !void {
      return Status.check(c.JxlEncoderAddJPEGFrame(@ptrCast(self), buffer.ptr, buffer.len));
    }

    /// Sets the buffer to read pixels from for the next image to encode.
    pub fn addImageFrame(self: *const @This(), format: *const Types.PixelFormat, buffer: []const u8) !void {
      return Status.check(c.JxlEncoderAddImageFrame(@ptrCast(self), @ptrCast(format), @ptrCast(buffer.ptr), buffer.len));
    }

    /// Adds a frame to the encoder using a chunked input source.
    pub fn addChunkedFrame(self: *const @This(), is_last_frame: bool, chunked_frame_input: ChunkedFrameInputSource) !void {
      return Status.check(c.JxlEncoderAddChunkedFrame(
        @ptrCast(self),
        @intFromBool(is_last_frame),
        @bitCast(chunked_frame_input),
      ));
    }

    /// Sets the buffer to read pixels from for an extra channel at a given index.
    pub fn setExtraChannelBuffer(
      self: *const @This(),
      format: *const Types.PixelFormat,
      buffer: []const u8,
      index: u32,
    ) !void {
      return Status.check(c.JxlEncoderSetExtraChannelBuffer(
        @ptrCast(self),
        @ptrCast(format),
        @ptrCast(buffer.ptr),
        buffer.len,
        index,
      ));
    }

    /// Create a new set of encoder options, tied to the encoder.
    pub fn init(enc: *Encoder, source: ?*const @This()) !*@This() {
      return @ptrCast(c.JxlEncoderFrameSettingsCreate(@ptrCast(enc), @ptrCast(source)) orelse return error.OutOfMemory);
    }

    /// Sets a frame-specific option of integer type.
    pub fn setOption(self: *@This(), option: FrameSettingId, value: i64) !void {
      return Status.check(c.JxlEncoderFrameSettingsSetOption(@ptrCast(self), @intFromEnum(option), value));
    }

    /// Sets a frame-specific option of float type.
    pub fn setFloatOption(self: *@This(), option: FrameSettingId, value: f32) !void {
      return Status.check(c.JxlEncoderFrameSettingsSetFloatOption(@ptrCast(self), @intFromEnum(option), value));
    }

    /// Enables lossless encoding for this frame.
    pub fn setLossless(self: *@This(), lossless: bool) !void {
      return Status.check(c.JxlEncoderSetFrameLossless(@ptrCast(self), @intFromBool(lossless)));
    }

    /// Sets the distance level for lossy compression (0.0 .. 25.0).
    pub fn setDistance(self: *@This(), distance: f32) !void {
      return Status.check(c.JxlEncoderSetFrameDistance(@ptrCast(self), distance));
    }

    /// Sets the distance level for lossy compression of extra channels.
    pub fn setExtraChannelDistance(self: *@This(), index: usize, distance: f32) !void {
      return Status.check(c.JxlEncoderSetExtraChannelDistance(@ptrCast(self), index, distance));
    }

    /// Sets the given debug image callback.
    pub fn setDebugImageCallback(self: *@This(), callback: DebugImageCallback, opaque_ptr: ?*anyopaque) void {
      c.JxlEncoderSetDebugImageCallback(@ptrCast(self), callback, opaque_ptr);
    }

    /// Sets the given stats object for gathering statistics during encoding.
    pub fn collectStats(self: *@This(), stats: *EncoderStats) void {
      c.JxlEncoderCollectStats(@ptrCast(self), @ptrCast(stats));
    }
  };

  /// Interface for the encoder's output processing (streaming).
  pub const OutputProcessor = extern struct {
    @"opaque": ?*anyopaque,
    get_buffer: *const fn (@"opaque": ?*anyopaque, size: *usize) callconv(.c) ?*anyopaque,
    release_buffer: *const fn (@"opaque": ?*anyopaque, written_bytes: usize) callconv(.c) void,
    seek: ?*const fn (@"opaque": ?*anyopaque, position: u64) callconv(.c) void,
    set_finalized_position: *const fn (@"opaque": ?*anyopaque, finalized_position: u64) callconv(.c) void,

    test {
      const T = c.JxlEncoderOutputProcessor;
      std.debug.assert(@sizeOf(@This()) == @sizeOf(T));
      inline for (@typeInfo(T).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(@This(), f.name) == @bitOffsetOf(T, cf.name));
      }
    }

    /// Creates an OutputProcessor from a Zig struct.
    /// The context must have:
    /// - `fn getBuffer(self: *@This(), size: *usize) ?*anyopaque`
    /// - `fn releaseBuffer(self: *@This(), written_bytes: usize) void`
    /// - `fn setFinalizedPosition(self: *@This(), pos: u64) void`
    /// - optional `fn seek(self: *@This(), pos: u64) void`
    pub fn fromContext(ctx_ptr: anytype) @This() {
      const T = @TypeOf(ctx_ptr);
      const PtrInfo = @typeInfo(T).pointer;
      const Sub = PtrInfo.child;

      const VTable = struct {
        fn getSelf(ctx: ?*anyopaque) *Sub { return @alignCast(@ptrCast(ctx.?)); }
        fn getBuffer(ctx: ?*anyopaque, size: *usize) callconv(.c) ?*anyopaque { return getSelf(ctx).getBuffer(size); }
        fn releaseBuffer(ctx: ?*anyopaque, written: usize) callconv(.c) void { getSelf(ctx).releaseBuffer(written); }
        fn seek(ctx: ?*anyopaque, pos: u64) callconv(.c) void { getSelf(ctx).seek(pos); }
        fn setFinalized(ctx: ?*anyopaque, pos: u64) callconv(.c) void { getSelf(ctx).setFinalizedPosition(pos); }
      };

      return .{
        .@"opaque" = ctx_ptr,
        .get_buffer = &VTable.getBuffer,
        .release_buffer = &VTable.releaseBuffer,
        .seek = if (@hasDecl(Sub, "seek")) &VTable.seek else null,
        .set_finalized_position = &VTable.setFinalized,
      };
    }
  };

  /// Interface to pass pixel data in a streaming manner.
  pub const ChunkedFrameInputSource = extern struct {
    @"opaque": ?*anyopaque,
    get_color_channels_pixel_format: *const fn (@"opaque": ?*anyopaque, format: *Types.PixelFormat) callconv(.c) void,
    get_color_channel_data_at: *const fn (@"opaque": ?*anyopaque, xpos: usize, ypos: usize, xsize: usize, ysize: usize, row_offset: *usize) callconv(.c) ?*const anyopaque,
    get_extra_channel_pixel_format: *const fn (@"opaque": ?*anyopaque, ec_index: usize, format: *Types.PixelFormat) callconv(.c) void,
    get_extra_channel_data_at: *const fn (@"opaque": ?*anyopaque, ec_index: usize, xpos: usize, ypos: usize, xsize: usize, ysize: usize, row_offset: *usize) callconv(.c) ?*const anyopaque,
    release_buffer: *const fn (@"opaque": ?*anyopaque, buf: ?*const anyopaque) callconv(.c) void,

    test {
      const T = c.JxlChunkedFrameInputSource;
      std.debug.assert(@sizeOf(@This()) == @sizeOf(T));
      inline for (@typeInfo(T).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(@This(), f.name) == @bitOffsetOf(T, cf.name));
      }
    }

    /// Creates a ChunkedFrameInputSource from a Zig struct.
    pub fn fromContext(ctx_ptr: anytype) @This() {
      const T = @TypeOf(ctx_ptr);
      const PtrInfo = @typeInfo(T).pointer;
      const Sub = PtrInfo.child;

      const VTable = struct {
        fn getSelf(ctx: ?*anyopaque) *Sub { return @alignCast(@ptrCast(ctx.?)); }
        fn getColorFmt(ctx: ?*anyopaque, fmt: *Types.PixelFormat) callconv(.c) void { getSelf(ctx).getColorChannelsPixelFormat(fmt); }
        fn getColorData(ctx: ?*anyopaque, x: usize, y: usize, xs: usize, ys: usize, ro: *usize) callconv(.c) ?*const anyopaque { return getSelf(ctx).getColorChannelDataAt(x, y, xs, ys, ro); }
        fn getExtraFmt(ctx: ?*anyopaque, idx: usize, fmt: *Types.PixelFormat) callconv(.c) void { getSelf(ctx).getExtraChannelPixelFormat(idx, fmt); }
        fn getExtraData(ctx: ?*anyopaque, idx: usize, x: usize, y: usize, xs: usize, ys: usize, ro: *usize) callconv(.c) ?*const anyopaque { return getSelf(ctx).getExtraChannelDataAt(idx, x, y, xs, ys, ro); }
        fn release(ctx: ?*anyopaque, buf: ?*const anyopaque) callconv(.c) void { getSelf(ctx).releaseBuffer(buf); }
      };

      return .{
        .@"opaque" = ctx_ptr,
        .get_color_channels_pixel_format = &VTable.getColorFmt,
        .get_color_channel_data_at = &VTable.getColorData,
        .get_extra_channel_pixel_format = &VTable.getExtraFmt,
        .get_extra_channel_data_at = &VTable.getExtraData,
        .release_buffer = &VTable.release,
      };
    }
  };

  /// Sets the output processor for the encoder. This processor determines how the
  /// encoder will handle buffering, writing, seeking, and setting a finalized position.
  /// This should not be used when using @ref JxlEncoderProcessOutput.
  pub fn setOutputProcessor(self: *@This(), output_processor: OutputProcessor) !void {
    return Status.check(c.JxlEncoderSetOutputProcessor(@ptrCast(self), @bitCast(output_processor)));
  }

  /// Flushes any buffered input in the encoder.
  /// This function can only be used after @ref JxlEncoderSetOutputProcessor.
  pub fn flushInput(self: *@This()) !void {
    return Status.check(c.JxlEncoderFlushInput(@ptrCast(self)));
  }

  /// Adds a metadata box to the file format. @ref JxlEncoderUseBoxes must
  /// be enabled before using this function.
  pub fn addBox(self: *@This(), box_type: *const Types.BoxType, contents: []const u8, compress_box: bool) !void {
    return Status.check(c.JxlEncoderAddBox(@ptrCast(self), @as(*const [4]u8, @ptrCast(box_type)), contents.ptr, contents.len, @intFromBool(compress_box)));
  }

  /// Indicates the intention to add metadata boxes.
  pub fn useBoxes(self: *@This()) !void {
    return Status.check(c.JxlEncoderUseBoxes(@ptrCast(self)));
  }

  /// Declares that no further boxes will be added.
  pub fn closeBoxes(self: *@This()) void {
    c.JxlEncoderCloseBoxes(@ptrCast(self));
  }

  /// Declares that no frames will be added.
  pub fn closeFrames(self: *@This()) void {
    c.JxlEncoderCloseFrames(@ptrCast(self));
  }

  /// Closes any input to the encoder.
  pub fn closeInput(self: *@This()) void {
    c.JxlEncoderCloseInput(@ptrCast(self));
  }

  /// Sets the original color encoding as structured data.
  pub fn setColorEncoding(self: *@This(), color: *const ColorEncoding) !void {
    return Status.check(c.JxlEncoderSetColorEncoding(@ptrCast(self), @ptrCast(color)));
  }

  /// Sets the original color encoding as an ICC color profile.
  pub fn setICCProfile(self: *@This(), icc_profile: []const u8) !void {
    return Status.check(c.JxlEncoderSetICCProfile(@ptrCast(self), icc_profile.ptr, icc_profile.len));
  }

  /// Sets the global metadata of the image.
  pub fn setBasicInfo(self: *@This(), info: *const Codestream.BasicInfo) !void {
    return Status.check(c.JxlEncoderSetBasicInfo(@ptrCast(self), @ptrCast(info)));
  }

  /// Sets the upsampling method the decoder will use.
  /// factor: 1, 2, 4 or 8.
  /// mode: -1 (default), 0 (nearest neighbor), 1 (pixel dots).
  pub fn setUpsamplingMode(self: *@This(), factor: i64, mode: i64) !void {
    return Status.check(c.JxlEncoderSetUpsamplingMode(@ptrCast(self), factor, mode));
  }

  /// Sets information for the extra channel at the given index.
  pub fn setExtraChannelInfo(self: *@This(), index: usize, info: *const Codestream.ExtraChannelInfo) !void {
    return Status.check(c.JxlEncoderSetExtraChannelInfo(@ptrCast(self), index, @ptrCast(info)));
  }

  /// Sets the name for the extra channel at the given index in UTF-8.
  pub fn setExtraChannelName(self: *@This(), index: usize, name: [*:0]const u8) !void {
    return Status.check(c.JxlEncoderSetExtraChannelName(@ptrCast(self), index, name, std.mem.sliceTo(name, 0).len));
  }

  /// Forces the encoder to use the box-based container format (BMFF).
  pub fn useContainer(self: *@This(), use: bool) !void {
    return Status.check(c.JxlEncoderUseContainer(@ptrCast(self), @intFromBool(use)));
  }

  /// Configure the encoder to store JPEG reconstruction metadata.
  pub fn storeJPEGMetadata(self: *@This(), store: bool) !void {
    return Status.check(c.JxlEncoderStoreJPEGMetadata(@ptrCast(self), @intFromBool(store)));
  }

  /// Sets the feature level of the JPEG XL codestream (5, 10, or -1).
  pub fn setCodestreamLevel(self: *@This(), level: i32) !void {
    return Status.check(c.JxlEncoderSetCodestreamLevel(@ptrCast(self), level));
  }

  /// Returns the codestream level required to support the currently configured settings.
  pub fn getRequiredCodestreamLevel(self: *const @This()) i32 {
    return c.JxlEncoderGetRequiredCodestreamLevel(@ptrCast(self));
  }

  /// Enables usage of expert options (e.g., effort 11).
  pub fn allowExpertOptions(self: *@This()) void {
    c.JxlEncoderAllowExpertOptions(@ptrCast(self));
  }

  /// Maps JPEG-style quality factor to distance.
  pub fn distanceFromQuality(quality: f32) f32 {
    return c.JxlEncoderDistanceFromQuality(quality);
  }
};

/// Color encoding of the image as structured information.
pub const ColorEncoding = extern struct {
  /// Color space of the image data.
  color_space: ColorSpace,

  /// Built-in white point. If this value is ::JXL_WHITE_POINT_CUSTOM, must
  /// use the numerical white point values from white_point_xy.
  white_point: WhitePoint,

  /// Numerical whitepoint values in CIE xy space.
  white_point_xy: [2]f64,

  /// Built-in RGB primaries. If this value is ::JXL_PRIMARIES_CUSTOM, must
  /// use the numerical primaries values below. This field and the custom values
  /// below are unused and must be ignored if the color space is
  /// ::JXL_COLOR_SPACE_GRAY or ::JXL_COLOR_SPACE_XYB.
  primaries: Primaries,

  /// Numerical red primary values in CIE xy space.
  primaries_red_xy: [2]f64,

  /// Numerical green primary values in CIE xy space.
  primaries_green_xy: [2]f64,

  /// Numerical blue primary values in CIE xy space.
  primaries_blue_xy: [2]f64,

  /// Transfer function if have_gamma is 0
  transfer_function: TransferFunction,

  /// Gamma value used when transfer_function is @ref
  /// JXL_TRANSFER_FUNCTION_GAMMA
  gamma: f64,

  /// Rendering intent defined for the color profile.
  rendering_intent: RenderingIntent,

  test {
    const T = c.JxlColorEncoding;
    std.debug.assert(@sizeOf(@This()) == @sizeOf(T));
    inline for (@typeInfo(T).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
      std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
      std.debug.assert(@bitOffsetOf(@This(), f.name) == @bitOffsetOf(T, cf.name));
    }
  }

  pub const ColorSpace = enum(c.JxlColorSpace) {
    /// Tristimulus RGB
    rgb = @bitCast(c.JXL_COLOR_SPACE_RGB),
    /// Luminance based, the primaries in @ref JxlColorEncoding must be ignored.
    /// This value implies that num_color_channels in @ref JxlBasicInfo is 1, any
    /// other value implies num_color_channels is 3.
    gray = @bitCast(c.JXL_COLOR_SPACE_GRAY),
    /// XYB (opsin) color space
    xyb = @bitCast(c.JXL_COLOR_SPACE_XYB),
    /// None of the other table entries describe the color space appropriately
    unknown = @bitCast(c.JXL_COLOR_SPACE_UNKNOWN),
    _, // future expansion
  };

  /// Built-in white points for color encoding. When decoding, the numerical xy
  /// white point value can be read from the @ref JxlColorEncoding white_point
  /// field regardless of the enum value. When encoding, enum values except
  /// ::JXL_WHITE_POINT_CUSTOM override the numerical fields. Some enum values
  /// match a subset of CICP (Rec. ITU-T H.273 | ISO/IEC 23091-2:2019(E)), however
  /// the white point and RGB primaries are separate enums here.
  pub const WhitePoint = enum(c.JxlWhitePoint) {
    /// CIE Standard Illuminant D65: 0.3127, 0.3290
    d65 = @bitCast(c.JXL_WHITE_POINT_D65),
    /// White point must be read from the @ref JxlColorEncoding white_point field,
    /// or as ICC profile. This enum value is not an exact match of the
    /// corresponding CICP value.
    custom = @bitCast(c.JXL_WHITE_POINT_CUSTOM),
    /// CIE Standard Illuminant E (equal-energy): 1/3, 1/3
    e = @bitCast(c.JXL_WHITE_POINT_E),
    /// DCI-P3 from SMPTE RP 431-2: 0.314, 0.351
    dci = @bitCast(c.JXL_WHITE_POINT_DCI),
    _, // future expansion
  };

  /// Built-in primaries for color encoding. When decoding, the primaries can be
  /// read from the @ref JxlColorEncoding primaries_red_xy, primaries_green_xy and
  /// primaries_blue_xy fields regardless of the enum value. When encoding, the
  /// enum values except ::JXL_PRIMARIES_CUSTOM override the numerical fields.
  /// Some enum values match a subset of CICP (Rec. ITU-T H.273 | ISO/IEC
  /// 23091-2:2019(E)), however the white point and RGB primaries are separate
  /// enums here.
  pub const Primaries = enum(c.JxlPrimaries) {
    /// The CIE xy values of the red, green and blue primaries are: 0.639998686,
    /// 0.330010138; 0.300003784, 0.600003357; 0.150002046, 0.059997204
    srgb = @bitCast(c.JXL_PRIMARIES_SRGB),
    /// Primaries must be read from the @ref JxlColorEncoding primaries_red_xy,
    /// primaries_green_xy and primaries_blue_xy fields, or as ICC profile. This
    /// enum value is not an exact match of the corresponding CICP value.
    custom = @bitCast(c.JXL_PRIMARIES_CUSTOM),
    /// As specified in Rec. ITU-R BT.2100-1
    p2100 = @bitCast(c.JXL_PRIMARIES_2100),
    /// As specified in SMPTE RP 431-2
    p3 = @bitCast(c.JXL_PRIMARIES_P3),
  };

  /// Built-in transfer functions for color encoding. Enum values match a subset
  /// of CICP (Rec. ITU-T H.273 | ISO/IEC 23091-2:2019(E)) unless specified
  /// otherwise.
  pub const TransferFunction = enum(c.JxlTransferFunction) {
    /// As specified in ITU-R BT.709-6
    bt709 = @bitCast(c.JXL_TRANSFER_FUNCTION_709),
    /// None of the other table entries describe the transfer function.
    unknown = @bitCast(c.JXL_TRANSFER_FUNCTION_UNKNOWN),
    /// The gamma exponent is 1
    linear = @bitCast(c.JXL_TRANSFER_FUNCTION_LINEAR),
    /// As specified in IEC 61966-2-1 sRGB
    srgb = @bitCast(c.JXL_TRANSFER_FUNCTION_SRGB),
    /// As specified in SMPTE ST 2084
    pq = @bitCast(c.JXL_TRANSFER_FUNCTION_PQ),
    /// As specified in SMPTE ST 428-1
    dci = @bitCast(c.JXL_TRANSFER_FUNCTION_DCI),
    /// As specified in Rec. ITU-R BT.2100-1 (HLG)
    hlg = @bitCast(c.JXL_TRANSFER_FUNCTION_HLG),
    /// Transfer function follows power law given by the gamma value in @ref
    /// JxlColorEncoding. Not a CICP value.
    gamma = @bitCast(c.JXL_TRANSFER_FUNCTION_GAMMA),
  };

  /// Rendering intent for color encoding, as specified in ISO 15076-1:2010
  pub const RenderingIntent = enum(c.JxlRenderingIntent) {
    /// vendor-specific
    perceptual = @bitCast(c.JXL_RENDERING_INTENT_PERCEPTUAL),
    /// media-relative
    relative = @bitCast(c.JXL_RENDERING_INTENT_RELATIVE),
    /// vendor-specific
    saturation = @bitCast(c.JXL_RENDERING_INTENT_SATURATION),
    /// ICC-absolute
    absolute = @bitCast(c.JXL_RENDERING_INTENT_ABSOLUTE),
  };

  pub fn setToSRGB(self: *@This(), is_gray: bool) void {
    c.JxlColorEncodingSetToSRGB(@ptrCast(self), @intFromBool(is_gray));
  }

  pub fn setToLinearSRGB(self: *@This(), is_gray: bool) void {
    c.JxlColorEncodingSetToLinearSRGB(@ptrCast(self), @intFromBool(is_gray));
  }
};

pub const ICC = if (config.icc) struct {
  /// Allocates a buffer using the memory manager, fills it with a compressed
  /// representation of an ICC profile, returns the result through @c output_buffer
  /// and indicates its size through @c output_size.
  ///
  /// The result must be freed using the memory manager once it is not of any more use.
  ///
  /// @param[in] memory_manager Pointer to a MemoryManager.
  /// @param[in] icc Pointer to a buffer containing the uncompressed ICC profile.
  /// @return the buffer containing the result or error.Failed
  pub fn encode(memory_manager: *const MemoryManager, icc: []const u8) error{Failed}![]u8 {
    var result: []u8 = undefined;
    if (c.JxlICCProfileEncode(@ptrCast(memory_manager), icc.ptr, icc.len, @ptrCast(&result.ptr), &result.len) == c.JXL_TRUE) return result;
    return error.Failed;
  }

  /// Allocates a buffer using the memory manager, fills it with the decompressed
  /// version of the ICC profile in @c compressed_icc, returns the result through
  /// @c output_buffer and indicates its size through @c output_size.
  ///
  /// The result must be freed using the memory manager once it is not of any more use.
  ///
  /// @param[in] memory_manager Pointer to a JxlMemoryManager.
  /// @param[in] compressed_icc Pointer to a buffer containing the compressed ICC profile.
  /// @return the buffer containing the result or error.Failed
  pub fn decode(memory_manager: *const MemoryManager, compressed_icc: []const u8) error{Failed}![]u8 {
    var result: []u8 = undefined;
    if (c.JxlICCProfileDecode(@ptrCast(memory_manager), compressed_icc.ptr, compressed_icc.len, @ptrCast(&result.ptr), &result.len) == c.JXL_TRUE) return result;
    return error.Failed;
  }
} else void;

/// Gain map bundle
///
/// This structure is used to serialize gain map data to and from an input
/// buffer. It holds pointers to sections within the buffer, and different parts
/// of the gain map data such as metadata, ICC profile data, and the gain map
/// itself.
///
/// The pointers in this structure do not take ownership of the memory they point
/// to. Instead, they reference specific locations within the provided buffer. It
/// is the caller's responsibility to ensure that the buffer remains valid and is
/// not deallocated as long as these pointers are in use. The structure should be
/// considered as providing a view into the buffer, not as an owner of the data.
pub const GainMapBundle = if (config.gain_map) extern struct {
  jhgm_version: u8,
  /// Size of the gain map metadata in bytes.
  gain_map_metadata_size: u16,
  /// Pointer to the gain map metadata, which is a binary
  /// blob following ISO 21496-1. This pointer references data within the input
  /// buffer.
  gain_map_metadata: ?[*]const u8,
  /// Indicates whether a color encoding is present.
  has_color_encoding: Types.Bool,
  /// If has_color_encoding is true, this field contains the
  /// uncompressed color encoding data.
  color_encoding: ColorEncoding,
  /// Size of the alternative ICC profile in bytes (compressed
  /// size).
  alt_icc_size: u32,
  /// Pointer to the compressed ICC profile. This pointer references
  /// data within the input buffer.
  alt_icc: ?[*]const u8,
  /// Size of the gain map in bytes.
  gain_map_size: u32,
  /// Pointer to the gain map data, which is a JPEG XL naked
  /// codestream. This pointer references data within the input buffer.
  gain_map: ?[*]const u8,

  test {
    const T = c.JxlGainMapBundle;
    std.debug.assert(@sizeOf(@This()) == @sizeOf(T));
    inline for (@typeInfo(T).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
      std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
      std.debug.assert(@bitOffsetOf(@This(), f.name) == @bitOffsetOf(T, cf.name));
    }
  }

  /// Calculates the total size required to serialize the gain map bundle into a
  /// binary buffer. This function accounts for all the necessary space to
  /// serialize fields such as gain map metadata, color encoding, compressed ICC
  /// profile data, and the gain map itself.
  ///
  /// @param[in] map_bundle Pointer to the JxlGainMapBundle containing all necessary data to compute the size.
  /// @return bundle_size: The size in bytes required to serialize the bundle or error.Failed if the operation failed.
  pub fn getBundleSize(self: *const @This()) error{Failed}!usize {
    var out: usize = undefined;
    if (c.JxlGainMapGetBundleSize(@ptrCast(self), &out) == c.JXL_TRUE) return out;
    return error.Failed;
  }

  /// Serializes the gain map bundle into a preallocated buffer. The function
  /// ensures that all parts of the bundle such as metadata, color encoding,
  /// compressed ICC profile, and the gain map are correctly encoded into the
  /// buffer. First call `getBundleSize` to get the size needed for the buffer.
  ///
  /// @param[in] map_bundle Pointer to the `JxlGainMapBundle` to serialize.
  /// @param[out] output_buffer Pointer to the buffer where the serialized data will be written.
  ///   The size of the output buffer in bytes. Must be large enough to hold the entire serialized data.
  /// Returns the number of bytes written on success or error.Failed if the operation failed
  pub fn writeBundle(self: *const @This(), output_buffer: []u8) error{Failed}!usize {
    var out: usize = undefined;
    if (c.JxlGainMapWriteBundle(@ptrCast(self), output_buffer.ptr, output_buffer.len, &out) == c.JXL_TRUE) return out;
    return error.Failed;
  }

  /// Deserializes a gain map bundle from a provided buffer and populates a
  /// `GainMapBundle` structure with the data extracted. This function assumes
  /// the buffer contains a valid serialized gain map bundle. After successful
  /// execution, the `GainMapBundle` structure will reference three different
  /// sections within the buffer:
  ///  - gain_map_metadata
  ///  - alt_icc
  ///  - gain_map
  /// These sections will be accompanied by their respective sizes. Users must
  /// ensure that the buffer remains valid as long as these pointers are in use.
  /// @param[in,out] self: Pointer to a preallocated `GainMapBundle` where the deserialized data will be stored.
  /// @param[in] input_buffer Pointer to the buffer containing the serialized gain map bundle data.
  /// @return The number of bytes read from the input buffer or error.Failed is the operation failed
  pub fn readBundle(self: *@This(), input_buffer: []const u8) error{Failed}!usize {
    var out: usize = undefined;
    if (c.JxlGainMapReadBundle(@ptrCast(self), input_buffer.ptr, input_buffer.len, &out) == c.JXL_TRUE) return out;
    return error.Failed;
  }
} else void;

/// Memory Manager struct.
/// These functions, when provided by the caller, will be used to handle memory
/// allocations.
pub const MemoryManager = extern struct {
  pub const Context = opaque{};
  /// The opaque pointer that will be passed as the first parameter to all the
  /// functions in this struct.
  _ctx: ?*Context,

  /// Memory allocation function. This can be NULL if and only if also the
  /// free() member in this class is NULL. All dynamic memory will be allocated
  /// and freed with these functions if they are not NULL, otherwise with the
  /// standard malloc/free.
  _alloc_fn: AllocFn,

  /// Free function matching the alloc() member.
  _free_fn: FreeFn,

  test {
    const T = c.JxlMemoryManager;
    std.debug.assert(@sizeOf(@This()) == @sizeOf(T));
    inline for (@typeInfo(T).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
      std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
      std.debug.assert(@bitOffsetOf(@This(), f.name) == @bitOffsetOf(T, cf.name));
    }
  }

  /// Allocating function for a memory region of a given size.
  ///
  /// Allocates a contiguous memory region of size @p size bytes. The returned
  /// memory may not be aligned to a specific size or initialized at all.
  ///
  /// @param opaque custom memory manager handle provided by the caller.
  /// @param size in bytes of the requested memory region.
  /// @return @c NULL if the memory can not be allocated,
  /// @return pointer to the memory otherwise.
  pub const AllocFn = *const fn (opaque_ptr: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque;

  /// Deallocating function pointer type.
  ///
  /// This function @b MUST do nothing if @p address is @c NULL.
  ///
  /// @param opaque custom memory manager handle provided by the caller.
  /// @param address memory region pointer returned by ::jpegxl_alloc_func, or @c
  /// NULL.
  pub const FreeFn = *const fn (opaque_ptr: ?*anyopaque, address: ?*anyopaque) callconv(.c) void;

  // The returned memory is may not be aligned to a specific size or initialized at all.
  pub fn _alloc(self: *const @This(), size: usize) ![]u8 {
    return @as([*]u8, @ptrCast(self._alloc_fn(self._ctx, size) orelse return error.OutOfMemory))[0 .. size];
  }

  pub fn alloc(self: *const @This(), comptime T: type, count: usize) ![]align(1) T {
    const mem = try _alloc(self, @sizeOf(T) * count);
    return @as([*]align(1)T, @ptrCast(mem.ptr))[0..count];
  }

  pub fn free(self: *const @This(), ptr: ?[*]u8) void {
    self._free_fn(self._ctx, @ptrCast(ptr));
  }
};

pub const ParallelRunner = if (config.threading) opaque {
  /// Return code used in the JxlParallel* functions as return value. A value
  /// of ::JXL_PARALLEL_RET_SUCCESS means success and any other value means error.
  /// The special value ::JXL_PARALLEL_RET_RUNNER_ERROR can be used by the runner
  /// to indicate any other error.
  pub const RetCode = enum(c.JxlParallelRetCode) {
    /// Code returned by the @ref JxlParallelRunInit function to indicate success.
    success = 0,
    /// Code returned by the @ref JxlParallelRunInit function to indicate a general
    /// error.
    @"error" = -1,
    /// Allow for custom error codes returned by the runner or init callbacks
    _,

    pub fn check(int: c.JxlParallelRetCode) !void {
      return switch (@as(@This(), @enumFromInt(int))) {
        .success => {},
        .@"error" => error.ParallelExecutionError,
        else => error.UnknownParallelRunnerRetCode
      };
    }
  };

  /// JxlParallelRunner function type. A parallel runner implementation can be
  /// provided by a JPEG XL caller to allow running computations in multiple
  /// threads. This function must call the initialization function @p init in the
  /// same thread that called it and then call the passed @p func once for every
  /// number in the range [start_range, end_range) (including start_range but not
  /// including end_range) possibly from different multiple threads in parallel.
  ///
  /// The @ref JxlParallelRunner function does not need to be re-entrant. This
  /// means that the same @ref JxlParallelRunner function with the same
  /// runner_opaque provided parameter will not be called from the library from
  /// either @p init or @p func in the same decoder or encoder instance. 
  /// However, a single decoding or encoding instance may call the provided 
  /// @ref JxlParallelRunner multiple times for different parts of the 
  /// decoding or encoding process.
  ///
  /// @return 0 if the @p init call succeeded (returned 0) and no other error
  /// occurred in the runner code.
  /// @return JXL_PARALLEL_RET_RUNNER_ERROR if an error occurred in the runner
  /// code, for example, setting up the threads.
  /// @return the return value of @p init() if non-zero.
  pub const RunnerFn = *const fn (
    runner_opaque: ?*anyopaque,
    jpegxl_opaque: ?*anyopaque,
    init: ?RunContext.InitFn,
    func: ?RunContext.RunFn,
    start_range: u32,
    end_range: u32,
  ) callconv(.c) c.JxlParallelRetCode;

  pub const RunContext = struct {
    ctx: ?*anyopaque,
    init_fn: ?InitFn,
    run_fn: RunFn,

    /// Parallel run initialization callback. See @ref JxlParallelRunner for details.
    ///
    /// This function MUST be called by the JxlParallelRunner only once, on the
    /// same thread that called @ref JxlParallelRunner, before any parallel
    /// execution. The purpose of this call is to provide the maximum number of
    /// threads that the @ref JxlParallelRunner will use, which can be used by 
    /// JPEG XL to allocate per-thread storage if needed.
    ///
    /// @param jpegxl_opaque the @p jpegxl_opaque handle provided to
    /// @ref JxlParallelRunner() must be passed here.
    /// @param num_threads the maximum number of threads. This value must be
    /// positive.
    /// @return 0 if the initialization process was successful.
    /// @return an error code if there was an error, which should be returned by
    /// @ref JxlParallelRunner().
    pub const InitFn = *const fn (jpegxl_opaque: ?*anyopaque, num_threads: usize) callconv(.c) c.JxlParallelRetCode;

    /// Parallel run data processing callback. See @ref JxlParallelRunner for
    /// details.
    ///
    /// This function MUST be called once for every number in the range [start_range,
    /// end_range) (including start_range but not including end_range) passing this
    /// number as the @p value. Calls for different value may be executed from
    /// different threads in parallel.
    ///
    /// @param jpegxl_opaque the @p jpegxl_opaque handle provided to
    /// @ref JxlParallelRunner() must be passed here.
    /// @param value the number in the range [start_range, end_range) of the call.
    /// @param thread_id the thread number where this function is being called from.
    /// This must be lower than the @p num_threads value passed to
    /// @ref JxlParallelRunInit.
    pub const RunFn = *const fn (jpegxl_opaque: ?*anyopaque, value: u32, thread_id: usize) callconv(.c) void;

    /// The context must have the following functions
    /// - optional `fn init(self: *@This(), num_threads: usize) !void`
    /// - `fn run(self: *@This(), value: u32, thread_id: u32) void`
    pub fn fromContext(ctx_ptr: anytype) @This() {
      const T = @TypeOf(ctx_ptr);
      const Sub = if(@typeInfo(T) == .pointer) @typeInfo(T).pointer.child else T;
      const VTable = struct {
        pub fn getSelf(ctx: ?*anyopaque) @TypeOf(ctx_ptr) {
          return @alignCast(@ptrCast(ctx));
        }

        pub fn init(jpegxl_opaque: ?*anyopaque, num_threads: usize) callconv(.c) c.JxlParallelRetCode {
          getSelf(jpegxl_opaque).init(num_threads) catch return @intFromEnum(RetCode.@"error");
          return @intFromEnum(RetCode.success);
        }

        pub fn run (jpegxl_opaque: ?*anyopaque, value: u32, thread_id: usize) callconv(.c) void {
          getSelf(jpegxl_opaque).run(value, thread_id);
        }
      };

      return .{
        .ctx = if (@bitSizeOf(Sub) == 0) null else @ptrCast(ctx_ptr),
        .init_fn = if (@hasDecl(Sub, "init")) &VTable.init else null,
        .run_fn = &VTable.run,
      };
    }
  };

  const RunRange = struct {
    from: u32,
    to: u32,
  };

  /// Parallel runner internally using std::thread. Use as @ref JxlParallelRunner.
  pub const Resizable = opaque {
    /// Creates the runner for @ref JxlResizableParallelRunner. Use as the opaque
    /// runner. The runner will execute tasks on the calling thread until
    /// @ref JxlResizableParallelRunnerSetThreads is called.
    pub fn init(memory_manager: ?*const MemoryManager) !*@This() {
      return @ptrCast(c.JxlResizableParallelRunnerCreate(@ptrCast(memory_manager)) orelse return error.OutOfMemory);
    }

    /// Destroys the runner created by @ref JxlResizableParallelRunnerCreate.
    pub fn deinit(self: *@This()) void {
      c.JxlResizableParallelRunnerDestroy(@ptrCast(self));
    }

    /// Parallel runner internally using std::thread. Use as @ref JxlParallelRunner.
    pub fn run(self: *@This(), ctx: RunContext, range: RunRange) !void {
      return RetCode.check(c.JxlResizableParallelRunner(@ptrCast(self), ctx.ctx, ctx.init_fn, ctx.run_fn, range.from, range.to));
    }

    /// Changes the number of threads for @ref JxlResizableParallelRunner.
    pub fn setThreads(self: *@This(), num_threads: usize) void {
      c.JxlResizableParallelRunnerSetThreads(@ptrCast(self), num_threads);
    }

    /// Suggests a number of threads to use for an image of given size.
    pub fn suggestThreads(xsize: u64, ysize: u64) u32 {
      return c.JxlResizableParallelRunnerSuggestThreads(xsize, ysize);
    }

    pub fn toAny(self: *@This()) *ParallelRunner {
      return @ptrCast(self);
    }
  };

  pub const Threaded = opaque {
    /// Creates the runner for @ref JxlThreadParallelRunner. Use as the opaque runner.
    pub fn init(memory_manager: ?*const MemoryManager, num_worker_threads: usize) ?*@This() {
      return @ptrCast(c.JxlThreadParallelRunnerCreate(@ptrCast(memory_manager), num_worker_threads));
    }

    /// Parallel runner internally using std::thread. Use as @ref JxlParallelRunner.
    pub fn run(self: *@This(), ctx: RunContext, range: RunRange) !void {
      return RetCode.check(c.JxlThreadParallelRunner(@ptrCast(self), ctx.ctx, ctx.init_fn, ctx.run_fn, range.from, range.to));
    }

    /// Destroys the runner created by @ref JxlThreadParallelRunnerCreate.
    pub fn deinit(self: *@This()) void {
      c.JxlThreadParallelRunnerDestroy(@ptrCast(self));
    }

    /// Returns a default num_worker_threads value for
    /// @ref JxlThreadParallelRunnerCreate.
    pub fn defaultWorkerThreads() usize {
      return c.JxlThreadParallelRunnerDefaultNumWorkerThreads();
    }

    pub fn toAny(self: *@This()) *ParallelRunner {
      return @ptrCast(self);
    }
  };
} else void;

/// Opaque structure that holds the encoder statistics.
///
/// Allocated and initialized with @ref JxlEncoderStatsCreate().
/// Cleaned up and deallocated with @ref JxlEncoderStatsDestroy().
pub const EncoderStats = struct {
  /// Creates an instance of JxlEncoderStats and initializes it.
  ///
  /// @return pointer to initialized @ref EncoderStats instance
  pub fn init() !*@This() {
    return @ptrCast(c.JxlEncoderStatsCreate() orelse return error.OutOfMemory);
  }

  /// Deinitializes and frees JxlEncoderStats instance.
  ///
  /// @param stats instance to be cleaned up and deallocated.
  pub fn deinit(stats: *@This()) void {
    c.JxlEncoderStatsDestroy(@ptrCast(stats));
  }

  /// Data type for querying @ref JxlEncoderStats object
  pub const Key = enum(c.JxlEncoderStatsKey) {
    header_bits = @bitCast(c.JXL_ENC_STAT_HEADER_BITS),
    toc_bits = @bitCast(c.JXL_ENC_STAT_TOC_BITS),
    dictionary_bits = @bitCast(c.JXL_ENC_STAT_DICTIONARY_BITS),
    splines_bits = @bitCast(c.JXL_ENC_STAT_SPLINES_BITS),
    noise_bits = @bitCast(c.JXL_ENC_STAT_NOISE_BITS),
    quant_bits = @bitCast(c.JXL_ENC_STAT_QUANT_BITS),
    modular_tree_bits = @bitCast(c.JXL_ENC_STAT_MODULAR_TREE_BITS),
    modular_global_bits = @bitCast(c.JXL_ENC_STAT_MODULAR_GLOBAL_BITS),
    dc_bits = @bitCast(c.JXL_ENC_STAT_DC_BITS),
    modular_dc_group_bits = @bitCast(c.JXL_ENC_STAT_MODULAR_DC_GROUP_BITS),
    control_fields_bits = @bitCast(c.JXL_ENC_STAT_CONTROL_FIELDS_BITS),
    coef_order_bits = @bitCast(c.JXL_ENC_STAT_COEF_ORDER_BITS),
    ac_histogram_bits = @bitCast(c.JXL_ENC_STAT_AC_HISTOGRAM_BITS),
    ac_bits = @bitCast(c.JXL_ENC_STAT_AC_BITS),
    modular_ac_group_bits = @bitCast(c.JXL_ENC_STAT_MODULAR_AC_GROUP_BITS),
    num_small_blocks = @bitCast(c.JXL_ENC_STAT_NUM_SMALL_BLOCKS),
    num_dct4x8_blocks = @bitCast(c.JXL_ENC_STAT_NUM_DCT4X8_BLOCKS),
    num_afv_blocks = @bitCast(c.JXL_ENC_STAT_NUM_AFV_BLOCKS),
    num_dct8_blocks = @bitCast(c.JXL_ENC_STAT_NUM_DCT8_BLOCKS),
    num_dct8x32_blocks = @bitCast(c.JXL_ENC_STAT_NUM_DCT8X32_BLOCKS),
    num_dct16_blocks = @bitCast(c.JXL_ENC_STAT_NUM_DCT16_BLOCKS),
    num_dct16x32_blocks = @bitCast(c.JXL_ENC_STAT_NUM_DCT16X32_BLOCKS),
    num_dct32_blocks = @bitCast(c.JXL_ENC_STAT_NUM_DCT32_BLOCKS),
    num_dct32x64_blocks = @bitCast(c.JXL_ENC_STAT_NUM_DCT32X64_BLOCKS),
    num_dct64_blocks = @bitCast(c.JXL_ENC_STAT_NUM_DCT64_BLOCKS),
    num_butteraugli_iters = @bitCast(c.JXL_ENC_STAT_NUM_BUTTERAUGLI_ITERS),
    num_stats = @bitCast(c.JXL_ENC_NUM_STATS),
  };

  /// Returns the value of the statistics corresponding the given key.
  ///
  /// @param stats object that was passed to the encoder with a
  ///   @ref JxlEncoderCollectStats function
  /// @param key the particular statistics to query
  ///
  /// @return the value of the statistics
  pub fn get(stats: *const @This(), key: Key) usize {
    return c.JxlEncoderStatsGet(@ptrCast(stats), @intFromEnum(key));
  }

  /// Updates the values of the given stats object with that of an other.
  ///
  /// @param stats object whose values will be updated (usually added together)
  /// @param other stats object whose values will be merged with stats
  pub fn merge(stats: *@This(), other: *const EncoderStats) void {
    c.JxlEncoderStatsMerge(@ptrCast(stats), @ptrCast(other));
  }
};

pub const Types = struct {
  /// The bool type used by libjxl
  pub const Bool = enum(c.JXL_BOOL) {
    true = c.JXL_TRUE,
    false = c.JXL_FALSE,
  };

  pub const BoxType = enum(u32) {
    // Basic Container Boxes
    jxl_signature = std.mem.readInt(u32, "JXL ", .big),
    ftyp          = std.mem.readInt(u32, "ftyp", .big),
    level         = std.mem.readInt(u32, "jxll", .big),
    
    // Codestream Boxes
    codestream         = std.mem.readInt(u32, "jxlc", .big),
    partial_codestream = std.mem.readInt(u32, "jxlp", .big),
    index              = std.mem.readInt(u32, "jxli", .big),
    
    // Metadata Boxes
    exif = std.mem.readInt(u32, "Exif", .big),
    xml  = std.mem.readInt(u32, "xml ", .big),
    jumb = std.mem.readInt(u32, "jumb", .big),
    brob = std.mem.readInt(u32, "brob", .big),
    
    // Feature Specific
    jpeg_reconstruction = std.mem.readInt(u32, "jbrd", .big),

    /// Returns the enum if the value is a known box type
    pub fn fromInt(val: u32) !BoxType {
      return std.meta.intToEnum(BoxType, val);
    }

    /// Helper to convert a 4-byte array directly to the enum
    pub fn fromBytes(bytes: [4]u8) !BoxType {
      return fromInt(std.mem.readInt(u32, &bytes, .big));
    }
  };

  /// Data type for the sample values per channel per pixel for the output buffer
  /// for pixels. This is not necessarily the same as the data type encoded in the
  /// codestream. The channels are interleaved per pixel. The pixels are
  /// organized row by row, left to right, top to bottom.
  /// TODO(lode): support different channel orders if needed (RGB, BGR, ...)
  pub const PixelFormat = extern struct {
    /// Amount of channels available in a pixel buffer.
    /// 1: single-channel data, e.g. grayscale or a single extra channel
    /// 2: single-channel + alpha
    /// 3: trichromatic, e.g. RGB
    /// 4: trichromatic + alpha
    /// TODO(lode): this needs finetuning. It is not yet defined how the user
    /// chooses output color space. CMYK+alpha needs 5 channels.
    num_channels: u32,

    /// Data type of each channel.
    data_type: DataType,

    /// Whether multi-byte data types are represented in big endian or little
    /// endian format. This applies to ::JXL_TYPE_UINT16 and ::JXL_TYPE_FLOAT.
    endianness: Endianness,

    /// Align scanlines to a multiple of align bytes, or 0 to require no
    /// alignment at all (which has the same effect as value 1)
    @"align": usize,

    test {
      const T = c.JxlPixelFormat;
      std.debug.assert(@sizeOf(@This()) == @sizeOf(T));
      inline for (@typeInfo(T).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(@This(), f.name) == @bitOffsetOf(T, cf.name));
      }
    }

    /// Data type for the sample values per channel per pixel.
    pub const DataType = enum(c.JxlDataType) {
      /// Use 32-bit single-precision floating point values, with range 0.0-1.0
      /// (within gamut, may go outside this range for wide color gamut). Floating
      /// point output, either ::JXL_TYPE_FLOAT or ::JXL_TYPE_FLOAT16, is recommended
      /// for HDR and wide gamut images when color profile conversion is required.
      float = @bitCast(c.JXL_TYPE_FLOAT),

      /// Use type uint8_t. May clip wide color gamut data.
      uint8 = @bitCast(c.JXL_TYPE_UINT8),

      /// Use type uint16_t. May clip wide color gamut data.
      uint16 = @bitCast(c.JXL_TYPE_UINT16),

      /// Use 16-bit IEEE 754 half-precision floating point values
      float16 = @bitCast(c.JXL_TYPE_FLOAT16),
    };

    /// Ordering of multi-byte data.
    pub const Endianness = enum(c.JxlEndianness) {
      /// Use the endianness of the system, either little endian or big endian,
      /// without forcing either specific endianness. Do not use if pixel data
      /// should be exported to a well defined format.
      native = @bitCast(c.JXL_NATIVE_ENDIAN),
      /// Force little endian
      little = @bitCast(c.JXL_LITTLE_ENDIAN),
      /// Force big endian
      big = @bitCast(c.JXL_BIG_ENDIAN),
    };
  };

  /// Data type for describing the interpretation of the input and output buffers
  /// in terms of the range of allowed input and output pixel values.
  pub const BitDepth = extern struct {
    /// Bit depth setting, see comment on @ref JxlBitDepthType
    type: @This().Type,

    /// Custom bits per sample
    bits_per_sample: u32,

    /// Custom exponent bits per sample
    exponent_bits_per_sample: u32,

    test {
      const T = c.JxlBitDepth;
      std.debug.assert(@sizeOf(@This()) == @sizeOf(T));
      inline for (@typeInfo(T).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(@This(), f.name) == @bitOffsetOf(T, cf.name));
      }
    }

    /// Settings for the interpretation of UINT input and output buffers.
    /// (buffers using a FLOAT data type are not affected by this)
    pub const Type = enum(c.JxlBitDepthType) {
      /// This is the default setting, where the encoder expects the input pixels
      /// to use the full range of the pixel format data type (e.g. for UINT16, the
      /// input range is 0 .. 65535 and the value 65535 is mapped to 1.0 when
      /// converting to float), and the decoder uses the full range to output
      /// pixels. If the bit depth in the basic info is different from this, the
      /// encoder expects the values to be rescaled accordingly (e.g. multiplied by
      /// 65535/4095 for a 12-bit image using UINT16 input data type).
      from_pixel_format = @bitCast(c.JXL_BIT_DEPTH_FROM_PIXEL_FORMAT),

      /// If this setting is selected, the encoder expects the input pixels to be
      /// in the range defined by the bits_per_sample value of the basic info (e.g.
      /// for 12-bit images using UINT16 input data types, the allowed range is
      /// 0 .. 4095 and the value 4095 is mapped to 1.0 when converting to float),
      /// and the decoder outputs pixels in this range.
      from_codestream = @bitCast(c.JXL_BIT_DEPTH_FROM_CODESTREAM),

      /// This setting can only be used in the decoder to select a custom range for pixel output
      custom = @bitCast(c.JXL_BIT_DEPTH_CUSTOM),
    };
  };
};

pub const version = struct {
  pub const major: u8 = @intCast(c.JPEGXL_MAJOR_VERSION);
  pub const minor: u8 = @intCast(c.JPEGXL_MINOR_VERSION);
  pub const patch: u8 = @intCast(c.JPEGXL_PATCH_VERSION);
  pub const numeric: c_int = c.JPEGXL_COMPUTE_NUMERIC_VERSION(@as(c_uint, major), @as(c_uint, minor), @as(c_uint, patch));
};


const testing = std.testing;
const jxl = @This();

fn ArgsTuple(comptime Function: type) ?type {
  @setEvalBranchQuota(1000_000);
  const info = @typeInfo(Function);
  if (info != .@"fn") @compileError("ArgsTuple expects a function type");

  const function_info = info.@"fn";
  if (function_info.is_var_args) return null;

  var argument_field_list: [function_info.params.len]type = undefined;
  inline for (function_info.params, 0..) |arg, i| {
    const T = arg.type orelse return null;
    if (T == type or @typeInfo(T) == .@"fn") return null;
    argument_field_list[i] = T;
  }

  var tuple_fields: [argument_field_list.len]std.builtin.Type.StructField = undefined;
  inline for (argument_field_list, 0..) |T, i| {
    @setEvalBranchQuota(10_000);
    var num_buf: [128]u8 = undefined;
    tuple_fields[i] = .{
      .name = std.fmt.bufPrintZ(&num_buf, "{d}", .{i}) catch unreachable,
      .type = T,
      .default_value_ptr = null,
      .is_comptime = false,
      .alignment = @alignOf(T),
    };
  }

  return @Type(.{
    .@"struct" = .{
      .is_tuple = true,
      .layout = .auto,
      .decls = &.{},
      .fields = &tuple_fields,
    },
  });
}

fn initType(comptime T: type) T {
  @setEvalBranchQuota(1000_000);
  comptime var retval: T = undefined;
  switch (@typeInfo(T)) {
    .type => return void,
    .void => return undefined,
    .bool => return false,
    .noreturn => unreachable,
    .int => return 0,
    .float => return 0.0,
    .pointer => return @alignCast(@ptrCast(@constCast(&.{}))),
    .array => |ai| inline for (0..ai.len) |i| {retval[i] = initType(ai.child);},
    .@"struct" => |si| inline for (si.fields) |field| {@field(retval, field.name) = comptime initType(@FieldType(T, field.name));},
    .comptime_float => return 0.0,
    .comptime_int => return 0,
    .undefined => unreachable,
    .null, .optional => return null,
    .error_union => |eu| return initType(eu.payload),
    .error_set => |es_| if (es_) |es| {
      if (es.len == 0) return undefined;
      return @field(T, es[0].name);
    } else error.AnyError,
    .@"enum" => |ei| if (ei.fields.len != 0) {retval = @field(T, ei.fields[0].name);} else return undefined,
    .@"union" => |ui| if (ui.fields.len != 0) {retval = @unionInit(T, ui.fields[0].name, initType(ui.fields[0].type));},
    .@"fn" => return undefined,
    .@"opaque", .frame, .@"anyframe" => unreachable,
    .vector => |vi| inline for (vi.len) |i| {@field(retval, i) = initType(vi.child);},
    .enum_literal => return undefined,
  }
  return retval;
}

/// If we use std.testing.refAllDeclsRecursive, we get a compile error because c has untranslatable code, hence we use this
/// Even this touches the translated parts of the c code that we touch, but atleast not it doesn't crash
fn refAllDeclsRecursiveExcerptC(comptime T: type) void {
  if (!@import("builtin").is_test) return;

  inline for (comptime std.meta.declarations(T)) |decl| {
    const field = @field(T, decl.name); 

    if (@TypeOf(field) == type) {
      if (decl.name.len == 1 and decl.name[0] == 'c') continue;
      switch (@typeInfo(@field(T, decl.name))) {
        .@"struct", .@"enum", .@"union", .@"opaque" => refAllDeclsRecursiveExcerptC(@field(T, decl.name)),
        else => {},
      }
      _ = &field;
    } else if (@typeInfo(@TypeOf(field)) == .@"fn") {
      var should_run: bool = false;
      _ = &should_run;
      if (should_run) {
        if (ArgsTuple(@TypeOf(field))) |Args| {
          _ = &@call(.auto, field, comptime initType(Args));
        } else comptime {
          // const name = std.fmt.comptimePrint("{s}.{s}", .{@typeName(T), decl.name});
          // if (skipFunctions.get(name)) @compileError(std.fmt.comptimePrint("Skipping {s}: {s}\n", .{name, @typeName(@TypeOf(field))}));
          // if (!skipFunctions.get(name)) @compileError(std.fmt.comptimePrint("Can't call {s}: {s}\n", .{name, @typeName(@TypeOf(field))}));
        }
      }
    }
  }
}

test {
  refAllDeclsRecursiveExcerptC(@This());
}

/// HashMap implementation used internally while parsing.
/// This is used for key replacement (${...})
/// This is a barebones implementation, it uses 8 bits for the fingerprint
/// unlike the 7 in zig's standard hashmap because we don't require toombstones
///
/// I chose to use write this instead of using the standard hashmap because
/// the standard implementation does not work at comptime, and has toombstones
/// which are not needed for this use case. We would need to use a context variant
/// of the hash map to prevent a new allocation for each value and it would result
/// in same amount of bloat more or less. Besides, this implementation should be
/// slightly faster (hopefully;) and works at comptime as well. Also, converting
/// the standard to ComptimeEnvType / EnvType would need rehashing which this
/// implementation does not need.
fn HashMap(is_const: bool) type {
  return struct {
    const Size = u32;
    pub const String = []const u8;
    pub const KV = struct { key: []const u8 };
    const default_max_load_percentage = 64;

    // This is the start of our allocated block
    keys: if (is_const) []const ?String else []?String = &.{},
    // These will be at the end of our allocated block, 0 means unused.
    meta: if (is_const) []const u8 else []u8 = &.{},
    /// Length for our keys, values, and meta arrays
    cap: Size = 0,
    // How many elements are in use
    size: Size = 0,
    // How many elements are available, this is used to reduce the number of instructions needed for the grow check
    available: Size = 0,

    pub fn initSlice(keys: []const []const u8) HashMap(true) {
      var self = @This().init(keys.len * default_max_load_percentage / 100 + 1);
      for (keys) |key| self.put(key);
      return self.toConst();
    }

    pub fn init(cap_: Size) @This() {
      @setEvalBranchQuota(1000_000);
      const cap = std.math.ceilPowerOfTwo(Size, cap_) catch 16;
      return .{
        .keys = blk: { var keys = [_]?String{null} ** cap; break :blk &keys; },
        .meta = blk: { var meta = [_]u8{0} ** cap; break :blk &meta; },
        .cap = cap,
        .available = c * default_max_load_percentage / 100,
      };
    }

    fn getHFP(key: []const u8) std.meta.Tuple(&.{u64, u8}) {
      const h = std.hash_map.StringContext.hash(undefined, key);
      const fp: u8 = @intCast(h >> 56);
      return .{h, fp};
    }

    fn eqlString(string: String, other: []const u8) bool {
      return std.mem.eql(u8, string.ptr[0..string.len], other);
    }

    fn getIndex(self: *const @This(), fingerprint: u8, hash: u64, key: []const u8) usize {
      var i: usize = @intCast(hash & (self.cap - 1));
      while (self.keys[i] != null) : (i = (i + 1) & (self.cap - 1)) {
        if (self.meta[i] == fingerprint and eqlString(self.keys[i].?, key)) break;
      }
      return i;
    }

    pub fn get(self: *const @This(), key: []const u8) bool {
      @setEvalBranchQuota(1000_000);
      const hash, const fingerprint = getHFP(key);
      const i = self.getIndex(fingerprint, hash, key);
      return self.keys[i] != null;
    }

    pub fn put(self: *@This(), key: []const u8) void {
      @setEvalBranchQuota(1000_000);
      self.grow();

      const hash, const fingerprint = getHFP(key);
      const i = self.getIndex(fingerprint, hash, key);
      if (self.keys[i] == null) {
        self.meta[i] = fingerprint;
        self.keys[i] = key;
        self.size += 1;
        self.available -= 1;
      }
    }

    fn grow(old: *@This()) void {
      @setEvalBranchQuota(1000_000);
      if (old.available > old.size) return;
      var self = @This().init(if (old.size == 0) 16 else old.size * 2);
      self.size = old.size;

      for (old.meta, old.keys) |m, k| {
        if (k == null) continue;
        const hash, _ = getHFP(k.?);
        var i: usize = @intCast(hash & (self.cap - 1));
        while (self.keys[i] != null) : (i = (i + 1) & (self.cap - 1)) {}
        self.meta[i] = m;
        self.keys[i] = k;
      }

      old.* = self;
    }

    pub fn toConst(self: *const @This()) HashMap(true) {
      if (is_const) return self.*;
      const keys: [self.keys.len]?String = self.keys[0..self.keys.len].*;
      const meta: [self.meta.len]u8 = self.meta[0..self.meta.len].*;
      return .{
        .keys = &keys,
        .meta = &meta,
        .cap = self.cap,
        .size = self.size,
        .available = self.available,
      };
    }
  };
}

/// These function are called somewhere in the tests
/// TODO: make this better; could mpve this to test runner to make it cleaner
const skipFunctions = HashMap(false).initSlice(&[_][]const u8{
});

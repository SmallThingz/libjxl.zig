const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
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

pub const Cms = struct {
  /// Represents an input or output colorspace to a color transform, as a
  /// serialized ICC profile.
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
          std.debug.assert(@bitOffsetOf(cf.type, cf.name) == @bitOffsetOf(f.type, f.name));
        }
      }
    };

    test {
      std.debug.assert(@sizeOf(@This()) == @sizeOf(c.JxlColorProfile));
      inline for (@typeInfo(c.JxlColorProfile).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(cf.type, cf.name) == @bitOffsetOf(f.type, f.name));
      }
    }
  };

  /// Interface for performing colorspace transforms. The @c init function can be
  /// called several times to instantiate several transforms, including before
  /// other transforms have been destroyed.
  pub const Interface = extern struct {
    /// CMS-specific data that will be passed to @ref set_fields_from_icc.
    set_fields_data: ?*anyopaque,
    /// Populates a @ref JxlColorEncoding from an ICC profile.
    set_fields_from_icc: SetFieldsFromIccFn,

    /// CMS-specific data that will be passed to @ref init.
    init_data: ?*anyopaque,
    /// Prepares a colorspace transform as described in the documentation of @ref
    /// jpegxl_cms_init_func.
    init: InitFn,
    /// Returns a buffer that can be used as input to @c run.
    get_src_buf: GetBufferFn,
    /// Returns a buffer that can be used as output from @c run.
    get_dst_buf: GetBufferFn,
    /// Executes the transform on a batch of pixels, per @ref jpegxl_cms_run_func.
    run: RunFn,
    /// Cleans up the transform.
    destroy: DestroyFn,

    test {
      std.debug.assert(@sizeOf(@This()) == @sizeOf(c.JxlCmsInterface));
      inline for (@typeInfo(c.JxlCmsInterface).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(cf.type, cf.name) == @bitOffsetOf(f.type, f.name));
      }
    }

    /// CMS interface function to parse an ICC profile and populate @p c and @p cmyk with the data.
    pub const SetFieldsFromIccFn = *const fn (user_data: ?*anyopaque, icc_data: ?[*]const u8, icc_size: usize, c: ?*ColorEncoding, cmyk: ?*c.JXL_BOOL) callconv(.c) c.JXL_BOOL;

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
    pub fn getDefault() ?*const @This() {
      return @ptrCast(c.JxlGetDefaultCms());
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
    reserved0 = @bitCast(c.JXL_CHANNEL_RESERVED0),
    reserved1 = @bitCast(c.JXL_CHANNEL_RESERVED1),
    reserved2 = @bitCast(c.JXL_CHANNEL_RESERVED2),
    reserved3 = @bitCast(c.JXL_CHANNEL_RESERVED3),
    reserved4 = @bitCast(c.JXL_CHANNEL_RESERVED4),
    reserved5 = @bitCast(c.JXL_CHANNEL_RESERVED5),
    reserved6 = @bitCast(c.JXL_CHANNEL_RESERVED6),
    reserved7 = @bitCast(c.JXL_CHANNEL_RESERVED7),
    unknown = @bitCast(c.JXL_CHANNEL_UNKNOWN),
    optional = @bitCast(c.JXL_CHANNEL_OPTIONAL),
  };

  /// The codestream preview header
  pub const PreviewHeader = extern struct {
    /// Preview width in pixels
    xsize: u32,
    /// Preview height in pixels
    ysize: u32,

    test {
      std.debug.assert(@sizeOf(@This()) == @sizeOf(c.JxlPreviewHeader));
      inline for (@typeInfo(c.JxlPreviewHeader).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(cf.type, cf.name) == @bitOffsetOf(f.type, f.name));
      }
    }
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
      std.debug.assert(@sizeOf(@This()) == @sizeOf(c.JxlAnimationHeader));
      inline for (@typeInfo(c.JxlAnimationHeader).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(cf.type, cf.name) == @bitOffsetOf(f.type, f.name));
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
      std.debug.assert(@sizeOf(@This()) == @sizeOf(c.JxlBasicInfo));
      inline for (@typeInfo(c.JxlBasicInfo).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(cf.type, cf.name) == @bitOffsetOf(f.type, f.name));
      }
    }
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
      std.debug.assert(@sizeOf(@This()) == @sizeOf(c.JxlExtraChannelInfo));
      inline for (@typeInfo(c.JxlExtraChannelInfo).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(cf.type, cf.name) == @bitOffsetOf(f.type, f.name));
      }
    }
  };

  /// Extensions in the codestream header.
  pub const HeaderExtensions = extern struct {
    /// Extension bits.
    extensions: u64,

    test {
      std.debug.assert(@sizeOf(@This()) == @sizeOf(c.JxlHeaderExtensions));
      inline for (@typeInfo(c.JxlHeaderExtensions).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(cf.type, cf.name) == @bitOffsetOf(f.type, f.name));
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
      std.debug.assert(@sizeOf(@This()) == @sizeOf(c.JxlBlendInfo));
      inline for (@typeInfo(c.JxlBlendInfo).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(cf.type, cf.name) == @bitOffsetOf(f.type, f.name));
      }
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
      std.debug.assert(@sizeOf(@This()) == @sizeOf(c.JxlLayerInfo));
      inline for (@typeInfo(c.JxlLayerInfo).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(cf.type, cf.name) == @bitOffsetOf(f.type, f.name));
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
      std.debug.assert(@sizeOf(@This()) == @sizeOf(c.JxlFrameHeader));
      inline for (@typeInfo(c.JxlFrameHeader).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(cf.type, cf.name) == @bitOffsetOf(f.type, f.name));
      }
    }
  };
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
    std.debug.assert(@sizeOf(@This()) == @sizeOf(c.JxlColorEncoding));
    inline for (@typeInfo(c.JxlColorEncoding).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
      std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
      std.debug.assert(@bitOffsetOf(cf.type, cf.name) == @bitOffsetOf(f.type, f.name));
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
};

pub const ICC = struct {
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
};

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
pub const GainMapBundle = extern struct {
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
    std.debug.assert(@sizeOf(@This()) == @sizeOf(c.JxlGainMapBundle));
    inline for (@typeInfo(c.JxlGainMapBundle).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
      std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
      std.debug.assert(@bitOffsetOf(cf.type, cf.name) == @bitOffsetOf(f.type, f.name));
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
};

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
    std.debug.assert(@sizeOf(@This()) == @sizeOf(c.JxlMemoryManager));
    inline for (@typeInfo(c.JxlMemoryManager).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
      std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
      std.debug.assert(@bitOffsetOf(cf.type, cf.name) == @bitOffsetOf(f.type, f.name));
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

  pub fn _alloc(self: *const @This(), size: usize) ![]u8 {
    return @as([*]u8, @ptrCast(self._alloc_fn(self._ctx, size) orelse return error.OutOfMemory))[0 .. size];
  }

  pub fn alloc(self: *const @This(), comptime T: type, count: usize) ![]T {
    std.debug.assert(@alignOf(T) <= 16);
    const mem = try _alloc(self, @sizeOf(T) * count);
    return @as([*]T, @ptrCast(@alignCast(mem.ptr)))[0..count];
  }

  pub fn free(self: *const @This(), ptr: ?[*]u8) void {
    self._free_fn(self._ctx, @ptrCast(ptr));
  }
};

pub const ParallelRunner = opaque {
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

    pub fn check(self: @This()) !void {
      return switch (self) {
        .success => {},
        .@"error" => error.ParallelExecutionError,
        else => error.InvalidParallelRetCode
      };
    }

    pub fn checkInt(int: c.JxlParallelRetCode) !void {
      return @as(@This(), @enumFromInt(int)).check();
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
  pub const ParallelRunner = ?*const fn (
    runner_opaque: ?*anyopaque,
    jpegxl_opaque: ?*anyopaque,
    init: RunContext.InitFn,
    func: RunContext.RunFn,
    start_range: u32,
    end_range: u32,
  ) callconv(.c) RetCode;

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
    pub const InitFn = *const fn (jpegxl_opaque: ?*anyopaque, num_threads: usize) callconv(.c) RetCode;

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
    pub fn run(self: *@This(), ctx: RunContext, range: RunRange) RetCode {
      return RetCode.checkInt(c.JxlResizableParallelRunner(@ptrCast(self), ctx.ctx, ctx.init_fn, ctx.run_fn, range.from, range.to));
    }

    /// Changes the number of threads for @ref JxlResizableParallelRunner.
    pub fn setThreads(self: *@This(), num_threads: usize) void {
      c.JxlResizableParallelRunnerSetThreads(@ptrCast(self), num_threads);
    }

    /// Suggests a number of threads to use for an image of given size.
    pub fn suggestThreads(xsize: u64, ysize: u64) u32 {
      return c.JxlResizableParallelRunnerSuggestThreads(xsize, ysize);
    }
  };

  pub const Threaded = opaque {
    /// Creates the runner for @ref JxlThreadParallelRunner. Use as the opaque runner.
    pub fn init(memory_manager: ?*const MemoryManager, num_worker_threads: usize) ?*@This() {
      return @ptrCast(c.JxlThreadParallelRunnerCreate(@ptrCast(memory_manager), num_worker_threads));
    }

    /// Parallel runner internally using std::thread. Use as @ref JxlParallelRunner.
    pub fn run(self: *@This(), ctx: RunContext, range: RunRange) !void {
      return RetCode.checkInt(c.JxlThreadParallelRunner(@ptrCast(self), ctx.ctx, ctx.init_fn, ctx.run_fn, range.from, range.to));
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
  };
};

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
      std.debug.assert(@sizeOf(@This()) == @sizeOf(c.JxlPixelFormat));
      inline for (@typeInfo(c.JxlPixelFormat).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(cf.type, cf.name) == @bitOffsetOf(f.type, f.name));
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
      std.debug.assert(@sizeOf(@This()) == @sizeOf(c.JxlBitDepth));
      inline for (@typeInfo(c.JxlBitDepth).@"struct".fields, @typeInfo(@This()).@"struct".fields) |cf, f| {
        std.debug.assert(@sizeOf(cf.type) == @sizeOf(f.type));
        std.debug.assert(@bitOffsetOf(cf.type, cf.name) == @bitOffsetOf(f.type, f.name));
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

      /// This setting can only be used in the decoder to select a custom range for
      /// pixel output
      custom = @bitCast(c.JXL_BIT_DEPTH_CUSTOM),
    };
  };

  /// Data type holding the 4-character type name of an ISOBMFF box.
  pub const BoxType = [4]u8;
};

pub const version = struct {
  pub const major: u8 = @intCast(c.JPEGXL_MAJOR_VERSION);
  pub const minor: u8 = @intCast(c.JPEGXL_MINOR_VERSION);
  pub const patch: u8 = @intCast(c.JPEGXL_PATCH_VERSION);
  pub const numeric: c_int = c.JPEGXL_COMPUTE_NUMERIC_VERSION(major, minor, patch);
};

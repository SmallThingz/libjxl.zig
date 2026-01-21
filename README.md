# libjxl-zig

An idiomatic Zig wrapper for [libjxl](https://github.com/libjxl/libjxl) (JPEG XL).

This library provides a type-safe, "Ziggy" interface to the JPEG XL reference implementation, featuring zero-cost abstractions and support for static linking.

> [!IMPORTANT]  
> **Development Status:** Tested on linux onty, if any bugs arise on other platforms, please open an issue, or better yet, a PR.

## ✨ Features

* **Type-Safe Callbacks:** Move away from `void*` nightmare. Use `fromContext` to pass Zig structs directly into decoder/CMS callbacks with full type safety.
* **Struct Layout Verification:** Uses tests to verify that Zig struct layouts perfectly match the underlying C library headers.
* **Flexible CMS:** Built-in support for linking `skcms` or `lcms2`, or providing your own implementation via a clean interface.

## 📦 Installation

Add this to your `build.zig.zon`:

```zig
.{
  .dependencies = .{
    .jxl = .{
      .url = "https://github.com/SmallThingz/libjxl.zig/archive/<commit-hash>.tar.gz",
      .hash = "...",
    },
  },
}

```

## 🚀 Quick Start: Decoding

```zig
const jxl = @import("jxl");

pub fn main() !void {
  // Initialize global defaults (BasicInfo, BlendInfo, etc.)
  try jxl.init(.{}); // Deinitialization not needed

  const decoder = jxl.Decoder.create(null);
  defer decoder.destroy();

  // Set up a custom pixel handler
  const MyHandler = struct {
    pub fn onImageOut(self: *@This(), x: usize, y: usize, num: usize, pixels: ?*const anyopaque) void {
      // Process pixels...
    }
  };

  var handler = MyHandler{};
  const listener = jxl.ImageOutListener.fromContext(&handler);
  
  _ = decoder.setImageOutCallback(&format, listener);
  
  // Feed data and process...
}

```

## 🛠 Build Configuration

The wrapper supports several build-time options to satisfy `libjxl` dependencies without system-wide installs.

| Option | Values | Description |
| --- | --- | --- |
| **`static_jxl`** | `bool` (default: `true`) | Build `libjxl` from source (static). If `false`, links to system libs. |
| **`cms`** | `skcms`, `lcms2` | Choose the Color Management System. |
| **`threading`** | `bool` (default: `true`) | Enable multi-threading support. |
| **`boxes`** | `bool` (default: `true`) | Enable JXL container format (ISOBMFF "boxes"). |
| **`jpeg_transcode`** | `bool` (default: `true`) | Enable lossless JPEG to JXL transcoding. |
| **`3d_icc_tonemapping`** | `bool` (default: `true`) | Enable 3D ICC tonemapping for HDR-to-SDR conversion. |
| **`icc`** | `bool` | Enable support for ICC profiles. |
| **`gain_map`** | `bool` | Enable support for HDR gain maps. |
| **`include_paths`** | `[]const []const u8` | Custom header search paths for system linking. |
| **`r_paths`** | `[]const []const u8` | Custom runtime library search paths for system linking. |

*These options specifically affect the C/C++ library compilation.*
| Option | Values | Description |
| --- | --- | --- |
| **`lib_strip`** | `bool` | Strip symbols from the library binary. |
| **`lib_unwind_tables`** | `none`, `sync`, `async` | Control stack unwind table generation. |
| **`lib_stack_protector`** | `bool` | Enable stack smashing protection. |
| **`lib_stack_check`** | `bool` | Enable stack limit checking. |
| **`lib_red_zone`** | `bool` (default: `true`) | Enable the "red zone" optimization. |
| **`lib_omit_frame_pointer`** | `bool` (default: `true`) | Omit the frame pointer for a performance boost. |
| **`lib_error_tracing`** | `bool` | Enable internal error tracing (useful for debugging). |

---

**Would you like me to show you how to set up the `build.zig.zon` file so Zig can automatically download the `libjxl` and `highway` dependencies?**


## 🧩 Advanced: Custom CMS Interface

You can satisfy the JPEG XL requirements with a custom Zig struct by implementing the `Cms.Interface`.

```zig
const MyCMS = struct {
  pub fn init(self: *@This(), num_threads: usize, max_pixels: usize) ?*anyopaque { 
    return self; 
  }
  pub fn run(self: *@This(), ...) bool { 
    return true; 
  }
};

const interface = jxl.Cms.Interface.fromContext(&my_cms_instance);
decoder.setCms(interface);

```

## ⚠️ Important Notes

* **Initialization:** You **must** call `jxl.init({})` before accessing `.default()` methods on configuration structs, as these are populated from the C library at runtime.

## Contributing

Contributions are welcome! Feel free to open a bug report or a Pull Request. Just keep the following in mind:
- **Indentation**: 2 spaces.

## License

This project is licensed under the MIT License. Reference the ONNX Runtime license for the underlying C library.

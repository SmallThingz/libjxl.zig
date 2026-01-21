const std = @import("std");
const builtin = @import("builtin");
const jxl = @import("jxl");
const testing = std.testing;

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
    _ = &field;

    if (@TypeOf(field) == type) {
      if (decl.name.len == 1 and decl.name[0] == 'c') continue;
      switch (@typeInfo(@field(T, decl.name))) {
        .@"struct", .@"enum", .@"union", .@"opaque" => refAllDeclsRecursiveExcerptC(@field(T, decl.name)),
        else => {},
      }
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
  refAllDeclsRecursiveExcerptC(jxl);
  testing.refAllDeclsRecursive(@This());
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

    pub fn init(cap: Size) @This() {
      @setEvalBranchQuota(1000_000);
      const c = std.math.ceilPowerOfTwo(Size, cap) catch 16;
      return .{
        .keys = blk: { var keys = [_]?String{null} ** c; break :blk &keys; },
        .meta = blk: { var meta = [_]u8{0} ** c; break :blk &meta; },
        .cap = c,
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
      var self = init(if (old.size == 0) 16 else old.size * 2);
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

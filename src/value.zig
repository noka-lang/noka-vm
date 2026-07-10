const io = @import("io.zig");

// TODO: for now every value is an f64. The spec ("Values and Types") wants
// nil, booleans, strings, and heap objects. Turn this into a tagged union,
// e.g.
//     pub const Value = union(enum) { nil, boolean: bool, number: f64, obj: *Obj };
// and update the VM's arithmetic ops to type-check their operands.
pub const Value = f64;

// TODO: Will need to switch on the union tag once `Value` grows.
pub fn printValue(value: Value) void {
    io.printf("{d}", .{value});
}

/// ST: ssz element type
/// ZT: zig type
pub fn withElementTypes(comptime ST: type, comptime ZT: type) type {
    const Array = struct {
        pub fn valueEquals(element_type: *ST, a: []const ZT, b: []const ZT) bool {
            if (a.len != b.len) {
                return false;
            }

            for (a, b) |*a_elem, *b_elem| {
                if (!element_type.equals(a_elem, b_elem)) {
                    return false;
                }
            }

            return true;
        }

        pub fn valueClone(element_type: *ST, value: []const ZT, out: []ZT) !void {
            for (value, out) |*elem, *out_elem| {
                try element_type.clone(elem, out_elem);
            }
        }
    };

    return Array;
}

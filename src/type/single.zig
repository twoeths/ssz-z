const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const AllocatorError = Allocator.Error;
const Scanner = std.json.Scanner;
const Parsed = @import("./type.zig").Parsed;
const JsonError = @import("./common.zig").JsonError;
const SszError = @import("./common.zig").SszError;

pub fn withType(comptime ZT: type) type {
    const ParsedResult = Parsed(ZT);
    // if ZT is a slice, we don't want to use pointer for it
    const CloneType = switch (@typeInfo(ZT)) {
        .Pointer => |ptrInfo| switch (ptrInfo.size) {
            .Slice => []const ptrInfo.child,
            // TODO: handle .One
            else => *const ZT,
        },
        else => *const ZT,
    };

    return struct {
        pub fn fromSsz(self: anytype, ssz: []const u8) SszError!ParsedResult {
            const arena = try self.allocator.create(ArenaAllocator);
            arena.* = ArenaAllocator.init(self.allocator);
            const allocator = arena.allocator();

            // must destroy before deinit()
            errdefer self.allocator.destroy(arena);
            errdefer arena.deinit();

            const value = try self.deserializeFromSlice(allocator, ssz, null);
            return .{
                .arena = arena,
                .value = value,
            };
        }

        pub fn fromJson(self: anytype, json: []const u8) JsonError!ParsedResult {
            const arena = try self.allocator.create(ArenaAllocator);
            arena.* = ArenaAllocator.init(self.allocator);
            const allocator = arena.allocator();

            // must destroy before deinit()
            errdefer self.allocator.destroy(arena);
            errdefer arena.deinit();

            var source = Scanner.initCompleteInput(allocator, json);
            defer source.deinit();
            const zt = try self.deserializeFromJson(allocator, &source, null);
            const end_document_token = try source.next();
            switch (end_document_token) {
                .end_of_document => {},
                else => return error.InvalidJson,
            }

            return .{
                .arena = arena,
                .value = zt,
            };
        }

        pub fn clone(self: anytype, value: CloneType) !ParsedResult {
            const arena = try self.allocator.create(ArenaAllocator);
            arena.* = ArenaAllocator.init(self.allocator);
            const allocator = arena.allocator();

            // must destroy before deinit()
            errdefer self.allocator.destroy(arena);
            errdefer arena.deinit();

            const cloned = try self.doClone(allocator, value, null);
            return .{
                .arena = arena,
                .value = cloned,
            };
        }
    };
}

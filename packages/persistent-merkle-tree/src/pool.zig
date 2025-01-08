const std = @import("std");
const expect = std.testing.expect;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
// node module
const nm = @import("./node.zig");
const Node = nm.Node;
const BranchNode = nm.BranchNode;
const LeafNode = nm.LeafNode;
const MAX_NODES_DEPTH = @import("./const.zig").MAX_NODES_DEPTH;
const zh = @import("./zero_hash.zig");

const LeafList = ArrayList(*Node);
const BranchList = ArrayList(*Node);
pub const NodePool = struct {
    leaf_nodes: LeafList,
    branch_nodes: BranchList,
    zero_list: []*Node,
    // no need to call destroyNode() on this
    place_holder: *Node,
    arena: *ArenaAllocator,
    allocator: Allocator,
    // these variables are useful for metrics and tests
    branch_node_count: usize,
    leaf_node_count: usize,

    pub fn init(allocator: Allocator, capacity: usize) !NodePool {
        const arena = try allocator.create(ArenaAllocator);
        arena.* = ArenaAllocator.init(allocator);
        const arena_allocator = arena.allocator();
        const place_holder = try nm.initLeafNode(arena_allocator, &[_]u8{0} ** 32);
        const zero_list = try arena_allocator.alloc(*Node, MAX_NODES_DEPTH);
        try zh.initZeroHash(&arena_allocator, MAX_NODES_DEPTH);
        for (0..MAX_NODES_DEPTH) |i| {
            zero_list[i] = try nm.initZeroNode(arena_allocator, try zh.getZeroHash(i));
        }
        return NodePool{
            .leaf_nodes = try LeafList.initCapacity(arena_allocator, capacity),
            .branch_nodes = try BranchList.initCapacity(arena_allocator, capacity),
            .zero_list = zero_list,
            .place_holder = place_holder,
            .arena = arena,
            .allocator = allocator,
            .branch_node_count = 0,
            .leaf_node_count = 0,
        };
    }

    pub fn deinit(self: *NodePool) void {
        self.leaf_nodes.deinit();
        self.branch_nodes.deinit();
        self.arena.deinit();
        self.allocator.destroy(self.arena);
    }

    pub fn newLeaf(self: *NodePool, hash: *const [32]u8) !*Node {
        const nodeOrNull = self.leaf_nodes.popOrNull();
        if (nodeOrNull) |node| {
            // reuse LeafNode from pool
            switch (node.*) {
                .Leaf => |leaf| {
                    @memcpy(leaf.hash.*[0..], hash.*[0..]);
                    nm.setRefCount(node, 0);
                    return node;
                },
                else => unreachable,
            }
        }

        // create new
        const node = try nm.initLeafNode(self.arena.allocator(), hash);
        self.leaf_node_count += 1;
        return node;
    }

    /// cannot make left and right as const since we may modify its ref_count
    pub fn newBranch(self: *NodePool, left: *Node, right: *Node) !*Node {
        const nodeOrNull = self.branch_nodes.popOrNull();
        if (nodeOrNull) |node| {
            // reuse BranchNode from pool
            switch (node.*) {
                .Branch => {
                    const branch = &node.Branch;
                    branch.hash_computed = false;
                    branch.left = left;
                    branch.right = right;
                    nm.incRefCount(left);
                    nm.incRefCount(right);
                    nm.setRefCount(node, 0);
                    return node;
                },
                else => unreachable,
            }
        }

        // create new
        const node = try nm.initBranchNode(self.arena.allocator(), left, right);
        self.branch_node_count += 1;
        return node;
    }

    pub fn getZeroNode(self: *const NodePool, depth: usize) !*Node {
        if (depth >= MAX_NODES_DEPTH) {
            return error.OutOfBounds;
        }
        return self.zero_list[depth];
    }

    pub fn destroyNode(self: *NodePool, node: *Node) !void {
        switch (node.*) {
            .Leaf => {
                const leaf = &node.Leaf;
                leaf.decRefCount();
                if (leaf.ref_count == 0) {
                    try self.leaf_nodes.append(node);
                    @memset(leaf.hash.*[0..], 0);
                }
            },
            .Branch => {
                const branch = &node.Branch;
                branch.decRefCount();
                if (branch.ref_count == 0) {
                    try self.destroyNode(branch.left);
                    try self.destroyNode(branch.right);
                    try self.branch_nodes.append(node);
                    @memset(branch.hash.*[0..], 0);
                    branch.left = self.place_holder;
                    branch.right = self.place_holder;
                    branch.hash_computed = false;
                }
            },
            .Zero => {}, // the pool will destroy it in the end
        }
    }
};

test "recreate the same tree" {
    const allocator = std.testing.allocator;
    var pool = try NodePool.init(allocator, 10);
    defer pool.deinit();

    const hash1: [32]u8 = [_]u8{1} ** 32;
    const hash2: [32]u8 = [_]u8{2} ** 32;
    const hash3: [32]u8 = [_]u8{3} ** 32;
    const hash4: [32]u8 = [_]u8{4} ** 32;

    // tree 1 is a full tree created from 4 leaves
    var leaf1 = try pool.newLeaf(&hash1);
    var leaf2 = try pool.newLeaf(&hash2);
    var leaf3 = try pool.newLeaf(&hash3);
    var leaf4 = try pool.newLeaf(&hash4);

    var branch1 = try pool.newBranch(leaf1, leaf2);
    var branch2 = try pool.newBranch(leaf3, leaf4);

    var rootNode = try pool.newBranch(branch1, branch2);
    var expected_root = [_]u8{0} ** 32;
    const root = nm.getRoot(rootNode);
    @memcpy(expected_root[0..], root.*[0..]);

    // tree 2 is a clone of tree 1 with different root
    var rootNode2 = try pool.newBranch(branch1, branch2);

    // destroy tree1, only rootNode is released to pool
    try pool.destroyNode(rootNode);
    try expect(pool.leaf_nodes.items.len == 0);
    try expect(pool.branch_nodes.items.len == 1);
    try expect(pool.leaf_node_count == 4);
    try expect(pool.branch_node_count == 4);

    // also destroy tree 2, all nodes are released to pool
    try pool.destroyNode(rootNode2);
    try expect(pool.leaf_nodes.items.len == 4);
    try expect(pool.branch_nodes.items.len == 4);
    try expect(pool.leaf_node_count == 4);
    try expect(pool.branch_node_count == 4);

    // recreate the same tree
    leaf1 = try pool.newLeaf(&hash1);
    leaf2 = try pool.newLeaf(&hash2);
    leaf3 = try pool.newLeaf(&hash3);
    leaf4 = try pool.newLeaf(&hash4);

    branch1 = try pool.newBranch(leaf1, leaf2);
    branch2 = try pool.newBranch(leaf3, leaf4);

    rootNode = try pool.newBranch(branch1, branch2);

    // only rootNode2 is in the pool
    try expect(pool.leaf_nodes.items.len == 0);
    try expect(pool.branch_nodes.items.len == 1);

    rootNode2 = try pool.newBranch(branch1, branch2);
    // should have no more nodes in pool
    try expect(pool.leaf_nodes.items.len == 0);
    try expect(pool.branch_nodes.items.len == 0);

    // no new nodes created
    try expect(pool.leaf_node_count == 4);
    try expect(pool.branch_node_count == 4);

    // hash should be the same
    const new_root = nm.getRoot(rootNode);
    try std.testing.expectEqualSlices(u8, expected_root[0..], new_root.*[0..]);
}

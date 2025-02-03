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
const Tree = @import("./tree.zig").Tree;

const LeafList = ArrayList(*Node);
const BranchList = ArrayList(*Node);

/// Nodes are created by the pool and reused to minimize memory allocations. When a node is no longer needed, you should call the `unref()` method, which decreases the node's reference count.
/// - Reference Counting: Each node tracks its usage with a reference count. When the count reaches zero, the node is returned to the pool.
/// - Reusability: Returned nodes are stored in the pool's LeafList and BranchList, making them available for reuse. This significantly reduces the need for frequent memory allocation during the application's lifetime.
/// - Memory Allocation: A single allocator is managed within the pool, simplifying memory management across the API. When trees are no longer in use, nodes should be returned to the pool via the `unref()` method. The pool will then handle cleanup and deallocate memory when required.
///
/// This design ensures efficient memory usage and optimal performance, especially in applications where nodes are frequently created and discarded.
pub const NodePool = struct {
    leaf_nodes: LeafList,
    branch_nodes: BranchList,
    zero_list: []*Node,
    // no need to call destroyNode() on this
    place_holder: *Node,
    allocator: Allocator,
    // these variables are useful for metrics and tests
    branch_node_count: usize,
    leaf_node_count: usize,

    pub fn init(allocator: Allocator, capacity: usize) !NodePool {
        const place_holder = try nm.initLeafNode(allocator, &[_]u8{0} ** 32);
        const zero_list = try allocator.alloc(*Node, MAX_NODES_DEPTH);
        try zh.initZeroHash(&allocator, MAX_NODES_DEPTH);
        // TODO: somehow put this in deinit() causes segmentation fault
        defer zh.deinitZeroHash();
        for (0..MAX_NODES_DEPTH) |i| {
            const prev_zero = if (i == 0) null else zero_list[i - 1];
            zero_list[i] = try nm.initZeroNode(allocator, try zh.getZeroHash(i), prev_zero, prev_zero);
        }
        return NodePool{
            .leaf_nodes = try LeafList.initCapacity(allocator, capacity),
            .branch_nodes = try BranchList.initCapacity(allocator, capacity),
            .zero_list = zero_list,
            .place_holder = place_holder,
            .allocator = allocator,
            .branch_node_count = 0,
            .leaf_node_count = 0,
        };
    }

    pub fn deinit(self: *NodePool) void {
        for (self.leaf_nodes.items) |node| {
            nm.destroyNode(self.allocator, node);
        }
        self.leaf_nodes.deinit();

        for (self.branch_nodes.items) |node| {
            nm.destroyNode(self.allocator, node);
        }
        self.branch_nodes.deinit();

        for (self.zero_list) |node| {
            nm.destroyNode(self.allocator, node);
        }

        self.allocator.free(self.zero_list);

        nm.destroyNode(self.allocator, self.place_holder);
    }

    /// get tree from root node
    pub fn getTree(self: *NodePool, root: *Node) Tree {
        return Tree{ ._root_node = root, .pool = self, .parent = null };
    }

    /// create new leaf node, if there is any in the pool, reuse it
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
        const node = try nm.initLeafNode(self.allocator, hash);
        self.leaf_node_count += 1;
        return node;
    }

    /// New LeafNode with its internal value set to zero. Consider using `zeroNode(0)` if you don't need to mutate.
    pub fn newZeroLeaf(self: *NodePool) !*Node {
        const zero_hash = [_]u8{0} ** 32;
        return self.newLeaf(&zero_hash);
    }

    /// LeafNode with 8 uint32 `(uint32, 0, 0, 0, 0, 0, 0, 0)`.
    pub fn newUint32Leaf(self: *NodePool, value: u32) !*Node {
        const hash = [_]u8{0} ** 32;
        const slice = std.mem.bytesAsSlice(u32, hash[0..]);
        slice[0] = value;
        return self.newLeaf(&hash);
    }

    /// create new branch node, if there is any in the pool, reuse it
    /// cannot make left and right as const since we may modify its ref_count
    pub fn newBranch(self: *NodePool, left: *Node, right: *Node) nm.NodeError!*Node {
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
        const node = try nm.initBranchNode(self.allocator, left, right);
        self.branch_node_count += 1;
        return node;
    }

    /// get zero node at depth
    pub fn getZeroNode(self: *const NodePool, depth: usize) !*Node {
        if (depth >= MAX_NODES_DEPTH) {
            return error.OutOfBounds;
        }
        return self.zero_list[depth];
    }

    /// decrease ref_count of node, if ref_count is 0, put it back to pool
    pub fn unref(self: *NodePool, node: *Node) Allocator.Error!void {
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
                    try self.unref(branch.left);
                    try self.unref(branch.right);
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
    try pool.unref(rootNode);
    try expect(pool.leaf_nodes.items.len == 0);
    try expect(pool.branch_nodes.items.len == 1);
    try expect(pool.leaf_node_count == 4);
    try expect(pool.branch_node_count == 4);

    // also destroy tree 2, all nodes are released to pool
    try pool.unref(rootNode2);
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

    // cleanup
    try pool.unref(rootNode);
    try pool.unref(rootNode2);
}

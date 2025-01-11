const std = @import("std");
const expect = std.testing.expect;
const nm = @import("./node.zig");
const Node = nm.Node;
const NodePool = @import("./pool.zig").NodePool;
const MAX_NODES_DEPTH = @import("./const.zig").MAX_NODES_DEPTH;
const util = @import("./util.zig");
const toRootHex = @import("util").toRootHex;

/// Binary merkle tree
/// Wrapper around immutable `Node` to support mutability.
pub const Tree = struct {
    pool: *NodePool,
    root_node: *Node,

    pub fn getRoot(self: *const Tree) *const [32]u8 {
        return nm.getRoot(self.root_node);
    }

    pub fn clone(self: *const Tree) Tree {
        return .{
            .pool = self.pool,
            .root_node = self.root_node,
        };
    }

    pub fn setTreeNode(self: *Tree, gindex: u64, node: *Node) !void {
        const old_root = self.root_node;
        self.root_node = try setNode(self.pool, old_root, gindex, node);
        // return the old root node to the pool if possible
        try self.pool.unref(old_root);
    }

    pub fn unref(self: *Tree) !void {
        try self.pool.unref(self.root_node);
    }
};

// TODO: HashComputation
/// Set multiple nodes in batch, editing and traversing nodes strictly once.
/// - gindexes MUST be sorted in ascending order beforehand.
/// - All gindexes must be at the exact same depth.
/// - Depth must be > 0, if 0 just replace the root node.
///
/// Strategy: for each gindex in `gindexes` navigate to the depth of its parent,
/// and create a new parent. Then calculate the closest common depth with the next
/// gindex and navigate upwards creating or caching nodes as necessary. Loop and repeat.
///
/// Supports index up to `Number.MAX_SAFE_INTEGER`.
/// cannot make nodes as const because we may modify ref_count
pub fn setNodesAtDepth(pool: *NodePool, root_node: *const Node, nodes_depth: usize, indexes: []usize, nodes: []*Node) !*Node {
    if (nodes_depth > MAX_NODES_DEPTH) {
        return error.InvalidDepth;
    }

    // depth depthi   gindexes   indexes
    // 0     1           1          0
    // 1     0         2   3      0   1
    // 2     -        4 5 6 7    0 1 2 3
    // '10' means, at depth 1, node is at the left
    //
    // For index N check if the bit at position depthi is set to navigate right at depthi
    // ```
    // mask = 1 << depthi
    // goRight = (N & mask) == mask
    // ```

    // If depth is 0 there's only one node max and the optimization below will cause a navigation error.
    // For this case, check if there's a new root node and return it, otherwise the current rootNode.
    if (nodes_depth == 0) {
        const node: *Node = @constCast(if (nodes.len > 0) nodes[0] else root_node);
        return node;
    }

    // Contiguous filled stack of parent nodes. It get filled in the first descent
    // Indexed by depthi
    var parent_nodes_stack = [_]*Node{@constCast(root_node)} ** MAX_NODES_DEPTH;

    // Temp stack of left parent nodes, index by depthi.
    // Node leftParentNodeStack[depthi] is a node at d = depthi - 1, such that:
    // ```
    // parentNodeStack[depthi].left = leftParentNodeStack[depthi]
    // ```
    var left_parent_node_stack = [_]?*Node{null} ** MAX_NODES_DEPTH;

    // Ignore first bit "1", then substract 1 to get to the parent
    const depth_i_root: usize = nodes_depth - 1;
    const depth_i_parent = 0;
    var depth_i = depth_i_root;
    var node: *Node = @constCast(root_node);

    // Insert root node to make the loop below general
    // parent_nodes_stack[depth_i_root] = node;

    var i: usize = 0;
    while (i < indexes.len) : (i += 1) {
        const index: usize = indexes[i];

        // Navigate down until parent depth, and store the chain of nodes
        //
        // Starts from latest common depth, so node is the parent node at `depthi`
        // When persisting the next node, store at the `d - 1` since its the child of node at `depthi`
        //
        // Stops at the level above depthiParent. For the re-binding routing below node must be at depthiParent
        var d: usize = depth_i;
        while (d > depth_i_parent) : (d -= 1) {
            node = if (isLeftNode(d, index)) try nm.getLeft(node) else try nm.getRight(node);
            parent_nodes_stack[d - 1] = node;
        }

        depth_i = depth_i_parent;

        // If this is the left node, check first it the next node is on the right
        //
        //   -    If both nodes exist, create new
        //  / \
        // x   x
        //
        //   -    If only the left node exists, rebind left
        //  / \
        // x   -
        //
        //   -    If this is the right node, only the right node exists, rebind right
        //  / \
        // -   x

        // d = 0, mask = 1 << d = 1
        const is_left_leaf_node = (index & 1) != 1;
        if (is_left_leaf_node) {
            // Next node is the very next to the right of current node
            if (index + 1 == indexes[i + 1]) {
                node = try pool.newBranch(nodes[i], nodes[i + 1]);
                // Move pointer one extra forward since node has consumed two nodes
                i += 1;
            } else {
                const old_node = node;
                node = try pool.newBranch(nodes[i], try nm.getRight(old_node));
            }
        } else {
            const old_node = node;
            node = try pool.newBranch(try nm.getLeft(old_node), nodes[i]);
        }

        // Here `node` is the new BranchNode at depthi `depthiParent`

        // Now climb upwards until finding the common node with the next index
        // For the last iteration, climb to the root at `depthiRoot`
        const is_last_index = i >= indexes.len - 1;
        const diff_depth_i = if (is_last_index) depth_i_root else try findDiffDepthi(index, indexes[i + 1]);

        // When climbing up from a left node there are two possible paths
        // 1. Go to the right of the parent: Store left node to rebind latter
        // 2. Go another level up: Will never visit the left node again, so must rebind now

        // 🡼 \     Rebind left only, will never visit this node again
        // 🡽 /\
        //
        //    / 🡽  Rebind left only (same as above)
        // 🡽 /\
        //
        // 🡽 /\ 🡾  Store left node to rebind the entire node when returning
        //
        // 🡼 \     Rebind right with left if exists, will never visit this node again
        //   /\ 🡼
        //
        //    / 🡽  Rebind right with left if exists (same as above)
        //   /\ 🡼

        d = depth_i_parent + 1;
        while (d <= diff_depth_i) : (d += 1) {
            // If node is on the left, store for latter
            // If node is on the right merge with stored left node
            if (nodes_depth < d + 1) {
                return error.InvalidDepth;
            }
            if (isLeftNode(d, index)) {
                if (is_last_index or d != diff_depth_i) {
                    // If it's last index, bind with parent since it won't navigate to the right anymore
                    // Also, if still has to move upwards, rebind since the node won't be visited anymore
                    const old_node = node;
                    node = try pool.newBranch(old_node, try nm.getRight(parent_nodes_stack[d]));
                } else {
                    // Only store the left node if it's at d = diffDepth
                    left_parent_node_stack[d] = node;
                    node = parent_nodes_stack[d];
                }
            } else {
                const left_node_or_null = left_parent_node_stack[d];

                if (left_node_or_null) |left_node| {
                    const old_node = node;
                    node = try pool.newBranch(left_node, old_node);
                    left_parent_node_stack[d] = null;
                } else {
                    const old_node = node;
                    node = try pool.newBranch(try nm.getLeft(parent_nodes_stack[d]), old_node);
                }
            }
        }

        // Prepare next loop
        // Go to the parent of the depth with diff, to switch branches to the right
        depth_i = diff_depth_i;
    }

    // Done, return new root node
    return node;
}

pub fn setNode(pool: *NodePool, root_node: *Node, gindex: u64, n: *Node) !*Node {
    var all_bit_array = [_]bool{false} ** MAX_NODES_DEPTH;
    const num_bits = try util.populateBitArray(all_bit_array[0..gindex], gindex);
    var array_parent_nodes = [_]*Node{n} ** MAX_NODES_DEPTH;
    const parent_nodes = array_parent_nodes[0..num_bits];
    const bit_array = all_bit_array[0..num_bits];
    try getParentNodes(parent_nodes, root_node, bit_array);
    return try rebindNodeToRoot(pool, bit_array, parent_nodes, n);
}

///
/// depth depthi   gindexes   indexes
/// 0     1           1          0
/// 1     0         2   3      0   1
/// 2     -        4 5 6 7    0 1 2 3
/// **Conditions**:
/// - `from` and `to` must not be equal
pub fn findDiffDepthi(from: usize, to: usize) !usize {
    if (from == to) {
        return error.InvalidArgument;
    }

    // 0 -> 0, 1 -> 1, 2 -> 2, 3 -> 2, 4 -> 3
    const from_plus_one: f64 = @floatFromInt(from + 1);
    const to_plus_one: f64 = @floatFromInt(to + 1);
    const num_bits_0: usize = @intFromFloat(@ceil(@log2(from_plus_one)));
    const num_bits_1: usize = @intFromFloat(@ceil(@log2(to_plus_one)));

    // these indexes stay in 2 sides of a merkle tree
    if (num_bits_0 != num_bits_1) {
        // must offset by one to match the depthi scale
        return @max(num_bits_0, num_bits_1) - 1;
    }

    // same number of bits
    const xor = from ^ to;
    const tmp: f64 = @floatFromInt(xor + 1);
    const num_bits_diff: usize = @intFromFloat(@ceil(@log2(tmp)));
    return num_bits_diff - 1;
}

/// Returns true if the `index` at `depth` is a left node, false if it is a right node.
///
/// In Eth2 case the biggest tree's index is 2**40 (VALIDATOR_REGISTRY_LIMIT)
fn isLeftNode(depth_i: usize, index: usize) bool {
    // depth_i should fit u6, validated in setNodesAtDepth()
    const shift: u6 = @intCast(depth_i);
    const mask: usize = @as(usize, 1) << shift;
    return (index & mask) != mask;
}

/// Build a new tree structure from bitstring, parentNodes and a new node.
/// Returns the new root node.
fn rebindNodeToRoot(pool: *NodePool, bit_array: []bool, parent_nodes: []*Node, new_node: *Node) !*Node {
    var node = new_node;

    // Ignore the first bit, left right directions are at bits [1,..]
    // Iterate the list backwards including the last bit, but offset the parentNodes array
    // by one since the first bit in bitstring was ignored in the previous loop
    var i = bit_array.len - 1;
    while (i >= 1) : (i -= 1) {
        const is_right = bit_array[i];
        const parent_node = parent_nodes[i - 1];
        node = if (is_right) try pool.newBranch(try nm.getLeft(parent_node), node) else try pool.newBranch(node, try nm.getRight(parent_node));
    }

    return node;
}

/// Traverse the tree from root node, ignore the last bit to get all parent nodes
/// of the specified bitstring.
fn getParentNodes(out: []*Node, root_node: *Node, bit_array: []bool) !void {
    if (out.len != bit_array.len) {
        return error.InvalidArgument;
    }

    // Keep a list of all parent nodes of node at gindex `index`. Then walk the list
    // backwards to rebind them "recursively" with the new nodes without using functions
    out[0] = root_node;
    var node: *Node = root_node;
    // Ignore the first bit, left right directions are at bits [1,..]
    // Ignore the last bit, no need to push the target node to the parentNodes array
    for (bit_array[1..], 0..) |bit, i| {
        node = if (bit) try nm.getRight(node) else try nm.getLeft(node);
        out[i + 1] = node;
    }
}

// TODO: implement a Tree
// - getRoot
// - unref
// - clone
test "setNode" {
    const allocator = std.testing.allocator;
    var pool = try NodePool.init(allocator, 32);
    defer pool.deinit();

    // Should compute root correctly after setting a leaf
    {
        const depth = 4;
        const zero_node = try pool.getZeroNode(depth);
        const leaf_node = try pool.newLeaf(&[_]u8{2} ** 32);
        const root_node = try setNode(&pool, zero_node, 18, leaf_node);
        const root = nm.getRoot(root_node);
        const root_hex = try toRootHex(root[0..]);
        try pool.unref(root_node);
        try std.testing.expectEqualSlices(u8, "0x3cfd85690fdd88abcf22ca7acf45bb47835326ff3166d3c953d5a23263fea2b2", root_hex);
    }

    // Should compute root correctly after setting 3 leafs
    {
        const depth = 5;
        const zero_node = try pool.getZeroNode(depth);
        // var tree = Tree{ .pool = &pool, .root_node = zero_node };
        var tree = pool.getTree(zero_node);
        const leaf_node = try pool.newLeaf(&[_]u8{2} ** 32);
        try tree.setTreeNode(18, leaf_node);
        try tree.setTreeNode(46, leaf_node);
        try tree.setTreeNode(60, leaf_node);
        const root = tree.getRoot();
        const root_hex = try toRootHex(root[0..]);
        try tree.unref();
        try std.testing.expectEqualSlices(u8, "0x02607e58782c912e2f96f4ff9daf494d0d115e7c37e8c2b7ddce17213591151b", root_hex);
    }
}

test "findDiffDepthi" {
    const TestCase = struct {
        index0: usize,
        index1: usize,
        expected: usize,
    };

    const tcs = [_]TestCase{
        .{ .index0 = 0, .index1 = 1, .expected = 0 },
        // 2 sides of a 4-width tree
        .{ .index0 = 1, .index1 = 3, .expected = 1 },
        // 2 sides of a 8-width tree
        .{ .index0 = 3, .index1 = 4, .expected = 2 },
        // 16 bits
        .{ .index0 = 0, .index1 = 0xffff, .expected = 15 },
        // 31 bits, different number of bits
        .{ .index0 = 5, .index1 = (0xffffffff >> 1) - 5, .expected = 30 },
        // 31 bits, same number of bits
        .{ .index0 = 0x7fffffff, .index1 = 0x70000000, .expected = 27 },
        // 32 bits tree, different number of bits
        .{ .index0 = 0, .index1 = 0xffffffff, .expected = 31 },
        .{ .index0 = 0, .index1 = (0xffffffff >> 1) + 1, .expected = 31 },
        .{ .index0 = 0xffffffff >> 1, .index1 = (0xffffffff >> 1) + 1, .expected = 31 },
        // 32 bits tree, same number of bits
        .{ .index0 = 0xf0000000, .index1 = 0xffffffff, .expected = 27 },
        // below tests are same to first tests but go from right to left
        // similar to {0, 1}
        .{ .index0 = 0xffffffff - 1, .index1 = 0xffffffff, .expected = 0 },
        // similar to {1, 3}
        .{ .index0 = 0xffffffff - 3, .index1 = 0xffffffff - 1, .expected = 1 },
        // similar to {3, 4}
        .{ .index0 = 0xffffffff - 4, .index1 = 0xffffffff - 3, .expected = 2 },
        // more than 32 bits, same number of bits
        .{ .index0 = 1153210973487, .index1 = 1344787435182, .expected = 37 },
        // more than 32 bits, different number of bits
        .{ .index0 = 1153210973487, .index1 = 1344787435182 >> 2, .expected = 40 },
    };

    for (tcs) |tc| {
        const result = try findDiffDepthi(tc.index0, tc.index1);
        try expect(result == tc.expected);
    }
}

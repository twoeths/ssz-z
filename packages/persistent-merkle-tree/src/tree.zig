const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const nm = @import("./node.zig");
const Node = nm.Node;
const NodePool = @import("./pool.zig").NodePool;
const MAX_NODES_DEPTH = @import("./const.zig").MAX_NODES_DEPTH;
const util = @import("./util.zig");
const toRootHex = @import("util").toRootHex;
const rootIntoHex = @import("util").rootIntoHex;

pub const TreeError = nm.NodeError || error{ TooFewBits, InvalidArgument } || Allocator.Error;

/// callback information to ask the parent tree to update the root node
/// due to subtree's new root. This is equivalent to a hook in Typescript implementation.
const ParentTree = struct {
    tree: *Tree,
    // gindex of root node of the subtree in the parent tree
    gindex_in_parent: u64,
};

/// binary merkle tree
/// wrapper around immutable `Node` to support mutability.
/// no need to allocate/deallocate since nodes are managed by pool.
pub const Tree = struct {
    pool: *NodePool,
    // do not set this field directly, do it through setRootNode()
    // no const, this could be mutated if hash is not computed yet
    _root_node: *Node,
    parent: ?ParentTree,

    // TODO: createFromProof

    /// The root node of the tree
    pub fn getRootNode(self: *const Tree) *const Node {
        return self._root_node;
    }

    /// Setting the root node will trigger a call to the tree's `hook` if it exists.
    pub fn setRootNode(self: *Tree, new_node: *Node) !void {
        const old_root = self._root_node;
        self._root_node = new_node;
        // return the old root node to the pool if possible
        try self.pool.unref(old_root);

        // similar to a hook to the parent tree to update its root node
        if (self.parent) |parent| {
            try parent.tree.setTreeNode(parent.gindex_in_parent, new_node);
        }
    }

    /// The root hash of the tree
    pub fn getRoot(self: *const Tree) *const [32]u8 {
        return nm.getRoot(self._root_node);
    }

    /// Return a copy of the tree
    pub fn clone(self: *const Tree) Tree {
        return .{
            .pool = self.pool,
            .root_node = self._root_node,
        };
    }

    /// Return the subtree at the specified gindex.
    /// Note: The returned subtree will have a `hook` attached to the parent tree.
    /// Updates to the subtree will result in updates to the parent.
    pub fn getSubTree(self: *Tree, gindex: u64) !Tree {
        // this node is mutable because hash is not computed yet
        const node = try getNodeMut(self._root_node, gindex);
        return Tree{ .pool = self.pool, ._root_node = node, .parent = .{ .tree = self, .gindex_in_parent = gindex } };
    }

    /// Return the node at the specified gindex.
    pub fn getTreeNode(self: *const Tree, gindex: u64) !*Node {
        return try getNodeMut(self._root_node, gindex);
    }

    /// Return the node at the specified depth and index.
    /// Supports index up to `Number.MAX_SAFE_INTEGER`.
    pub fn getTreeNodeAtDepth(self: *const Tree, depth: usize, index: usize) !*Node {
        return getNodeAtDepth(self._root_node, depth, index);
    }

    /// Return the hash at the specified gindex.
    pub fn getRootOfNode(self: *const Tree, index: u64) !*[32]u8 {
        const node = try getNode(self._root_node, index);
        return nm.getRoot(node);
    }

    /// Set the node at at the specified gindex.
    pub fn setTreeNode(self: *Tree, gindex: u64, node: *Node) TreeError!void {
        const old_root = self._root_node;
        const new_root = try setNode(self.pool, old_root, gindex, node);
        try self.setRootNode(new_root);
    }

    /// Traverse to the node at the specified gindex,
    /// then apply the function to get a new node and set the node at the specified gindex with the result.
    ///
    /// This is a convenient method to avoid traversing the tree 2 times to
    /// get and set.
    pub fn setTreeNodeWithFn(self: *Tree, gindex: u64, getNewNode: fn (*Node) *Node) !void {
        const old_root = self._root_node;
        const new_root = try setNodeWithFn(self.pool, old_root, gindex, getNewNode);
        try self.setRootNode(new_root);
    }

    /// Set the node at the specified depth and index.
    /// Supports index up to `Number.MAX_SAFE_INTEGER`.
    pub fn setTreeNodeAtDepth(self: *Tree, depth: usize, index: usize, node: *Node) !void {
        const old_root = self._root_node;
        const new_root = try setNodeAtDepth(self.pool, old_root, depth, index, node);
        try self.setRootNode(new_root);
    }

    pub fn setTreeNodesAtDepth(self: *Tree, nodes_depth: usize, indexes: []usize, nodes: []*Node) !*Node {
        const old_root = self._root_node;
        const new_root = try setNodesAtDepth(self.pool, old_root, nodes_depth, indexes, nodes);
        try self.setRootNode(new_root);
        return new_root;
    }

    /// Set the hash at the specified gindex.
    /// Note: This will set a new `LeafNode` at the specified gindex.
    pub fn setRootOfNode(self: *Tree, index: u64, hash: *const [32]u8) !void {
        const left_node = try self.pool.newLeaf(hash);
        try self.setTreeNode(index, left_node);
    }

    /// Fast read-only iteration
    /// In-order traversal of nodes at `depth`
    /// starting from the `startIndex`-indexed node
    /// iterating through `count` nodes
    pub fn getTreeNodesAtDepth(self: *const Tree, depth: usize, start_index: usize, count: usize, out: []*Node) !usize {
        return getNodesAtDepth(self._root_node, depth, start_index, count, out);
    }

    // TODO: iterateNodesAtDepth() returns IterableIterator<Node> in typescript
    // find equivalent way in zig or just use getNodesAtDepth()

    // TODO: getSingleProof
    // TODO: getProof

    /// unreferece the root node to possibly return it to the pool
    pub fn unref(self: *Tree) !void {
        try self.pool.unref(self._root_node);
    }
};

pub fn getNode(root_node: *const Node, gindex: u64) !*const Node {
    return getNodeMut(root_node, gindex);
}

/// the same to getNode() but returns mutable node
pub fn getNodeMut(root_node: *const Node, gindex: u64) !*Node {
    var all_bit_array = [_]bool{false} ** MAX_NODES_DEPTH;
    const num_bits = try util.populateBitArray(all_bit_array[0..gindex], gindex);
    var node = @constCast(root_node);
    for (1..num_bits) |i| {
        node = if (all_bit_array[i]) try nm.getRightMut(node) else try nm.getLeftMut(node);
    }

    return node;
}

pub fn setNode(pool: *NodePool, root_node: *const Node, gindex: u64, n: *Node) TreeError!*Node {
    var all_bit_array = [_]bool{false} ** MAX_NODES_DEPTH;
    const num_bits = try util.populateBitArray(all_bit_array[0..], gindex);
    var array_parent_nodes = [_]*Node{n} ** MAX_NODES_DEPTH;
    const parent_nodes = array_parent_nodes[0..num_bits];
    const bit_array = all_bit_array[0..num_bits];
    try getParentNodes(parent_nodes, root_node, bit_array);
    return try rebindNodeToRoot(pool, bit_array, parent_nodes, n);
}

/// Traverse to the node at the specified gindex,
/// then apply the function to get a new node and set the node at the specified gindex with the result.
///
/// This is a convenient method to avoid traversing the tree 2 times to
/// get and set.
///
/// Returns the new root node.
pub fn setNodeWithFn(pool: *NodePool, root_node: *const Node, gindex: u64, getNewNode: fn (*Node) *Node) !*Node {
    // Pre-compute entire bitstring instead of using an iterator (25% faster)
    var all_bit_array = [_]bool{false} ** MAX_NODES_DEPTH;
    const num_bits = try util.populateBitArray(all_bit_array[0..gindex], gindex);
    var array_parent_nodes = [_]*Node{root_node} ** MAX_NODES_DEPTH;
    const parent_nodes = array_parent_nodes[0..num_bits];
    const bit_array = all_bit_array[0..num_bits];
    try getParentNodes(parent_nodes, root_node, bit_array);

    const last_parent_node = parent_nodes[parent_nodes.len - 1];
    const last_bit = bit_array[bit_array.len - 1];
    const old_node = if (last_bit) try nm.getRight(last_parent_node) else try nm.getLeft(last_parent_node);
    const new_node = getNewNode(old_node);

    return try rebindNodeToRoot(pool, bit_array, parent_nodes, new_node);
}

pub fn getNodeAtDepth(root_node: *const Node, depth: usize, index: usize) !*const Node {
    if (depth == 0) {
        return root_node;
    }

    if (depth == 1) {
        return if (index == 0) try nm.getLeft(root_node) else try nm.getRight(root_node);
    }

    // Ignore first bit "1", then substract 1 to get to the parent
    const depth_i_root: usize = depth - 1;
    const depth_i_parent: usize = 0;
    var node = root_node;

    var d = depth_i_root;
    while (d >= depth_i_parent) : (d -= 1) {
        node = if (isLeftNode(d, index)) try nm.getLeft(node) else try nm.getRight(node);
    }

    return node;
}

pub fn setNodeAtDepth(pool: *NodePool, root_node: *const Node, nodes_depth: usize, index: usize, node_changed: *Node) *Node {
    var indices = [_]usize{index};
    const nodes_changed = [_]*Node{node_changed};
    return try setNodesAtDepth(pool, root_node, nodes_depth, indices[0..], nodes_changed[0..]);
}

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
    var parent_nodes_stack = [_]?*Node{undefined} ** MAX_NODES_DEPTH;

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
    parent_nodes_stack[depth_i_root] = @constCast(root_node);

    errdefer {
        if (node != root_node) {
            // return the in-progress root to the pool
            // without this we'll lose access to in-progress nodes and leak memory
            pool.unref(node) catch {};
        }
    }

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
            node = if (isLeftNode(d, index)) try nm.getLeftMut(node) else try nm.getRightMut(node);
            parent_nodes_stack[d - 1] = @constCast(node);
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
            if ((i < indexes.len - 1) and index + 1 == indexes[i + 1]) {
                node = try pool.newBranch(nodes[i], nodes[i + 1]);
                // Move pointer one extra forward since node has consumed two nodes
                i += 1;
            } else {
                const old_node = node;
                node = try pool.newBranch(nodes[i], try nm.getRightMut(old_node));
            }
        } else {
            const old_node = node;
            node = try pool.newBranch(try nm.getLeftMut(old_node), nodes[i]);
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
                const node_d = parent_nodes_stack[d] orelse return error.IncorrectParentNode;
                if (is_last_index or d != diff_depth_i) {
                    // If it's last index, bind with parent since it won't navigate to the right anymore
                    // Also, if still has to move upwards, rebind since the node won't be visited anymore
                    const old_node = node;
                    node = try pool.newBranch(old_node, try nm.getRightMut(node_d));
                } else {
                    // Only store the left node if it's at d = diffDepth
                    left_parent_node_stack[d] = node;
                    node = node_d;
                }
            } else {
                const left_node_or_null = left_parent_node_stack[d];

                if (left_node_or_null) |left_node| {
                    const old_node = node;
                    node = try pool.newBranch(left_node, old_node);
                    left_parent_node_stack[d] = null;
                } else {
                    const old_node = node;
                    const node_d = parent_nodes_stack[d] orelse return error.IncorrectParentNode;
                    node = try pool.newBranch(try nm.getLeftMut(node_d), old_node);
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

/// Fast read-only iteration
/// In-order traversal of nodes at `depth`
/// starting from the `startIndex`-indexed node
/// iterating through `count` nodes
/// return number of returned nodes
///
/// **Strategy**
/// 1. Navigate down to parentDepth storing a stack of parents
/// 2. At target level push current node
/// 3. Go up to the first level that navigated left
/// 4. Repeat (1) for next index
pub fn getNodesAtDepth(root_node: *const Node, depth: usize, start_index: usize, count: usize, out: []*const Node) !usize {
    // Optimized paths for short trees (x20 times faster)
    if (depth == 0) {
        if (start_index == 0 and count > 0) {
            if (out.len == 0) {
                return error.Out_Nodes_Too_Small;
            }
            out[0] = @constCast(root_node);
            return 1;
        } else {
            return 0;
        }
    } else if (depth == 1) {
        if (count == 0) {
            return 0;
        } else if (count == 1) {
            if (out.len == 0) {
                return error.Out_Nodes_Too_Small;
            }
            out[0] = if (start_index == 0) try nm.getLeft(root_node) else try nm.getRight(root_node);
            return 1;
        } else {
            // 2 nodes
            if (out.len < 2) {
                return error.Out_Nodes_Too_Small;
            }
            out[0] = try nm.getLeft(root_node);
            out[1] = try nm.getRight(root_node);
            return 2;
        }
    }

    // Ignore first bit "1", then substract 1 to get to the parent
    const depthi_root: usize = depth - 1;
    const depthi_parent: usize = 0;
    var depthi = depthi_root;
    var node: *const Node = root_node;

    // Contiguous filled stack of parent nodes. It get filled in the first descent
    // Indexed by depthi
    var parent_nodes_stack = [_]?*const Node{undefined} ** MAX_NODES_DEPTH;
    var is_left_stack = [_]bool{false} ** MAX_NODES_DEPTH;

    // Insert root node to make the loop below general
    parent_nodes_stack[depthi_root] = @constCast(root_node);

    for (0..count) |i| {
        var d = depthi;
        while (d >= depthi_parent) : (d -= 1) {
            if (d != depthi) {
                parent_nodes_stack[d] = node;
            }

            const is_left = isLeftNode(d, start_index + i);

            is_left_stack[d] = is_left;
            node = if (is_left) try nm.getLeft(node) else try nm.getRight(node);

            // avoid integer overflow
            if (d == 0) {
                break;
            }
        }

        out[i] = node;

        // Find the first depth where navigation when left.
        // Store that height and go right from there
        for (depthi_parent..(depthi_root + 1)) |d2| {
            if (is_left_stack[d2]) {
                depthi = d2;
                break;
            }
        }

        if (parent_nodes_stack[depthi]) |node_depth_i| {
            node = node_depth_i;
        } else {
            return error.IncorrectParentNode;
        }
    }

    return count;
}

/// TODO: iterateNodesAtDepth() returns IterableIterator<Node> in typescript
/// find equivalent way in zig or just use getNodesAtDepth()
///
///
///Zero's all nodes right of index with constant depth of `nodesDepth`.
///For example, zero-ing this tree at depth 2 after index 0
///```
///   X              X
/// X   X    ->    X   0
///X X X X        X 0 0 0
///```
///Or, zero-ing this tree at depth 3 after index 2
///```
///       X                     X
///   X       X             X       0
/// X   X   X   X    ->   X   X   0   0
///X X X X X X X X       X X X 0 0 0 0 0
///```
///The strategy is to first navigate down to `nodesDepth` and `index` and keep a stack of parents.
///Then navigate up re-binding:
///- If navigated to the left rebind with zeroNode()
///- If navigated to the right rebind with parent.left from the stack
pub fn treeZeroAfterIndex(pool: *NodePool, root_node: *const Node, nodes_depth: usize, index: usize) !*Node {
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

    // Degenerate case where tree is zero after a negative index (-1).
    // All positive indexes are zero, so the entire tree is zero. Return cached zero node as root.
    // in Zig this never happens
    // if (index < 0) {
    //     return zeroNode(nodesDepth);
    // }

    // Contiguous filled stack of parent nodes. It get filled in the first descent
    // Indexed by depthi
    var parent_nodes_stack = [_]?*Node{undefined} ** MAX_NODES_DEPTH;

    // Ignore first bit "1", then substract 1 to get to the parent
    const depthi_root = nodes_depth - 1;
    const depthi_parent = 0;
    var depthi = depthi_root;
    var node = root_node;

    // Insert root node to make the loop below general
    parent_nodes_stack[depthi_root] = root_node;

    // Navigate down until parent depth, and store the chain of nodes
    //
    // Stops at the depthiParent level. To rebind below down to `nodesDepth`
    var d = depthi;
    while (d >= depthi_parent) : (d -= 1) {
        node = if (isLeftNode(d, index)) try nm.getLeft(node) else try nm.getRight(node);
        parent_nodes_stack[d - 1] = node;
    }

    depthi = depthi_parent;

    // Now climb up re-binding with either zero of existing tree.

    for (depthi_parent..(depthi_root + 1)) |d2| {
        if (isLeftNode(d2, index)) {
            // If navigated to the left, then all the child nodes of the right node are NOT part of the new tree.
            // So re-bind new `node` with a zeroNode at the current depth.
            node = try pool.newBranch(node, try pool.getZeroNode(d2));
        } else {
            // If navigated to the right, then all the child nodes of the left node are part of the new tree.
            // So re-bind new `node` with the existing left node of the parent.
            const node_d2 = parent_nodes_stack[d2] orelse return error.IncorrectParentNode;
            node = try pool.newBranch(try nm.getLeft(node_d2), node);
        }
    }

    // Done, return new root node
    return node;
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
fn rebindNodeToRoot(pool: *NodePool, bit_array: []bool, parent_nodes: []*Node, new_node: *Node) nm.NodeError!*Node {
    var node = new_node;

    // Ignore the first bit, left right directions are at bits [1,..]
    // Iterate the list backwards including the last bit, but offset the parentNodes array
    // by one since the first bit in bitstring was ignored in the previous loop
    var i = bit_array.len - 1;
    while (i >= 1) : (i -= 1) {
        const is_right = bit_array[i];
        const parent_node = parent_nodes[i - 1];
        node = if (is_right) try pool.newBranch(try nm.getLeftMut(parent_node), node) else try pool.newBranch(node, try nm.getRightMut(parent_node));
    }

    return node;
}

/// Traverse the tree from root node, ignore the last bit to get all parent nodes
/// of the specified bitstring.
fn getParentNodes(out: []*const Node, root_node: *const Node, bit_array: []bool) TreeError!void {
    if (out.len != bit_array.len) {
        return error.InvalidArgument;
    }

    // Keep a list of all parent nodes of node at gindex `index`. Then walk the list
    // backwards to rebind them "recursively" with the new nodes without using functions
    out[0] = root_node;
    var node: *const Node = root_node;
    // Ignore the first bit, left right directions are at bits [1,..]
    // Ignore the last bit, no need to push the target node to the parentNodes array
    for (bit_array[1..], 0..) |bit, i| {
        node = if (bit) try nm.getRight(node) else try nm.getLeft(node);
        out[i + 1] = node;
    }
}

test "should properly navigate the zero tree" {
    const allocator = std.testing.allocator;
    var pool = try NodePool.init(allocator, 32);
    defer pool.deinit();
    const depth = 4;
    const zero_node = try pool.getZeroNode(0);
    const zero_root = nm.getRoot(zero_node);
    const zero_node_depth = try pool.getZeroNode(depth);
    const tree = pool.getTree(zero_node_depth);

    var nodes_arr = [_]*Node{zero_node} ** depth;
    const nodes = nodes_arr[0..];

    const count = try tree.getTreeNodesAtDepth(depth, 0, depth, nodes);

    try expect(count == 4);
    for (nodes) |node| {
        const root = nm.getRoot(node);
        try std.testing.expectEqualSlices(u8, zero_root.*[0..], root.*[0..]);
    }
}

// should properly navigate a custom tree

// batchHash() vs root getter

test "subtree mutation - changing a subtree should change the parent root" {
    const allocator = std.testing.allocator;
    var pool = try NodePool.init(allocator, 32);
    defer pool.deinit();
    const depth = 2;
    const zero_node = try pool.getZeroNode(depth);
    var tree = pool.getTree(zero_node);
    // clean up
    defer {
        tree.unref() catch {};
    }

    // Get the subtree with "X"s
    //       0
    //      /  \
    //    0      X
    //   / \    / \
    //  0   0  X   X

    var sub_tree = try tree.getSubTree(3);
    const new_root = [_]u8{1} ** 32;
    const root_before = tree.getRoot();
    try sub_tree.setRootOfNode(3, &new_root);
    const root_after = tree.getRoot();
    // expectEqualSlices should be false, usually the 1st u8 changed
    try expect(root_before.*[0] != root_after.*[0]);
}

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
        defer {
            tree.unref() catch {};
        }

        const leaf_node = try pool.newLeaf(&[_]u8{2} ** 32);
        try tree.setTreeNode(18, leaf_node);
        try tree.setTreeNode(46, leaf_node);
        try tree.setTreeNode(60, leaf_node);
        const root = tree.getRoot();
        const root_hex = try toRootHex(root[0..]);
        try std.testing.expectEqualSlices(u8, "0x02607e58782c912e2f96f4ff9daf494d0d115e7c37e8c2b7ddce17213591151b", root_hex);
    }
}

test "Tree batch setNodes" {
    const TestCase = struct {
        depth: usize,
        gindexes: []const u64,
    };

    const tcs = [_]TestCase{
        .{ .depth = 1, .gindexes = &.{2} },
        .{ .depth = 1, .gindexes = &.{ 2, 3 } },
        .{ .depth = 2, .gindexes = &.{4} },
        .{ .depth = 2, .gindexes = &.{6} },
        .{ .depth = 2, .gindexes = &.{ 4, 6 } },
        .{ .depth = 3, .gindexes = &.{9} },
        .{ .depth = 3, .gindexes = &.{12} },
        .{ .depth = 3, .gindexes = &.{ 9, 10 } },
        .{ .depth = 3, .gindexes = &.{ 13, 14 } },
        .{ .depth = 3, .gindexes = &.{ 13, 14 } },
        .{ .depth = 3, .gindexes = &.{ 9, 10, 13, 14 } },
        .{ .depth = 3, .gindexes = &.{ 8, 9, 10, 11, 12, 13, 14, 15 } },
        .{ .depth = 4, .gindexes = &.{16} },
        .{ .depth = 4, .gindexes = &.{ 16, 17 } },
        .{ .depth = 4, .gindexes = &.{ 16, 17 } },
        .{ .depth = 4, .gindexes = &.{ 16, 20 } },
        .{ .depth = 4, .gindexes = &.{ 16, 20, 30 } },
        .{ .depth = 4, .gindexes = &.{ 16, 20, 30, 31 } },
        .{ .depth = 5, .gindexes = &.{33} },
        .{ .depth = 5, .gindexes = &.{34} },
        .{ .depth = 10, .gindexes = &.{ 1024, 1061, 1098, 1135, 1172, 1209, 1246, 1283 } },
        // .{.depth = 40, .gindexes = &.{std.math.pow(u64, 2, 40) + 1000, std.math.pow(u64, 2, 40) + 1_000_000, std.math.pow(u64, 2, 40) + 1_000_000_000}}
        // Math.pow(2, 40) = 1099511627776
        .{ .depth = 40, .gindexes = &.{ 1099511627776 + 1000, 1099511627776 + 1_000_000, 1099511627776 + 1_000_000_000 } },
        .{ .depth = 40, .gindexes = &.{ 1157505940782, 1349082402477, 1759777921993 } },
    };

    const allocator = std.testing.allocator;
    var pool = try NodePool.init(allocator, 32);
    defer pool.deinit();

    inline for (tcs[0..]) |tc| {
        const depth = tc.depth;
        const gindexes = tc.gindexes;

        // Prepare tree
        var tree_ok = pool.getTree(try pool.getZeroNode(depth));
        // cache all roots
        _ = tree_ok.getRoot();
        var tree = pool.getTree(try pool.getZeroNode(depth));
        _ = tree.getRoot();

        defer {
            // clean up
            tree_ok.unref() catch {};
            tree.unref() catch {};
        }

        const index0 = std.math.pow(u64, 2, depth);
        var indices = [_]usize{0} ** gindexes.len;
        for (gindexes, 0..) |gindex, i| {
            indices[i] = @intCast(gindex - index0);
        }

        // we can reuse the nodes but want to do the same to typescript's test here
        var nodes_ok: [gindexes.len]*Node = undefined;
        var nodes: [gindexes.len]*Node = undefined;
        for (gindexes, 0..) |gindex, i| {
            var root = [_]u8{@intCast(gindex % 256)} ** 32;
            nodes_ok[i] = try pool.newLeaf(&root);
            nodes[i] = try pool.newLeaf(&root);
            try tree_ok.setTreeNode(gindex, nodes_ok[i]);
        }

        // For the large test cases, only compare the rootNode root (gindex 1)
        const max_gindex = comptime if (depth > 6) 1 else std.math.pow(u64, 2, (depth + 1));
        var hexes_ok: [max_gindex - 1][66]u8 = undefined;
        _ = try _getTreeRoots(&tree_ok, max_gindex, hexes_ok[0..]);

        _ = try tree.setTreeNodesAtDepth(depth, indices[0..], nodes[0..]);

        for (1..max_gindex) |i| {
            const node = try tree.getTreeNode(i);
            const root = nm.getRoot(node);
            var hex = [_]u8{0} ** 66;
            try rootIntoHex(hex[0..], root);
            try std.testing.expectEqualSlices(u8, hexes_ok[i - 1][0..], hex[0..]);
        }
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

/// test util
/// extract root hexes from tree
fn _getTreeRoots(tree: *const Tree, max_gindex: u64, out: [][66]u8) !void {
    if (out.len != max_gindex - 1) {
        return error.InvalidArgument;
    }

    for (1..max_gindex) |i| {
        const node = try tree.getTreeNode(i);
        const root = nm.getRoot(node);
        try rootIntoHex(out[i - 1][0..], root);
    }
}

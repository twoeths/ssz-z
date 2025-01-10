const std = @import("std");
const Allocator = std.mem.Allocator;
const digest64Into = @import("./sha256.zig").digest64Into;

pub const NodeType = enum {
    Branch,
    Leaf,
    Zero,
};

pub const Node = union(NodeType) {
    Branch: BranchNode,
    Leaf: LeafNode,
    Zero: ZeroNode,
};

pub const BranchNode = struct {
    // cannot use const here because it's designed to be reused
    hash: *[32]u8,
    hash_computed: bool,
    left: *Node,
    right: *Node,
    ref_count: usize,

    // called and managed by NodePool
    pub fn init(allocator: Allocator, left: *Node, right: *Node) !*BranchNode {
        const branch = try allocator.create(BranchNode);
        branch.hash = try allocator.create([32]u8);
        branch.left = left;
        branch.right = right;
        branch.hash_computed = false;
        branch.ref_count = 0;
        incRefCount(left);
        incRefCount(right);
        return branch;
    }

    // NodePool will deinit in batch

    pub fn root(self: *BranchNode) *const [32]u8 {
        if (self.hash_computed == true) {
            return self.hash;
        }
        // TODO: change digest64Into() to accept *[32]u8
        digest64Into(getRoot(self.left).*[0..], getRoot(self.right).*[0..], self.hash);
        self.hash_computed = true;
        return self.hash;
    }

    pub fn decRefCount(node: *BranchNode) void {
        // TODO: extract to a util?
        if (node.ref_count > 0) {
            node.ref_count -= 1;
            return;
        }
        node.ref_count = 0;
    }
};

pub const LeafNode = struct {
    // cannot use const here because it's designed to be reused
    hash: *[32]u8,
    ref_count: usize,

    // called and managed by NodePool
    pub fn init(allocator: Allocator, hash: *const [32]u8) !*LeafNode {
        const leaf = try allocator.create(LeafNode);
        leaf.hash = try allocator.create([32]u8);
        @memcpy(leaf.hash.*[0..], hash.*[0..]);
        leaf.ref_count = 0;
        return leaf;
    }

    // NodePool will deinit in batch

    pub fn root(self: *LeafNode) *const [32]u8 {
        return self.hash;
    }

    pub fn decRefCount(node: *LeafNode) void {
        // TODO: extract to a util?
        if (node.ref_count > 0) {
            node.ref_count -= 1;
            return;
        }
        node.ref_count = 0;
    }
};

/// if level 0, it's a leaf node without ref count
/// from level 1, it's the BranchNode with no ref count
pub const ZeroNode = struct {
    hash: *[32]u8,
    // these are ZeroNode but want to conform to get* function signature
    left: ?*Node,
    right: ?*Node,

    // called and managed by NodePool
    pub fn init(allocator: Allocator, zero_hash: *const [32]u8, left: ?*Node, right: ?*Node) !*ZeroNode {
        const zero = try allocator.create(ZeroNode);
        zero.hash = try allocator.create([32]u8);
        @memcpy(zero.hash.*[0..], zero_hash.*[0..]);
        zero.left = left;
        zero.right = right;
        return zero;
    }

    pub fn root(self: *LeafNode) *const [32]u8 {
        return self.hash;
    }
};

pub fn initBranchNode(allocator: Allocator, left: *Node, right: *Node) !*Node {
    const branch = try BranchNode.init(allocator, left, right);
    const node = try allocator.create(Node);
    node.* = Node{ .Branch = branch.* };
    return node;
}

pub fn initLeafNode(allocator: Allocator, hash: *const [32]u8) !*Node {
    const leaf = try LeafNode.init(allocator, hash);
    const node = try allocator.create(Node);
    node.* = Node{ .Leaf = leaf.* };
    return node;
}

pub fn initZeroNode(allocator: Allocator, hash: *const [32]u8, left: ?*Node, right: ?*Node) !*Node {
    const zero = try ZeroNode.init(allocator, hash, left, right);
    const node = try allocator.create(Node);
    node.* = Node{ .Zero = zero.* };
    return node;
}

pub fn getRoot(node: *Node) *const [32]u8 {
    switch (node.*) {
        .Leaf => return node.Leaf.root(),
        .Branch => return node.Branch.root(),
        .Zero => return node.Zero.hash,
    }
}

pub fn getLeft(node: *Node) !*Node {
    switch (node.*) {
        .Branch => return node.Branch.left,
        .Zero => return node.Zero.left orelse return error.NoLeft,
        else => return error.NoLeft,
    }
}

pub fn getRight(node: *Node) !*Node {
    switch (node.*) {
        .Branch => return node.Branch.right,
        .Zero => return node.Zero.right orelse return error.NoRight,
        else => return error.NoRight,
    }
}

pub fn incRefCount(node: *Node) void {
    switch (node.*) {
        .Leaf => node.Leaf.ref_count += 1,
        .Branch => node.Branch.ref_count += 1,
        .Zero => {}, // do nothing
    }
}

pub fn decRefCount(node: *Node) void {
    switch (node.*) {
        .Leaf => node.Leaf.ref_count = @max(node.Leaf.ref_count - 1, 0),
        .Branch => node.Branch.ref_count = @max(node.Branch.ref_count - 1, 0),
        .Zero => {}, // do nothing
    }
}

pub fn setRefCount(node: *Node, count: usize) void {
    switch (node.*) {
        .Leaf => node.Leaf.ref_count = count,
        .Branch => node.Branch.ref_count = count,
        .Zero => {}, // do nothing
    }
}

pub fn getRefCount(node: *Node) usize {
    switch (node.*) {
        .Leaf => return node.Leaf.ref_count,
        .Branch => return node.Branch.ref_count,
        .Zero => {}, // do nothing
    }
}

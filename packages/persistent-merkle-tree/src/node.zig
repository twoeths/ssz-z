const std = @import("std");
const Allocator = std.mem.Allocator;
const digest64Into = @import("./sha256.zig").digest64Into;

pub const NodeType = enum {
    Branch,
    Leaf,
};

pub const Node = union(NodeType) {
    Branch: BranchNode,
    Leaf: LeafNode,
};

pub const BranchNode = struct {
    hash: *[32]u8,
    hash_computed: bool,
    left: *Node,
    right: *Node,
    ref_count: usize,

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

    pub fn root(self: *BranchNode) *[32]u8 {
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
    hash: *[32]u8,
    ref_count: usize,

    pub fn init(allocator: Allocator, hash: *const [32]u8) !*LeafNode {
        const leaf = try allocator.create(LeafNode);
        leaf.hash = try allocator.create([32]u8);
        @memcpy(leaf.hash.*[0..], hash.*[0..]);
        leaf.ref_count = 0;
        return leaf;
    }

    pub fn root(self: *LeafNode) *[32]u8 {
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

pub fn getRoot(node: *Node) *[32]u8 {
    switch (node.*) {
        .Leaf => return node.Leaf.root(),
        .Branch => return node.Branch.root(),
    }
}

pub fn incRefCount(node: *Node) void {
    switch (node.*) {
        .Leaf => node.Leaf.ref_count += 1,
        .Branch => node.Branch.ref_count += 1,
    }
}

pub fn decRefCount(node: *Node) void {
    switch (node.*) {
        .Leaf => node.Leaf.ref_count = @max(node.Leaf.ref_count - 1, 0),
        .Branch => node.Branch.ref_count = @max(node.Branch.ref_count - 1, 0),
    }
}

pub fn setRefCount(node: *Node, count: usize) void {
    switch (node.*) {
        .Leaf => node.Leaf.ref_count = count,
        .Branch => node.Branch.ref_count = count,
    }
}

pub fn getRefCount(node: *Node) usize {
    switch (node.*) {
        .Leaf => return node.Leaf.ref_count,
        .Branch => return node.Branch.ref_count,
    }
}

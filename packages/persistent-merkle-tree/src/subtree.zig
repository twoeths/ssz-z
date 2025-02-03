const std = @import("std");
const nm = @import("./node.zig");
const Node = nm.Node;
const NodePool = @import("./pool.zig").NodePool;
const getNodesAtDepth = @import("./tree.zig").getNodesAtDepth;

pub fn subtreeFillToDepth(pool: *NodePool, bottom: *Node, depth: usize) !*Node {
    var d = depth;
    var node = bottom;
    while (d > 0) : (d -= 1) {
        node = try pool.newBranch(node, node);
    }

    return node;
}

pub fn subtreeFillToLength(pool: *NodePool, bottom: *Node, depth: usize, length: usize) !*Node {
    const max_length = 1 << depth;
    if (length > max_length) {
        return error.InvalidLength;
    }

    if (length == max_length) {
        return subtreeFillToDepth(pool, bottom, depth);
    }

    if (depth == 0) {
        if (length == 1) {
            return bottom;
        } else {
            return error.InvalidLength;
        }
    }

    if (depth == 1) {
        const right = if (length > 1) bottom else pool.getZeroNode(0);
        return pool.newBranch(bottom, right);
    }

    const pivot = max_length >> 1;
    if (length <= pivot) {
        const left = subtreeFillToLength(pool, bottom, depth - 1, length);
        const right = try pool.getZeroNode(depth - 1);
        return pool.newBranch(left, right);
    } else {
        const left = subtreeFillToDepth(pool, bottom, depth - 1);
        const right = subtreeFillToLength(pool, bottom, depth - 1, length - pivot);
        return pool.newBranch(left, right);
    }
}

/// WARNING: Mutates the provided nodes array.
/// TODO: Don't mutate the nodes array.
/// TODO: HashComputation
pub fn subtreeFillToContents(pool: *NodePool, nodes: []*Node, depth: usize) !*Node {
    const max_length: usize = std.math.pow(usize, 2, depth);
    if (nodes.len > max_length) {
        return error.InvalidLength;
    }

    if (nodes.len == 0) {
        return pool.getZeroNode(depth);
    }

    if (depth == 0) {
        return nodes[0];
    }

    if (depth == 1) {
        // All nodes at depth 1 available
        // If there is only one node, pad with zero node
        const left_node = nodes[0];
        const right_node = if (nodes.len > 1) nodes[1] else try pool.getZeroNode(0);
        return pool.newBranch(left_node, right_node);
    }

    var count = nodes.len;
    var d = depth;
    while (d > 0) : (d -= 1) {
        const count_remainder = count % 2;
        const count_even = count - count_remainder;

        // For each depth level compute the new BranchNodes and overwrite the nodes array
        var i: usize = 0;
        while (i < count_even) : (i += 2) {
            const left = nodes[i];
            const right = nodes[i + 1];
            const node = try pool.newBranch(left, right);
            nodes[i / 2] = node;
        }

        if (count_remainder > 0) {
            const left = nodes[count_even];
            const right = try pool.getZeroNode(depth - d);
            const node = try pool.newBranch(left, right);
            nodes[count_even / 2] = node;
        }

        // If there was remainer, 2 nodes are added to the count
        count = count_even / 2 + count_remainder;
    }

    return nodes[0];
}

// private function, not included in build
fn nodeNum(pool: *NodePool, num: u8) !*Node {
    const hash = [_]u8{num} ** 32;
    return pool.newLeaf(&hash);
}

test "Simple case" {
    const allocator = std.testing.allocator;
    var pool = try NodePool.init(allocator, 10);
    defer pool.deinit();

    const node1 = try nodeNum(&pool, 1);
    const node2 = try nodeNum(&pool, 2);
    const node3 = try nodeNum(&pool, 3);
    const node4 = try nodeNum(&pool, 4);

    var nodes = [_]*Node{ node1, node2, node3, node4 };
    const root = try subtreeFillToContents(&pool, nodes[0..], 2);
    try pool.unref(root);
}

test "should not error on contents length 1" {
    const allocator = std.testing.allocator;
    var pool = try NodePool.init(allocator, 10);
    defer pool.deinit();

    const node = try pool.newZeroLeaf();
    var nodes = [_]*Node{node};
    const root = try subtreeFillToContents(&pool, nodes[0..], 1);
    try pool.unref(root);
}

test "should not error on empty contents" {
    const allocator = std.testing.allocator;
    var pool = try NodePool.init(allocator, 10);
    defer pool.deinit();

    const root0 = try subtreeFillToContents(&pool, &.{}, 0);
    const root1 = try subtreeFillToContents(&pool, &.{}, 1);

    try pool.unref(root0);
    try pool.unref(root1);
}

test "should not error on depth 31" {
    const allocator = std.testing.allocator;
    var pool = try NodePool.init(allocator, 10);
    defer pool.deinit();

    const root = try subtreeFillToContents(&pool, &.{}, 31);

    try pool.unref(root);
}

// TODO: executeHashComputations confirmation
test "subtreeFillToContents at different depths and counts" {
    const allocator = std.testing.allocator;
    var pool = try NodePool.init(allocator, 200_000);
    defer pool.deinit();

    var nodes: [200_000]*Node = undefined;
    var expected_nodes: [200_000]*Node = undefined;
    var retrieved_nodes: [200_000]*Node = undefined;

    var depth: usize = 1;
    while (depth <= 32) : (depth *= 2) {
        const max_index: usize = @min(std.math.pow(usize, 2, depth), 200_000);

        var count: usize = 1;
        while (count < max_index) : (count *= 2) {
            for (0..count) |i| {
                const node = try pool.newZeroLeaf();
                nodes[i] = node;
                expected_nodes[i] = node;
            }

            const root = try subtreeFillToContents(&pool, nodes[0..count], depth);

            // Assert correct
            const num_nodes = try getNodesAtDepth(root, depth, 0, count, retrieved_nodes[0..]);
            try std.testing.expect(num_nodes == count);

            for (0..count) |i| {
                try std.testing.expect(retrieved_nodes[i] == expected_nodes[i]);
            }

            try pool.unref(root);
        }
    }
}

// TODO: subtreeFillToContents with hcByLevel
// TODO: should compute HashComputations for validator nodes

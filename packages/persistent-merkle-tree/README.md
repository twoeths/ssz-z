# Persistent Merkle Tree

![Zig 0.13](https://img.shields.io/badge/Zig-F7A41D?logo=zig&logoColor=fff)

A binary merkle tree implemented as a [persistent data structure](https://en.wikipedia.org/wiki/Persistent_data_structure).
This is a port of [typescript implementation](https://github.com/ChainSafe/ssz/tree/master/packages/persistent-merkle-tree).

## Example

```zig
// LeafNode and BranchNode are used to build nodes in a tree
// Nodes may not be changed once initialized

const allocator = std.testing.allocator;
var pool = try NodePool.init(allocator, 10);
defer pool.deinit();

const hash1: [32]u8 = [_]u8{1} ** 32;
const hash2: [32]u8 = [_]u8{2} ** 32;
const leaf = try pool.newLeaf(&hash1);
const otherLeaf = try pool.newLeaf(&hash2);

var branch = try pool.newBranch(leaf1, leaf2);

// The `root` property returns the merkle root of a Node

// this is equal to `hash(leaf.root, otherLeaf.root));`
const root = nm.getRoot(branch);

// cleanup
try pool.unref(branch);

// Well-known zero nodes are provided

// 0x0
const zero0 = try pool.getZeroNode(0);

// hash(0, 0)
const zero1 = try pool.getZeroNode(0);

// hash(hash(0, 0), hash(0, 0))
const zero2 = try pool.getZeroNode(0);

// Tree provides a mutable wrapper around a "root" Node

const tree = pool.getTree(try pool.getZeroNode(10));

// `rootNode` property returns the root Node of a Tree

const rootNode = tree.getRootNode();

// `root` property returns the merkle root of a Tree

const rr = try tree.getRoot();

// A Tree is navigated by Gindex

const gindex: u64 = ...;

const n: Node = try tree.getTreeNode(gindex); // the Node at gindex
const rrr: Uint8Array = try tree.getRootOfNode(gindex); // the *[32]u8 root at gindex
const subtree: Tree = tree.getSubtree(gindex); // the Tree wrapping the Node at gindex. Updates to `subtree` will be propagated to `tree`

```

## Motivation

When dealing with large datasets, it is very expensive to merkleize them in their entirety. In cases where large datasets are remerkleized often between updates and additions, using ephemeral structures for intermediate hashes results in significant duplicated work, as many intermediate hashes will be recomputed and thrown away on each merkleization. In these cases, maintaining structures for the entire tree, intermediate nodes included, can mitigate these issues and allow for additional usecases (eg: proof generation). This implementation also uses the known immutability of nodes to share data between common subtrees across different versions of the data.

## Features

#### Intermediate nodes with cached, lazily computed hashes

The tree is represented as a linked tree of `Node`s, currently either `BranchNode`s or `LeafNode`s or `ZeroNode`s.
A `BranchNode` has a `left` and `right` child `Node`, and a `root`, 32 byte `*[32]u8`.
A `LeafNode` has a `root`.
The `root` of a `Node` is not computed until requested, and cached thereafter.

#### Shared data betwen common subtrees

Any update to a tree (either to a leaf or intermediate node) is performed as a rebinding that yields a new, updated tree that maximally shares data between versions. Garbage collection allows memory from unused nodes to be eventually reclaimed.

#### Mutable wrapper for the persistent core

A `Tree` object wraps `Node` and provides an API for tree navigation and transparent rebinding on updates.

#### Navigation by gindex or (depth, index)

Many tree methods allow navigation with a gindex. A gindex (or generalized index) describes a path through the tree, starting from the root and nagivating downwards.

```
     1
   /   \
  2     3
/  \   /  \
4  5   6  7
```

It can also be interpreted as a bitstring, starting with "1", then appending "0" for each navigation left, or "1" for each navigation right.

```
        1
    /      \
   10       11
 /    \    /    \
100  101  110  111
```

Alternatively, several tree methods, with names ending with `AtDepth`, allow navigation by (depth, index). Depth and index navigation works by first navigating down levels into the tree from the top, starting at 0 (depth), and indexing nodes from the left, starting at 0 (index).

```
     0          <- depth 0
   /   \
  0     1       <- depth 1
/  \   /  \
0  1   2  3     <- depth 2
```

#### Memory efficiency

The Merkle tree implementation uses a centralized node pool to manage all nodes efficiently. Nodes are created by the pool and reused to minimize memory allocations. When a node is no longer needed, you should call the `unref()` method, which decreases the node's reference count.

- Reference Counting: Each node tracks its usage with a reference count. When the count reaches zero, the node is returned to the pool.
- Reusability: Returned nodes are stored in the pool's LeafList and BranchList, making them available for reuse. This significantly reduces the need for frequent memory allocation during the application's lifetime.
- Memory Allocation: A single allocator is managed within the pool, simplifying memory management across the API. When trees are no longer in use, nodes should be returned to the pool via the `unref()` method. The pool will then handle cleanup and deallocate memory when required.

This design ensures efficient memory usage and optimal performance, especially in applications where nodes are frequently created and discarded.

#### Navigation efficiency

In performance-critical applications performing many reads and writes to trees, being smart with tree navigation is crucial. This library correctly provides tree navigation methods that handle several important optimized cases: multi-node get and set, and get-then-set operations.

## See also:

https://github.com/protolambda/remerkleable

### Audit

This repo was audited by Least Authority as part of [this security audit](https://github.com/ChainSafe/lodestar/blob/master/audits/2020-03-23_UTILITY_LIBRARIES.pdf), released 2020-03-23. Commit [`8b5ad7`](https://github.com/ChainSafe/bls-hd-key/commit/8b5ad7) verified in the report.

## License

Apache-2.0

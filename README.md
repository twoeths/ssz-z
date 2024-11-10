# ssz-z
An implementation of Ethereum Consensus Spec SimpleSerialize https://github.com/ethereum/consensus-specs/tree/dev/ssz. This follows Typescript implementation of Lodestar team https://github.com/ChainSafe/ssz. Some features:
- support generic. If you have an application struct, just write a respective ssz struct and create a ssz type then you have an ssz implementation. More on that in the example below.
- designed to support batch hash through `merkleize` function
- support generic `HashFn` as a parameter when creating a new type

## Examples

## Commands:
- `zig build test` to run all tests
- `zig test --dep util -Mroot=src/hash/merkleize.zig  -Mutil=lib/hex.zig` run tests in merkleize.zig
- `zig test --dep hash -Mroot=src/type/container.zig -Mhash=src/hash/merkleize.zig` run tests in src/type/container.zig
- `zig build test --verbose` to see how to map modules
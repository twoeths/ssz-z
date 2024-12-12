# ssz-z
An implementation of Ethereum Consensus Spec SimpleSerialize https://github.com/ethereum/consensus-specs/tree/dev/ssz. This follows Typescript implementation of Lodestar team https://github.com/ChainSafe/ssz. Some features:
- support generic. If you have an application struct, just write a respective ssz struct and create a ssz type then you have an ssz implementation. More on that in the example below.
- designed to support batch hash through `merkleize` function
- support generic `HashFn` as a parameter when creating a new type

## Examples

## Commands:
- `zig build test:unit` to run all unit tests
- `zig build test:int` to run all integration tests (tests across types)
- `zig test --dep util -Mroot=src/hash/merkleize.zig  -Mutil=lib/hex.zig` run tests in merkleize.zig
- `zig test --dep util --dep hash -Mroot=src/type/container.zig -Mutil=/Users/tuyennguyen/Projects/workshop/ssz-z/lib/hex.zig -Mhash=src/hash/merkleize.zig` to run tests in `src/type/container.zig`
- `zig build test:unit --verbose` to see how to map modules
# ssz-z
An implementation of Ethereum Consensus Spec SimpleSerialize

## Commands:
- `zig build test` to run all tests
- `zig test --dep util -Mroot=src/hash/merkleize.zig  -Mutil=lib/hex.zig` run tests in merkleize.zig
- `zig test --dep hash -Mroot=src/type/container.zig -Mhash=src/hash/merkleize.zig` run tests in src/type/container.zig
- `zig build test --verbose` to see how to map modules
/// this helps avoid heap memory allocation in setNodesAtDepth() below
/// VALIDATOR_REGISTRY_LIMIT is only 2**40 (= 1,099,511,627,776)
pub const MAX_NODES_DEPTH = 64;

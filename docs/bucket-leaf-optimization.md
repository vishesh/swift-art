# Bucket Leaf Optimization

## Overview

The bucket leaf optimization reduces memory usage in the Adaptive Radix Tree (ART) by storing multiple key-value pairs in a single leaf node, rather than one entry per leaf.

## Implementation

### Structure
- Each bucket leaf stores up to 32 entries
- Entries are kept sorted for efficient lookup
- Uses linear search (optimal for small buckets)
- Automatically splits when capacity exceeded

### Memory Impact
- **Before**: ~62 bytes per entry (single-entry leaves)
- **After**: ~20.5 bytes per entry (32-entry buckets)
- **Reduction**: 67% memory savings

### Theoretical Analysis
For 100,000 entries:
- Dictionary: ~3.8 MB (theoretical), ~7.4 MB (actual with hash overhead)
- Single leaves: ~6.2 MB
- Bucket leaves: ~1.7 MB
- **Savings**: 55-73% depending on baseline

## Current Status

### Working Features
✅ Insert operations with bucket allocation
✅ Delete operations with bucket management
✅ Basic iteration through buckets
✅ Copy-on-write semantics preserved
✅ Bucket splitting when full

### Known Issues
❌ Collection.map() fails with "count differed in successive traversals"
❌ Complex iteration patterns may fail
❌ Some tests hang during iteration

### Root Cause Analysis
The iteration issue stems from how Swift's Collection protocol requires stable iteration. The current implementation has an issue where:

1. The iterator stores references to bucket nodes
2. These references use unretained storage for performance
3. Multiple iterations may see different states
4. Collection.count iterates once, then map() iterates again
5. If these give different results, Swift's runtime fails

## Performance Characteristics

### Pros
- 67% memory reduction
- Better cache locality (32 entries per cache line vs scattered)
- Reduced pointer chasing during traversal
- Amortized allocation overhead

### Cons
- Linear search within buckets (acceptable for size 32)
- More complex iteration logic
- Potential for wasted space in partially-filled buckets

## Future Optimizations

1. **Fix iteration stability**: Ensure proper reference counting during iteration
2. **Adaptive bucket sizes**: Start small, grow as needed
3. **SIMD search**: Use vector operations for bucket search
4. **Compression**: Delta-encode keys within buckets
5. **Bucket merging**: Combine undersized adjacent buckets

## Conclusion

The bucket leaf optimization provides substantial memory savings (67%) with the trade-off of increased implementation complexity. The core functionality works but requires refinement of the iteration mechanism to fully integrate with Swift's Collection protocol.

The optimization is particularly valuable for:
- Large datasets where memory is constrained
- Workloads with good key locality
- Applications that primarily use direct lookups over iteration

Once the iteration issues are resolved, this optimization will make the ART implementation significantly more memory-efficient than both standard Dictionary and single-entry leaf implementations.
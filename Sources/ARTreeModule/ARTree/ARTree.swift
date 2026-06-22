/// An ordered collection of unique keys and associated values, optimized for space,
/// mutating shared copies, and efficient range operations, particularly read
/// operations.
///
/// `ARTree` has the same functionality as a standard `Dictionary`, and it largely
/// implements the same APIs. However, `ARTree` is optimized specifically for use cases
/// where underlying keys share common prefixes. The underlying data-structure is a
/// _persistent_ variant of _Adaptive Radix Tree (ART)_.

/// Alias for `ARTreeImpl` using the default specification.
typealias ARTree<Value> = ARTreeImpl<DefaultSpec<Value>>

/// Implements a persistent Adaptive Radix Tree (ART).
internal struct ARTreeImpl<Spec: ARTreeSpec> {
  public typealias Spec = Spec
  public typealias Value = Spec.Value

  @usableFromInline
  internal var _root: RawNode?
  internal var version: Int

  @inlinable
  public init() {
    self._root = nil
    self.version = -1
  }
}

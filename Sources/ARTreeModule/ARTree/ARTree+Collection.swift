@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension ARTreeImpl {
  @usableFromInline
  var startIndex: Index  {
    var idx = Index(forTree: self)
    idx.descentToLeftMostChild()
    return idx
  }

  @usableFromInline
  var endIndex: Index  {
    return Index(forTree: self)
  }
}

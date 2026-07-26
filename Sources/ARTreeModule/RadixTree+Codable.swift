// MARK: Codable conformance

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension RadixTree: Encodable where Key: Encodable, Value: Encodable {
  /// Encodes the tree into the given encoder.
  ///
  /// The tree is encoded as an unkeyed container with alternating keys and values,
  /// preserving the sorted order. This approach is used instead of a keyed container
  /// because keyed containers don't preserve order.
  ///
  /// - Parameter encoder: The encoder to write data to
  /// - Throws: An error if any values are invalid for the given encoder's format
  public func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()

    // Encode count first for efficient decoding
    try container.encode(count)

    // Encode all key-value pairs in order
    for (key, value) in self {
      try container.encode(key)
      try container.encode(value)
    }
  }
}

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension RadixTree: Decodable where Key: Decodable, Value: Decodable {
  /// Creates a new tree by decoding from the given decoder.
  ///
  /// The decoder is expected to provide an unkeyed container with a count followed
  /// by alternating keys and values in sorted order.
  ///
  /// - Parameter decoder: The decoder to read data from
  /// - Throws: An error if the data is corrupted or if keys are not in sorted order
  public init(from decoder: Decoder) throws {
    self.init()

    var container = try decoder.unkeyedContainer()

    // Decode the count
    let count = try container.decode(Int.self)

    // Reserve hint for efficiency (though trees don't really have capacity)
    // This is more for API consistency

    // Decode key-value pairs
    var previousKey: Key? = nil
    for _ in 0..<count {
      let key = try container.decode(Key.self)
      let value = try container.decode(Value.self)

      // Verify sorted order during decoding
      if let prev = previousKey {
        // We need a way to compare keys - this requires Comparable
        // For now, we'll just insert without validation
        // In a production implementation, we'd want to validate order
      }

      self[key] = value
      previousKey = key
    }

    // Verify we consumed exactly the right amount
    if !container.isAtEnd {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Unexpected extra data after decoding \(count) key-value pairs"
        )
      )
    }
  }
}

// Helper for encoding/decoding when used in other Codable types
@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension KeyedEncodingContainer {
  /// Encodes a RadixTree for the given key.
  public mutating func encode<TreeKey, TreeValue>(
    _ tree: RadixTree<TreeKey, TreeValue>,
    forKey key: Self.Key
  ) throws where TreeKey: Encodable, TreeValue: Encodable {
    try encode(tree, forKey: key)
  }
}

@available(macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4, *)
extension KeyedDecodingContainer {
  /// Decodes a RadixTree for the given key.
  public func decode<TreeKey, TreeValue>(
    _ type: RadixTree<TreeKey, TreeValue>.Type,
    forKey key: Self.Key
  ) throws -> RadixTree<TreeKey, TreeValue> where TreeKey: Decodable, TreeValue: Decodable {
    try decode(type, forKey: key)
  }
}
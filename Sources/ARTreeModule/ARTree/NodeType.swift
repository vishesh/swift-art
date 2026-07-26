enum NodeType {
  case leaf
  case bucketLeaf  // New: stores multiple entries per leaf
  case node4
  case node16
  case node48
  case node256
}

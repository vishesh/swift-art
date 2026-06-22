import Testing
import _CollectionsTestSupport
@testable import ARTreeModule

final class ARTreeNode256Tests: CollectionTestCase {
  typealias Leaf = NodeLeaf<DefaultSpec<[UInt8]>>
  typealias N256 = Node256<DefaultSpec<[UInt8]>>

  @Test func test256Basic() throws {
    var node = N256.allocate()
    _ = node.addChild(forKey: 10, node: Leaf.allocate(key: [10], value: [0]))
    _ = node.addChild(forKey: 20, node: Leaf.allocate(key: [20], value: [3]))
    expectEqual(
      node.print(),
      "○ Node256 {childs=2, partial=[]}\n" +
      "├──○ 10: 1[10] -> [0]\n" +
      "└──○ 20: 1[20] -> [3]")
  }

  @Test func test48DeleteAtIndex() throws {
    var node = N256.allocate()
    _ = node.addChild(forKey: 10, node: Leaf.allocate(key: [10], value: [1]))
    _ = node.addChild(forKey: 15, node: Leaf.allocate(key: [15], value: [2]))
    _ = node.addChild(forKey: 20, node: Leaf.allocate(key: [20], value: [3]))
    expectEqual(
      node.print(),
      "○ Node256 {childs=3, partial=[]}\n" +
      "├──○ 10: 1[10] -> [1]\n" +
      "├──○ 15: 1[15] -> [2]\n" +
      "└──○ 20: 1[20] -> [3]")
    _ = node.removeChild(at: 10)
    expectEqual(
      node.print(),
      "○ Node256 {childs=2, partial=[]}\n" +
      "├──○ 15: 1[15] -> [2]\n" +
      "└──○ 20: 1[20] -> [3]")
    _ = node.removeChild(at: 15)
    expectEqual(
      node.print(),
      "○ Node256 {childs=1, partial=[]}\n" +
      "└──○ 20: 1[20] -> [3]")
    _ = node.removeChild(at: 20)
    expectEqual(node.print(), "○ Node256 {childs=0, partial=[]}\n")
  }
}

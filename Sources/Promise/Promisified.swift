// Extension point for other classes. See URLSession

public struct Promisified<Base> {
  public let base: Base
  public init(_ base: Base) {
    self.base = base
  }
}

public protocol PromiseCompatible {
  associatedtype PromisifiedBase
  static var p: Promisified<PromisifiedBase>.Type { get }
  var p: Promisified<PromisifiedBase> { get }
}

public extension PromiseCompatible {
  static var p: Promisified<Self>.Type {
    get { Promisified<Self>.self }
  }

  var p: Promisified<Self> {
    get { Promisified(self) }
  }
}

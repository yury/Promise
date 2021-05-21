public final class Disposable {
  private var _disposeFn: (() -> ())? = nil
  private var _child: Disposable? = nil
  
  init(_ fn: @escaping () -> ()) {
    _disposeFn = fn
  }
  
  public final func dispose() {
    _child?.dispose()
    _disposeFn?()
    
    _child = nil
    _disposeFn = nil
  }
  
  final func append(to parent: Disposable) {
    parent._child = self
  }
  
  final func store(in parent: Disposable) -> Disposable {
    parent._child = self
    return parent
  }
  
  static var noop: Disposable {
    .init {}
  }
  
  static func wrap(_ fn: @escaping () -> ()) -> Disposable {
    .init(fn)
  }
  
  static func wrap(_ c: Disposable) -> Disposable {
    .wrap(c.dispose)
  }
  
  deinit {
    dispose()
  }
}




#if canImport(Combine)
import Combine

extension Promise {
  @available(iOS 13.0, macOS 10.15, *)
  func publisher() -> AnyPublisher<O, E> {
    var disposable: Disposable? = nil
    var sinkFn: Fn? = nil
    
    return Future { sinkFn = $0 }
    .handleEvents(
      receiveCompletion: { _ in disposable?.dispose() },
      receiveCancel: { disposable?.dispose() },
      receiveRequest: { demand in
        if let fn = sinkFn, demand != .none {
          disposable = self.on(result: fn)
        }
      }
    )
    .eraseToAnyPublisher()
  }
}

#endif

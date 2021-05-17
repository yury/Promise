import Dispatch

public final class Promise<O, E> where E: Error {
  public typealias Result = Swift.Result<O, E>
  public typealias Fn = (Result) -> ()
  
  private let _resolver: (@escaping Fn) -> Disposable
  private var _callback: Fn? = nil
  private var _receiverQueue: DispatchQueue? = nil
  
  public init(_ resolver: @escaping (@escaping Fn) -> Disposable) {
    _resolver = resolver
  }
  
  private final func _resolve(with result: Result) {
    guard
      let callback = _callback
    else {
      return
    }
    
    // we call callback only once
    _callback = nil
    let q = _receiverQueue ?? DispatchQueue.global()
    q.async {
      callback(result)
    }
  }
  
  public final func on(result: @escaping Fn, dispose: (() -> ())? = nil) -> Disposable {
    _callback = result
    return _resolver(_resolve).store(in: .wrap {
      self._callback = nil
      dispose?()
    })
  }
  
  public final func chain(result: @escaping Fn, dispose: (() -> ())? = nil) -> Disposable {
    _callback = result
    return _resolver(_resolve).store(in: .wrap {
      dispose?()
    })
  }
  
  public final func awaitResult(timeout: DispatchTime = .distantFuture) -> Result? {
    var result: Result? = nil
    var d: Disposable? = nil
    
    defer {
      d?.dispose()
    }
    
    let g = DispatchGroup()
    g.enter()
    d = on(result: {
      result = $0
      g.leave()
    }, dispose: {
      if result == nil {
        g.leave()
      }
    })
    
    _ = g.wait(timeout: timeout)
    return result
  }
  
  public final func awaitOutput(timeout: DispatchTime = .distantFuture) throws -> O? {
    let result = awaitResult()
    switch result {
    case .none:           return nil
    case .failure(let e): throw e
    case .success(let o): return o
    }
  }
  
  public final func delay(
    _ wait: DispatchTimeInterval,
    queue: DispatchQueue = DispatchQueue.global()
  ) -> Promise {
    Promise { [self] fn in
      self.chain { result in
        queue.asyncAfter(deadline: DispatchTime.now() + wait) {
          fn(result)
        }
      }
    }
  }
  
  public final func receiveOn(queue: DispatchQueue) -> Promise {
    _receiverQueue = queue
    return self
  }
  
  // Map output to new output
  public final func map<T>(_ transform: @escaping (O) -> T) -> Promise<T, E> {
    Promise<T, E> { [self] fn in
      self.chain { result in
        fn(result.map(transform))
      }
    }
  }
  
  public final func tap(_ tapFn: @escaping (O) -> Void) -> Promise {
    Promise { [self] fn in
      self.chain { result in
        if case .success(let v) = result {
          tapFn(v)
        }
        
        fn(result)
      }
    }
  }
  
  public final func tapResult(_ tapFn: @escaping (Result) -> Void) -> Promise {
    Promise { [self] fn in
      self.chain { result in
        tapFn(result)
        fn(result)
      }
    }
  }
  
  // Map output to result with new output
  public final func map<T>(_ transform: @escaping (O) -> Promise<T, E>.Result) -> Promise<T, E> {
    Promise<T, E> { [self] fn in
      self.chain { result in
        switch result {
        case .failure(let err): fn(.failure(err))
        case .success(let v): fn(transform(v))
        }
      }
    }
  }
  
  public final func repeatIfNeeded(_ predicate: @escaping (Result) -> Bool) -> Promise {
    let original = self
    var disposable: Disposable! = nil

    return Promise { fn in
      disposable = self.on { o in
        if predicate(o) {
          original.repeatIfNeeded(predicate).chain(result: fn).append(to: disposable)
        } else {
          fn(o)
        }
      }

      return disposable
    }
  }
  
  public final func mapError<NewE>(_ transform: @escaping (E) -> NewE) -> Promise<O, NewE> where NewE: Error {
    Promise<O, NewE> { [self] fn in
      self.chain { result in
        fn(result.mapError(transform))
      }
    }
  }
  
  public final func map<T>(_ transform: @escaping (O) throws -> T) -> Promise<T, Error> {
    Promise<T, Error> { [self] fn in
      self.chain { result in
        switch result {
        case .failure(let error):
          fn(.failure(error))
        case .success(let o):
          do {
            try fn(.success(transform(o)))
          } catch {
            fn(.failure(error))
          }
        }
      }
    }
  }
    
  public final func flatMap<T>(_ transform: @escaping (O) -> Promise<T, E>) -> Promise<T, E> {
    Promise<T, E> { [self] fn in
      var disposable: Disposable! = nil
      disposable = self.chain { result in
        switch result {
        case .failure(let err):
          fn(.failure(err))
        case .success(let output):
          transform(output).on(result: fn).append(to: disposable)
        }
      }
      
      return disposable
    }
  }
  
  public static func just(_ value: O) -> Promise<O, E> {
    Promise<O, E> { fn in
      fn(.success(value))
      return .noop
    }
  }
  
  public static func fail(_ error: E) -> Promise<O, E> {
    Promise<O, E> { fn in
      fn(.failure(error))
      return .noop
    }
  }

}

extension Promise where E == Never {
  public static func just(_ value: O) -> Promise<O, E> {
    Promise<O, E> { fn in
      fn(.success(value))
      return .noop
    }
  }
}

extension Promise where E == Error {
  public static func catching(_ body: @escaping () throws -> O) -> Promise<O, E> {
    Promise<O, E> { fn in
      fn(Result(catching: body))
      return .noop
    }
  }
}

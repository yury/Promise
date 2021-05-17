import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension URLSession: PromiseCompatible { }

extension Promisified where Base == URLSession {
  
  public typealias HTTPDataOutput = (data: Data, response: HTTPURLResponse)
  public typealias Handler = (Data?, URLResponse?, Error?) -> Void
  
  private func _commonCompletionHandler(_ fn: @escaping Promise<HTTPDataOutput, Swift.Error>.Fn) -> Handler {
    { data, response, error in
      
      if let error = error {
        return fn(.failure(error))
      }
      
      guard let response = response as? HTTPURLResponse else {
        return fn(.failure(URLError.init(.unknown)))
      }
      
      fn(.success((data ?? Data(), response)))
    } as Handler
  }
  
  func data(with request: URLRequest) -> Promise<HTTPDataOutput, Swift.Error> {
    Promise { fn in
      let task = base.dataTask(with: request, completionHandler: _commonCompletionHandler(fn))
      task.resume()
      return .wrap(task.cancel)
    }
  }
  
  func data(with url: URL) -> Promise<HTTPDataOutput, Swift.Error> {
    data(with: URLRequest(url: url))
  }
}

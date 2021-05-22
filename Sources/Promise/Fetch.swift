
import struct Foundation.URL
import struct Foundation.URLError
import struct Foundation.URLComponents
import struct Foundation.URLQueryItem
import struct Foundation.Data
import struct Foundation.TimeInterval
import protocol Foundation.LocalizedError

import class Foundation.NSNumber

import class Foundation.JSONSerialization

#if canImport(FoundationNetworking)
import FoundationNetworking
#else
import struct Foundation.URLRequest

import class Foundation.HTTPURLResponse
import class Foundation.URLSession
#endif


public protocol FetchAuthTokenProvider {
  var accessToken: String? { get }
  var refreshToken: String? { get }
  
  func refresh() -> Promise<(), Error>
}

extension Promise where O == Fetch.DataOutput, E == Error {
  func refreshAuthAndRetry(auth: Fetch.Auth) -> Promise<O, E> {
    flatMap { output in
      guard
        [401, 403].contains(output.response.statusCode),
        case .bearer(let tokenProvider) = auth
      else {
        return .just(output)
      }
      
      return tokenProvider.refresh().flatMap { self }
    }
  }
}

public enum Fetch {
  
  public enum Auth {
    case none
    case bearer(FetchAuthTokenProvider)
    
    func preparedRequest(request: URLRequest) -> Promise<URLRequest, Swift.Error> {
      Promise.catching {
        var request = request
        if case .bearer(let provider) = self,
           let bearer = provider.accessToken {
          request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        
        return request
      }
    }
  }
  
  public enum HttpMethod: String {
    case head, put, delete, connect, trace, patch, post, get, set, update, options
  }
  
  public enum HTTPBodyEncoding {
    case json([String : Any]? = nil)
    case xWWWFormUrlEncoded([String : Any]? = nil)
  }
  
  // https://developer.mozilla.org/en-US/docs/Web/HTTP/Status
  public enum ResponseStatus {
    case any
    case info, successfull, redirection, clientError, serverError
    case set(Set<Int>)
    case range(Range<Int>)
    
    func matches(statusCode: Int) -> Bool {
      switch self {
      case .any: return true
      case .info:        return (100..<200).contains(statusCode)
      case .successfull: return (200..<299).contains(statusCode)
      case .redirection: return (300..<399).contains(statusCode)
      case .clientError: return (400..<499).contains(statusCode)
      case .serverError: return (500..<599).contains(statusCode)
      case .set(let set):     return set.contains(statusCode)
      case .range(let range): return range.contains(statusCode)
      }
    }
  }
  
  public enum Error: Swift.Error, LocalizedError {
    case invalidParameter(name: String, message: String)
    case cannotBuildUrl
    case cannotBuildRequest(Swift.Error)
    case cannotParseJSON(Data)
    case unexpectedError(Swift.Error)
    case unexpectedResponseStatus(DataOutput)
    case unexpectedResponseFormat(name: String, message: String)
    case authError(Swift.Error)
    case urlError(URLError)
    
    public var errorDescription: String? {
      switch self {
      case .invalidParameter(name: let name, message: let message):
        return "Invalid parameter \(name): \(message)"
      case .cannotBuildUrl:
        return "Can't build URL"
      case .cannotBuildRequest(let error):
        return "Can't build request: \(error)"
      case .cannotParseJSON(let data):
        let body = String(data: data, encoding: .utf8) ?? "<Non UTF-8 String>"
        return "Can't parse json: \"\(body)\""
      case .unexpectedError(let error):
        return "Unexpected error: \(error)"
      case .unexpectedResponseStatus(let output):
        let body = String(data: output.data, encoding: .utf8) ?? "<Non UTF-8 String>"
        return "Unexpected response status \(output.response.statusCode): \(output.response)\nbody: \"\(body)\""
      case .unexpectedResponseFormat(name: let name, message: let message):
        return "Unexpected response format: \(name) - \(message)"
      case .authError(let error): return "Authentication Error: \(error)"
      case .urlError(let error): return "URLError: \(error)"
      }
    }
  }
  
  public typealias DataOutput = (data: Data, response: HTTPURLResponse)
  public typealias JSONOutput = (json: [String: Any], response: HTTPURLResponse)
  public typealias HTMLOutput = (html: Data, response: HTTPURLResponse)
  
  public static func json(
    _ method: HttpMethod,
    request: URLRequest,
    auth: Auth = .none,
    session: URLSession = .shared,
    expectedStatus: ResponseStatus = .any
  ) -> Promise<JSONOutput, Error> {
    var request = request
    request.setValue("utf-8", forHTTPHeaderField: "Accept-Charset")
    request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Accept")
    
    return data(method, request: request, auth: auth, session: session, expectedStatus: expectedStatus)
      .map { data, response in
        do {
          let jsonObj = try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
          return .success((json: jsonObj as? [String: Any] ?? [:], response: response))
        } catch {
          return .failure(.cannotParseJSON(data))
        }
      }
      
  }
  
  public static func html(
    _ method: HttpMethod,
    request: URLRequest,
    auth: Auth = .none,
    session: URLSession = .shared,
    expectedStatus: ResponseStatus = .any
  ) -> Promise<HTMLOutput, Error> {
    var request = request
    request.setValue("utf-8, iso-8859-1;q=0.5, *;q=0.1", forHTTPHeaderField: "Accept-Charset")
    request.setValue("text/html; charset=UTF-8", forHTTPHeaderField: "Accept")

    return data(method, request: request, auth: auth, session: session, expectedStatus: expectedStatus)
      .map { data, response in
        .success((html: data, response: response))
      }
  }
  
  public static func data(
    _ method: HttpMethod,
    request: URLRequest,
    auth: Auth = .none,
    session: URLSession = .shared,
    expectedStatus: ResponseStatus = .any
  ) -> Promise<DataOutput, Error> {
    var request = request
    request.httpMethod = method.rawValue.uppercased()
    return auth
      .preparedRequest(request: request)
      .flatMap(session.p.data)
      .refreshAuthAndRetry(auth: auth)
      .mapError(Error.unexpectedError)
      .map({ output in
        let statusCode = output.response.statusCode
        if expectedStatus.matches(statusCode: statusCode) {
          return .success(output)
        } else {
          return .failure(.unexpectedResponseStatus(output))
        }
      })
  }
}

public typealias RequestResult = Result<URLRequest, Fetch.Error>

public extension RequestResult {
  init(
    url: String,
    path: String? = nil,
    query: [String : String]? = nil,
    headers: [String : String?]? = nil,
    body: Fetch.HTTPBodyEncoding = .json(),
    cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
    timeoutInterval: TimeInterval = 60.0
  ) {
    self = URLRequest.build(
      url: url,
      path: path,
      query: query,
      headers: headers,
      body: body,
      cachePolicy: cachePolicy,
      timeoutInterval: timeoutInterval
    )
  }

  func fetchJSON(
    method: Fetch.HttpMethod,
    auth: Fetch.Auth = .none,
    session: URLSession = .shared,
    expectedStatus: Fetch.ResponseStatus = .any
  ) -> Promise<Fetch.JSONOutput, Fetch.Error> {
    promise().flatMap { request in
      Fetch.json(
        method,
        request: request,
        auth: auth,
        session: session,
        expectedStatus: expectedStatus
      )
    }
  }
  
  func fetchHTML(
    method: Fetch.HttpMethod,
    auth: Fetch.Auth = .none,
    session: URLSession = .shared,
    expectedStatus: Fetch.ResponseStatus = .any
  ) -> Promise<Fetch.HTMLOutput, Fetch.Error> {
    promise().flatMap { request in
      Fetch.html(
        method,
        request: request,
        auth: auth,
        session: session,
        expectedStatus: expectedStatus
      )
    }
  }
  
  func fetchData(
    method: Fetch.HttpMethod,
    auth: Fetch.Auth = .none,
    session: URLSession = .shared,
    expectedStatus: Fetch.ResponseStatus = .any
  ) -> Promise<Fetch.DataOutput, Fetch.Error> {
    promise().flatMap { request in
      Fetch.data(
        method,
        request: request,
        auth: auth,
        session: session,
        expectedStatus: expectedStatus
      )
    }
  }
}

public extension Result {
  var fetchError: Fetch.Error? {
    switch self {
    case .failure(let e): return e as? Fetch.Error
    case .success: return nil
    }
  }
  
  func promise() -> Promise<Success, Failure> {
    Promise { fn in
      fn(self)
      return .noop
    }
  }
}

public extension URLRequest {
  static func build(
    url: String,
    path: String? = nil,
    query: [String : String]? = nil,
    headers: [String : String?]? = nil,
    body: Fetch.HTTPBodyEncoding = .json(),
    cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
    timeoutInterval: TimeInterval = 60.0
  ) -> Result<URLRequest, Fetch.Error> {
    
    // Path and Query
    guard
      let url = url.url(path: path, query: query)
    else {
      return .failure(.cannotBuildUrl)
    }
    
    var request = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval)
    
    // Body
    
    do {
      try request.encodeHttpBody(body)
    } catch {
      return .failure(.cannotBuildRequest(error))
    }
    
    // Headers
    
    if let headers = headers {
      for (key, value) in headers {
        request.setValue(value, forHTTPHeaderField: key)
      }
    }
    
    return .success(request)
  }
  
  private mutating func encodeHttpBody(_ body: Fetch.HTTPBodyEncoding) throws {
    switch body {
    case .json(let obj):
      if let obj = obj {
        self.setValue("application/json", forHTTPHeaderField: "Content-Type")
        self.httpBody = try obj.jsonData()
      }
    case .xWWWFormUrlEncoded(let obj):
      if let obj = obj {
        self.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        self.httpBody = try obj.xWWWFormUrlEncodedData()
      }
    }
  }
}


fileprivate extension String {
  func url(path: String? = nil, query: [String: String?]?) -> URL? {
    guard
      var components = URLComponents(string: self)
    else {
      return nil
    }
    
    if let path = path, !path.isEmpty {
      let originalPath = components.path
      if path.starts(with: "/") {
        components.path = path
      } else if originalPath.hasSuffix("/") {
        components.path = originalPath + path
      } else {
        components.path = originalPath + "/" + path
      }
    }
    
    if let params = query {
      var items = components.queryItems ?? []
      for (key, value) in params {
        items.append(URLQueryItem(name: key, value: value))
      }
      
      components.queryItems = items
    }
    
    return components.url
  }
}

fileprivate extension Dictionary where Value == Any, Key == String {
  func jsonData() throws -> Data {
    try JSONSerialization.data(withJSONObject: self, options: [])
  }
  
  func xWWWFormUrlEncodedString() -> String {
    func typeToUrl(_ any: Any?) -> String? {
      guard let a = any else {
        return nil
      }
      if let v = a as? String {
        return v
      }
      if let v = a as? Bool {
        return v ? "true" : "false"
      }
      
      if let v = a as? NSNumber {
        return v.stringValue
      }
      
      if let v = a as? Data {
        return v.base64EncodedString()
      }
      
      return nil
    }
    
    var comps = URLComponents()
    comps.queryItems = map {  key, value in
      URLQueryItem(name: key, value: typeToUrl(value))
    }

    return comps.url?.query ?? ""
  }
  
  func xWWWFormUrlEncodedData() throws -> Data {
    guard let data = xWWWFormUrlEncodedString().data(using: .utf8) else {
      throw URLError(.badURL)
    }
    
    return data
  }
}

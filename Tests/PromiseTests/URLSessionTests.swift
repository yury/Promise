import XCTest
@testable import Promise


final class URLSessionTests: XCTestCase {
  
  func testAwaitOutput() throws {
    let output = try URLSession.shared
      .p.data(with: URL(string:"https://google.com")!)
      .map({ o throws -> (data: Data, response: HTTPURLResponse) in
        guard let httpResponse = o.response as? HTTPURLResponse else {
          throw URLError(.unknown)
        }
        
        return (data: o.data, response: httpResponse)
      })
      .awaitOutput()
    
    XCTAssertEqual(output?.response.statusCode, 200)
  }

  static var allTests = [
    ("testJust", testAwaitOutput)
  ]
}

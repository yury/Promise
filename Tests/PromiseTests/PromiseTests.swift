import XCTest
@testable import Promise

extension Promise {
  func on(test: XCTestCase, timeout: TimeInterval = 1, result: @escaping Promise.Fn) {
    let expectation = test.expectation(description: "Promise expectation")
    let dispose = on { a in
      result(a)
      expectation.fulfill()
    }
    test.wait(for: [expectation], timeout: timeout)
    dispose.dispose()
  }
  
  func result(test: XCTestCase, timeout: TimeInterval = 1) -> Promise.Result? {
    let expectation = test.expectation(description: "Promise expectation")
    var res: Result! = nil
    let dispose = on { result in
      res = result
      expectation.fulfill()
    }
    test.wait(for: [expectation], timeout: timeout)
    dispose.dispose()
    return res
  }

}

final class PromiseTests: XCTestCase {
  
  func testResultCalledOnlyOnce() {
    
    var n = 0;
    
    let d = Promise<Int, Never> { fn in
      fn(.success(1))
      fn(.success(2))
      fn(.success(3))
      return .noop
    }.on { result in
      n += 1
    }
    
    sleep(1)
    
    XCTAssertEqual(n, 1)
    d.dispose()
  }
  
  func testJust() {
    let result = Promise
      .just(10)
      .result(test: self)
    
    XCTAssertEqual(result, .success(10))
  }
  
  func testFail() {
    let result = Promise<Int, URLError>
      .fail(.init(.badURL))
      .result(test: self)
    
    XCTAssertEqual(result, .failure(.init(.badURL)))
  }
  
  func testMap() {
    let result = Promise<Int, Never>
      .just(10)
      .map { $0 + 1 }
      .map { $0 + 2 }
      .map { $0 + 3 }
      .result(test: self)
    
    XCTAssertEqual(result, .success(16))
  }
  
  func testFlatMap() {
    let result = Promise
      .just(10)
      .flatMap({ n in
        .just(30 + n)
      })
      .result(test: self)
    
    XCTAssertEqual(result, .success(40))
  }
  
  func testCatching() {
    let result = Promise.catching {
      throw URLError(.badURL)
    }.result(test: self)
    
    switch result {
    case .failure(let error):
      XCTAssertEqual(error.localizedDescription, URLError(.badURL).localizedDescription)
    default:
      XCTFail()
    }
  }
  
  func testRepeatIfNeeded() throws {
    
    let result = Promise.catching {
      Int.random(in: 0..<10)
    }.repeatIfNeeded { result in
      try! result.get() != 5
    }.result(test: self)!
    
    XCTAssertEqual(try result.get(), 5)
    
  }
  
  func testAwaitResult() {
    let result = Promise.just(1).awaitResult()!
    
    XCTAssertEqual(result, .success(1))
  }
  
  
  func testAwaitOutput() throws {
    let output = try Promise.just(1).awaitOutput()!
    
    XCTAssertEqual(output, 1)
  }

  static var allTests = [
    ("testJust", testJust),
    ("testFail", testFail),
    ("testMap", testMap),
    ("testFlatMap", testFlatMap),
    ("testRepeatIfNeeded", testRepeatIfNeeded),
  ]
}

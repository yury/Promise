import XCTest
@testable import Promise


final class FetchTests: XCTestCase {
  
  func testAwaitOutput() throws {
    
    do {
      let res = try Fetch.html(
        .get,
        request: try .build(
          url: "https://ya.ru"
        )
      )
      .awaitOutput()
      debugPrint(res!.response)
//      debugPrint(String(data: res!.html, encoding: .utf8)!)
      
      
    } catch {
      debugPrint(error)
    }

  }
  
  func testAuth() throws {
    
//    let url = "http://46.101.250.94"
    let auth0ClientId = "x7RQ8NR862VscbotFSfu2VO7PEj55ExK"
    let auth0Domain = "dev-i8bp-l6b.us.auth0.com"
    let auth0Scope = "offline_access+openid+profile+read:build+write:build"
    let auth0Audience = "blink.build"
    
    
    let res = try Fetch
      .json(
        .post,
        request: try .build(
          url: "https://\(auth0Domain)/oauth/device/code",
          bodyParams: [
            "client_id": auth0ClientId,
            "scope": auth0Scope,
            "audience": auth0Audience
          ],
          bodyEncoding: .xWWWFormUrlEncoded
      )
    ).awaitOutput()
    
    debugPrint(res)
  }

  static var allTests = [
    ("testJust", testAwaitOutput)
  ]
}

import XCTest
@testable import NSLogger

final class NSLoggerTests: XCTestCase {
    func testBasic() {
        Logger.shared.log(.network, .info, "Checking paper level…")
        // Logger doesn't have a flush, so I'll just wait
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 5))
    }
    static var allTests = [
        ("testBasic", testBasic),
    ]
}

import XCTest
@testable import WorthifyNative

final class WorthifyNativeTests: XCTestCase {
    func testPlaceholderAnalysisHasArtist() {
        XCTAssertFalse(ArtworkAnalysis.placeholder.artistText.isEmpty)
    }
}

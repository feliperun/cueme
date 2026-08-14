import XCTest
@testable import CueMe

/// The reload guard exists because activation can race with the fixture wiring
/// during UI tests. Adding a path for a real corpus must not weaken it, so the
/// decision is a pure function over the environment and is pinned here.
final class UITestCorpusModeTests: XCTestCase {
    // MARK: AC4 — without the new variable, nothing changes

    func testTheReloadStaysOffForAnOrdinaryUITestRun() {
        XCTAssertFalse(UITestFixtures.reloadFromDiskIsEnabled(["CUEME_UI_TESTING": "1"]))
        XCTAssertNil(UITestFixtures.externalCorpusRoot(["CUEME_UI_TESTING": "1"]))
    }

    func testTheReloadIsOnWhenTheAppIsNotUnderUITest() {
        XCTAssertTrue(UITestFixtures.reloadFromDiskIsEnabled([:]))
        XCTAssertTrue(UITestFixtures.reloadFromDiskIsEnabled(["CUEME_UI_TESTING": "0"]))
    }

    // MARK: A supplied corpus is meant to be read

    func testASuppliedCorpusTurnsTheReloadBackOn() {
        let environment = ["CUEME_UI_TESTING": "1", "CUEME_UI_CORPUS_ROOT": "/tmp/corpus"]

        XCTAssertTrue(UITestFixtures.reloadFromDiskIsEnabled(environment))
        XCTAssertEqual(
            UITestFixtures.externalCorpusRoot(environment)?.path,
            "/tmp/corpus"
        )
    }

    func testAnEmptyPathIsNotACorpus() {
        let environment = ["CUEME_UI_TESTING": "1", "CUEME_UI_CORPUS_ROOT": ""]

        XCTAssertNil(UITestFixtures.externalCorpusRoot(environment))
        XCTAssertFalse(
            UITestFixtures.reloadFromDiskIsEnabled(environment),
            "an empty value must not be read as a corpus and reopen the guard"
        )
    }
}

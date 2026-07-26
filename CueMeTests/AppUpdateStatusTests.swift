import XCTest
@testable import CueMe

final class AppUpdateStatusTests: XCTestCase {
    func testIdleAndCheckingDescribeTheCheckItself() {
        XCTAssertEqual(AppUpdateStatus.idle.summary, "Buscar atualizações…")
        XCTAssertFalse(AppUpdateStatus.idle.isBusy)

        XCTAssertEqual(AppUpdateStatus.checking.summary, "Procurando atualizações…")
        XCTAssertTrue(AppUpdateStatus.checking.isBusy)
    }

    func testUpToDateNamesTheVersionTheUserIsRunning() {
        let status = AppUpdateStatus.upToDate(currentVersion: "1.2.0")
        XCTAssertEqual(status.summary, "CueMe 1.2.0 é a versão mais recente")
        XCTAssertFalse(status.isBusy)
        XCTAssertFalse(status.isActionable)
    }

    func testAvailableNamesTheOfferedVersionAndIsActionable() {
        let status = AppUpdateStatus.available(version: "1.3.0")
        XCTAssertEqual(status.summary, "Atualização disponível: 1.3.0")
        XCTAssertTrue(status.isActionable)
        XCTAssertFalse(status.isBusy)
    }

    // The updater's own errors carry the feed URL and NSError internals. Users
    // must never see those (see the privacy rules in AGENTS.md), so the status
    // maps them onto a fixed set of human explanations.
    func testOfflineFailureIsExplainedWithoutLeakingInternals() {
        let underlying = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [NSURLErrorFailingURLStringErrorKey: "https://github.com/feliperun/cueme/releases/latest/download/appcast.xml"]
        )
        let status = AppUpdateStatus.failure(from: underlying)
        XCTAssertEqual(status, .failed(reason: .offline))
        XCTAssertEqual(status.summary, "Sem conexão para verificar atualizações")
        XCTAssertFalse(status.summary.contains("github.com"))
        XCTAssertFalse(status.summary.contains("appcast"))
    }

    func testMissingFeedIsReportedAsUnavailableRatherThanA404() {
        let underlying = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorFileDoesNotExist,
            userInfo: [NSLocalizedDescriptionKey: "The requested URL was not found on this server: https://github.com/feliperun/cueme/releases/latest/download/appcast.xml"]
        )
        let status = AppUpdateStatus.failure(from: underlying)
        XCTAssertEqual(status, .failed(reason: .feedUnavailable))
        XCTAssertEqual(status.summary, "Nenhuma atualização publicada ainda")
        XCTAssertFalse(status.summary.lowercased().contains("http"))
    }

    func testUnknownFailureKeepsAGenericExplanation() {
        let underlying = NSError(
            domain: "SUSparkleErrorDomain",
            code: 2001,
            userInfo: [NSLocalizedDescriptionKey: "/Users/frb/Library/Caches/Sparkle failed"]
        )
        let status = AppUpdateStatus.failure(from: underlying)
        XCTAssertEqual(status, .failed(reason: .unknown))
        XCTAssertEqual(status.summary, "Não foi possível verificar atualizações")
        XCTAssertFalse(status.summary.contains("/Users/"))
    }

    func testEveryFailureSummaryStaysFreeOfPathsAndURLs() {
        for reason in UpdateFailureReason.allCases {
            let summary = AppUpdateStatus.failed(reason: reason).summary
            XCTAssertFalse(summary.contains("http"), "\(reason) leaks a URL")
            XCTAssertFalse(summary.contains("/Users/"), "\(reason) leaks a path")
            XCTAssertFalse(summary.isEmpty)
        }
    }
}

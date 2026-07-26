import Foundation
import Sparkle

/// Bridges Sparkle's delegate callbacks onto an `AppUpdateStatus`, so the rest
/// of the app observes update state without importing Sparkle. Sparkle calls
/// these on the main thread; the hops keep that explicit for Swift concurrency.
final class UpdateStatusReporter: NSObject, SPUUpdaterDelegate {
    /// Set by `AppModel` once it exists — the reporter is built first because
    /// the updater controller needs a delegate at construction time.
    @MainActor var onChange: ((AppUpdateStatus) -> Void)?

    private func report(_ status: AppUpdateStatus) {
        Task { @MainActor in self.onChange?(status) }
    }

    /// The version the user is running, used to phrase "you are up to date".
    @MainActor static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        report(.available(version: item.displayVersionString))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            self.onChange?(.upToDate(currentVersion: Self.currentVersion))
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        // Sparkle reports "no update found" as an error too; only a genuine
        // transport/feed problem should read as a failure to the user.
        let nsError = error as NSError
        if nsError.domain == SUSparkleErrorDomain, nsError.code == Int(SUError.noUpdateError.rawValue) {
            Task { @MainActor in
                self.onChange?(.upToDate(currentVersion: Self.currentVersion))
            }
        } else {
            report(.failure(from: error))
        }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let nsError = error as NSError
        // A user-cancelled check is not a failure worth surfacing.
        guard !(nsError.domain == SUSparkleErrorDomain
                && nsError.code == Int(SUError.installationCanceledError.rawValue)) else { return }
        report(.failure(from: error))
    }
}

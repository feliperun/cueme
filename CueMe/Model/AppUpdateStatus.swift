import Foundation

/// Why an update check could not answer. Kept coarse on purpose: the updater's
/// own errors embed the feed URL and local cache paths, which must never reach
/// the user (see the privacy rules in AGENTS.md).
enum UpdateFailureReason: CaseIterable, Equatable {
    case offline
    case feedUnavailable
    case unknown
}

/// Observable outcome of a Sparkle update check, expressed without any Sparkle
/// type so it can be unit-tested and rendered while the updater is idle (or,
/// under UI testing, never started at all).
enum AppUpdateStatus: Equatable {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case available(version: String)
    case failed(reason: UpdateFailureReason)

    /// One line the user can read anywhere the update state is surfaced.
    var summary: String {
        switch self {
        case .idle: return "Buscar atualizações…"
        case .checking: return "Procurando atualizações…"
        case .upToDate(let version): return "CueMe \(version) é a versão mais recente"
        case .available(let version): return "Atualização disponível: \(version)"
        case .failed(.offline): return "Sem conexão para verificar atualizações"
        case .failed(.feedUnavailable): return "Nenhuma atualização publicada ainda"
        case .failed(.unknown): return "Não foi possível verificar atualizações"
        }
    }

    /// A check is in flight.
    var isBusy: Bool { self == .checking }

    /// There is something for the user to install.
    var isActionable: Bool {
        if case .available = self { return true }
        return false
    }

    var symbol: String {
        switch self {
        case .idle: return "arrow.triangle.2.circlepath"
        case .checking: return "arrow.triangle.2.circlepath"
        case .upToDate: return "checkmark.seal.fill"
        case .available: return "arrow.down.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    /// Classifies an updater error into a reason with a safe explanation.
    static func failure(from error: Error) -> AppUpdateStatus {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return .failed(reason: .unknown) }
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorCannotFindHost,
             NSURLErrorTimedOut:
            return .failed(reason: .offline)
        case NSURLErrorFileDoesNotExist,
             NSURLErrorResourceUnavailable,
             NSURLErrorBadServerResponse:
            return .failed(reason: .feedUnavailable)
        default:
            return .failed(reason: .unknown)
        }
    }
}

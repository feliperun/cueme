import Foundation

/// The actor string written into every document's `generated.by`, following
/// OKF's actor convention for agents and tools: `<producer>/<version>`.
/// Injectable so a golden-file test can pin it.
enum CueMeProducer {
    static var current: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "cueme/\(version ?? "dev")"
    }
}

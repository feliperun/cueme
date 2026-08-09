import Foundation

/// Finds a note's recordings, hands them to the player, and computes the
/// waveform envelope off the main actor. Split out of `SessionWorkspaceView`
/// so the workspace does not also know how audio is located and analysed.
@Observable
final class WaveformLoader {
    private(set) var envelope: [Float] = []
    private(set) var isLoading = false

    @MainActor
    func load(for record: MemoryNote, into player: MeetingPlayer) async {
        player.teardown()
        envelope = []
        let selfURL = MeetingRecording.selfURL(for: record)
        let otherURL = MeetingRecording.otherURL(for: record)
        player.load(selfURL: selfURL, otherURL: otherURL)
        guard player.isReady else {
            isLoading = false
            return
        }
        isLoading = true
        envelope = await Task.detached(priority: .userInitiated) {
            WaveformGenerator.envelope(selfURL: selfURL, otherURL: otherURL, buckets: 300)
        }.value
        isLoading = false
    }
}

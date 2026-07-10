import AVFoundation

/// Buffer de áudio taggeado com a origem (locutor conhecido por origem).
struct AudioChunk: @unchecked Sendable {
    let source: Speaker
    let buffer: AVAudioPCMBuffer
}

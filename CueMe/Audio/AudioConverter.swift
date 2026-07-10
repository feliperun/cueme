import AVFoundation
import CoreMedia

/// Converte buffers de qualquer formato de device para o formato alvo (o exigido
/// pelo SpeechTranscriber). Um conversor por par (inputFormat -> outputFormat).
final class AudioConverter {
    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var lastInputFormat: AVAudioFormat?

    init(outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
    }

    /// Converte um `AVAudioPCMBuffer` para o formato alvo. Recria o `AVAudioConverter`
    /// se o formato de entrada mudar. Retorna nil em falha.
    func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let inFormat = input.format
        if inFormat == outputFormat {
            return input
        }

        if converter == nil || lastInputFormat != inFormat {
            converter = AVAudioConverter(from: inFormat, to: outputFormat)
            lastInputFormat = inFormat
        }
        guard let converter else { return nil }

        // Capacidade de saída proporcional à razão de sample rates (+ folga).
        let ratio = outputFormat.sampleRate / inFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio + 1024)
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return input
        }

        if status == .error || error != nil { return nil }
        if output.frameLength == 0 { return nil }
        return output
    }

    /// Converte um `CMSampleBuffer` (ScreenCaptureKit) para `AVAudioPCMBuffer` no
    /// formato alvo. Passa pelo formato nativo do sample buffer primeiro.
    func convert(sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let pcm = AudioConverter.pcmBuffer(from: sampleBuffer) else { return nil }
        return convert(pcm)
    }

    /// Extrai um `AVAudioPCMBuffer` de um `CMSampleBuffer` de áudio.
    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
        else { return nil }

        var asbd = asbdPtr.pointee
        guard let format = AVAudioFormat(streamDescription: &asbd) else { return nil }

        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return nil }
        buffer.frameLength = frames

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else { return nil }
        return buffer
    }
}

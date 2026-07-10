import Foundation
import Translation

/// Fila de tradução (Sendable). O `.translationTask` entrega a `TranslationSession`
/// (não-Sendable) via parâmetro `sending` para `run(session:)` — a session é
/// transferida pra região deste método e nunca cruza pro MainActor.
final class TranslationPipe: @unchecked Sendable {
    struct Job: Sendable { let id: UUID; let text: String }

    /// (lineID, tradução) — o AppModel injeta um sink que salta pro MainActor.
    var onResult: (@Sendable (UUID, String) -> Void)?

    private let lock = NSLock()
    private var cont: AsyncStream<Job>.Continuation?
    private var _stream: AsyncStream<Job>

    init() {
        var c: AsyncStream<Job>.Continuation!
        _stream = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { c = $0 }
        cont = c
    }

    /// Stream atual (Sendable) para iterar dentro do `.translationTask`.
    var stream: AsyncStream<Job> {
        lock.lock(); defer { lock.unlock() }
        return _stream
    }

    /// Novo stream por sessão (o `.translationTask` re-dispara quando a config muda).
    func reset() {
        lock.lock(); defer { lock.unlock() }
        cont?.finish()
        var c: AsyncStream<Job>.Continuation!
        _stream = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { c = $0 }
        cont = c
    }

    func finish() {
        lock.lock(); defer { lock.unlock() }
        cont?.finish()
    }

    func enqueue(id: UUID, text: String) {
        lock.lock(); let c = cont; lock.unlock()
        c?.yield(Job(id: id, text: text))
    }

    func emit(_ id: UUID, _ text: String) {
        onResult?(id, text)
    }

    /// Loop consumidor. A `TranslationSession` da Apple não é Sendable e é usada
    /// só aqui, de forma serial (um translate por vez, main apenas aguarda), então
    /// marcamos como nonisolated(unsafe) — seguro neste uso confinado.
    func run(session: TranslationSession) async {
        nonisolated(unsafe) let s = session
        try? await s.prepareTranslation()
        for await job in stream {
            if let response = try? await s.translate(job.text) {
                emit(job.id, response.targetText)
            }
        }
    }
}

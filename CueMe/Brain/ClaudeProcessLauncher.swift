import Foundation

/// Spawns the Claude CLI as a plain-text streaming process, isolated from the
/// user's own environment. Split out of `ClaudeSession`, which manages the turn
/// queue over an already-running process.
///
/// **Do not relax the isolation here.** The CLI runs from an empty temporary
/// working directory with hooks, tools, MCP servers, plugins and slash commands
/// all disabled. Without that it picks up the user's own project context —
/// their `CLAUDE.md`, their skills — and the coach fabricates "experience" from
/// it. That happened once. See ADR 0005 and ADR 0008.
struct ClaudeProcessLauncher {
    let cliPath: String
    let model: String
    let system: String

    private let shell = "/bin/zsh"

    struct Launched {
        let process: Process
        let stdin: FileHandle
        let stdout: FileHandle
        let stderr: FileHandle
    }

    func launch() throws -> Launched {
        let script = #"exec "$LC_CLAUDE" -p --model "$LC_MODEL" --system-prompt "$LC_SYS" --input-format stream-json --output-format stream-json --include-partial-messages --verbose --tools "" --strict-mcp-config --mcp-config '{"mcpServers":{}}' --disable-slash-commands --no-chrome --no-session-persistence --setting-sources project,local --settings "$LC_SETTINGS""#

        var env = ProcessInfo.processInfo.environment
        env["LC_CLAUDE"] = cliPath
        env["LC_MODEL"] = model
        env["LC_SYS"] = system
        env["LC_SETTINGS"] = #"{"disableAllHooks":true}"#

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-lc", script]
        proc.environment = env
        // cwd isolado + zero tools/MCP/plugins/user settings: evita carregar contexto
        // pessoal e reduz drasticamente tokens/latência do processo de texto puro.
        let isolated = FileManager.default.temporaryDirectory.appendingPathComponent("CueMeCLI", isDirectory: true)
        try? FileManager.default.createDirectory(at: isolated, withIntermediateDirectories: true)
        proc.currentDirectoryURL = isolated

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        try proc.run()

        return Launched(
            process: proc,
            stdin: inPipe.fileHandleForWriting,
            stdout: outPipe.fileHandleForReading,
            stderr: errPipe.fileHandleForReading
        )
    }
}

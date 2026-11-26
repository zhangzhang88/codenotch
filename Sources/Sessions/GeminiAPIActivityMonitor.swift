import Combine
import Foundation

/// What the `gemini-api` ring shows as running.
///
/// Three tools spend the same API key and each records a turn in flight in its
/// own way, so the monitor is one timer over three readers rather than three
/// monitors sharing an id: `GeminiCLIActivity` on the chat files' modification
/// dates, `OpenCodeGeminiActivity` on an assistant message with no
/// `time.completed`, `HermesGeminiActivity` on an open session's lease.
///
/// The order is fixed and matches the provider's tooltip rows. Sessions are
/// drawn in the order they arrive, so concatenating by whichever reader
/// answered first would reshuffle the ring every couple of seconds.
///
/// None of the three writes a "waiting for you" marker to disk, so every
/// session here is `.busy` or absent, the way Cursor and Antigravity report
/// rather than the way Claude does.
final class GeminiAPIActivityMonitor: AgentActivityMonitor {
    @Published private(set) var sessions: [AgentSession] = []
    var sessionsPublisher: AnyPublisher<[AgentSession], Never> { $sessions.eraseToAnyPublisher() }

    private let geminiRoot: URL
    private let opencodeDatabase: URL
    private let hermesDatabase: URL
    private let interval: TimeInterval
    /// How recently a source must have been touched to count as live. Generous,
    /// because a model can think for a while between two lines.
    private let staleAfter: TimeInterval
    private let queue = DispatchQueue(label: "com.vinz.codenotch.gemini-api-activity", qos: .utility)
    private var timer: Timer?
    private var isPolling = false
    private var generation: UInt = 0

    init(geminiRoot: URL = GeminiCLIUsage.sessionsRoot,
         opencodeDatabase: URL = OpenCodeGeminiActivity.database,
         hermesDatabase: URL = HermesGeminiUsage.database,
         interval: TimeInterval = 2,
         staleAfter: TimeInterval = 45) {
        self.geminiRoot = geminiRoot
        self.opencodeDatabase = opencodeDatabase
        self.hermesDatabase = hermesDatabase
        self.interval = interval
        self.staleAfter = staleAfter
    }

    func start() {
        stop()
        generation &+= 1
        poll()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        generation &+= 1
        isPolling = false
    }

    private func poll() {
        guard !isPolling else { return }
        isPolling = true
        let gen = generation
        let geminiRoot = self.geminiRoot
        let opencodeDatabase = self.opencodeDatabase
        let hermesDatabase = self.hermesDatabase
        let staleAfter = self.staleAfter
        queue.async { [weak self] in
            let found = Self.read(
                geminiRoot: geminiRoot,
                opencodeDatabase: opencodeDatabase,
                hermesDatabase: hermesDatabase,
                staleAfter: staleAfter
            )
            DispatchQueue.main.async {
                guard let self, self.generation == gen else { return }
                self.isPolling = false
                guard found != self.sessions else { return }
                self.sessions = found
            }
        }
    }

    static func read(
        geminiRoot: URL,
        opencodeDatabase: URL,
        hermesDatabase: URL,
        staleAfter: TimeInterval,
        now: Date = Date()
    ) -> [AgentSession] {
        GeminiCLIActivity.read(root: geminiRoot, staleAfter: staleAfter, now: now)
            + OpenCodeGeminiActivity.read(
                database: opencodeDatabase, staleAfter: staleAfter, now: now)
            + HermesGeminiActivity.read(
                database: hermesDatabase, staleAfter: staleAfter, now: now)
    }
}

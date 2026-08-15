import Foundation

@MainActor
final class MonitorViewModel: ObservableObject {
    @Published private(set) var snapshot = ProcessSnapshot(processes: [], cpuTotal: 0, memTotal: 0, sessionCount: 0)
    @Published private(set) var usageResult: UsageBlockResult = .unavailable

    private let processMonitor = ProcessMonitor()
    private let usageFetcher = UsageBlockFetcher()
    private let sessionStateTracker = SessionStateTracker()
    let overloadSettings = OverloadSettings()
    private var processTimer: Timer?
    private var usageTimer: Timer?
    private var isPolling = false
    private var isRefreshingProcesses = false
    private var isRefreshingUsage = false

    /// Starts the polling loops. Kept out of `init` so constructing the view model has no
    /// side effects (no shell-outs, no timers); the app calls this once at launch.
    /// Idempotent, so a repeated trigger cannot start a second pair of timers.
    func startPolling() {
        guard !isPolling else { return }
        isPolling = true

        refreshProcesses()
        refreshUsage()
        processTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshProcesses() }
        }
        usageTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshUsage() }
        }
    }

    deinit {
        processTimer?.invalidate()
        usageTimer?.invalidate()
    }

    /// A full `ps aux` + per-process `lsof` sweep can outlast the 2s tick. Skipping
    /// overlapping refreshes keeps detached tasks from piling up on the cooperative
    /// thread pool, each blocked on synchronous `Process` I/O.
    private func refreshProcesses() {
        guard !isRefreshingProcesses else { return }
        isRefreshingProcesses = true

        let monitor = processMonitor
        let tracker = sessionStateTracker
        let basis = overloadSettings.basis
        Task.detached { [weak self] in
            let rawSnapshot = monitor.snapshot()
            let now = Date()
            guard let self else { return }
            await MainActor.run {
                let states = tracker.states(for: rawSnapshot, now: now, basis: basis)
                let processes = rawSnapshot.processes.map { process -> ClaudeProcess in
                    var updated = process
                    updated.state = states[process.pid] ?? .idle
                    return updated
                }
                let result = ProcessSnapshot(
                    processes: processes,
                    cpuTotal: rawSnapshot.cpuTotal,
                    memTotal: rawSnapshot.memTotal,
                    sessionCount: rawSnapshot.sessionCount
                )
                if result != self.snapshot { self.snapshot = result }
                self.isRefreshingProcesses = false
            }
        }
    }

    /// The `npx ccusage` shell-out can outlast the 30s tick (or hang on a slow network);
    /// skipping overlapping fetches avoids stacking `node` processes on top of a stuck one.
    private func refreshUsage() {
        guard !isRefreshingUsage else { return }
        isRefreshingUsage = true

        let fetcher = usageFetcher
        Task.detached { [weak self] in
            let result = fetcher.fetch()
            guard let self else { return }
            await MainActor.run {
                self.usageResult = result
                self.isRefreshingUsage = false
            }
        }
    }
}

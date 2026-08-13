import Foundation

@MainActor
final class MonitorViewModel: ObservableObject {
    @Published private(set) var snapshot = ProcessSnapshot(processes: [], cpuTotal: 0, memTotal: 0, sessionCount: 0)
    @Published private(set) var usageResult: UsageBlockResult = .unavailable

    private let processMonitor = ProcessMonitor()
    private let usageFetcher = UsageBlockFetcher()
    private var processTimer: Timer?
    private var usageTimer: Timer?

    init() {
        refreshProcesses()
        refreshUsage()
        processTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshProcesses()
        }
        usageTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshUsage()
        }
    }

    deinit {
        processTimer?.invalidate()
        usageTimer?.invalidate()
    }

    private func refreshProcesses() {
        let monitor = processMonitor
        Task.detached { [weak self] in
            let result = monitor.snapshot()
            await MainActor.run { self?.snapshot = result }
        }
    }

    private func refreshUsage() {
        let fetcher = usageFetcher
        Task.detached { [weak self] in
            let result = fetcher.fetch()
            await MainActor.run { self?.usageResult = result }
        }
    }
}

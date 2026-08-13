import Foundation

struct CcusageResponse: Decodable {
    let blocks: [CcusageBlock]
}

struct CcusageBlock: Decodable {
    let totalTokens: Int
    let costUSD: Double
    let isActive: Bool
    let burnRate: BurnRate?
    let projection: Projection?
    let startTime: String
    let endTime: String

    struct BurnRate: Decodable {
        let tokensPerMinute: Double
    }

    struct Projection: Decodable {
        let totalCost: Double
    }
}

struct UsageBlock: Equatable {
    let pct: Int
    let usedTokens: String
    let maxTokens: String
    let cost: Double
    let burnRate: String
    let estimatedCost: Double
    let resetIn: String
    let startLocal: String
    let endLocal: String
}

enum UsageBlockResult: Equatable {
    case active(UsageBlock)
    case noActiveBlock
    case unavailable
}

enum UsageBlockParsing {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ data: Data, now: Date) -> UsageBlockResult {
        guard let response = try? JSONDecoder().decode(CcusageResponse.self, from: data) else {
            return .unavailable
        }
        guard let active = response.blocks.first(where: { $0.isActive }) else {
            return .noActiveBlock
        }
        guard let endTime = isoFormatter.date(from: active.endTime),
              let startTime = isoFormatter.date(from: active.startTime) else {
            return .unavailable
        }

        let maxTokens = response.blocks.map { $0.totalTokens }.max() ?? active.totalTokens
        let pct = maxTokens > 0 ? Int(Double(active.totalTokens) * 100 / Double(maxTokens)) : 0
        let remainingMinutes = max(0, Int(endTime.timeIntervalSince(now) / 60))

        let local = DateFormatter()
        local.dateFormat = "HH:mm"

        return .active(UsageBlock(
            pct: pct,
            usedTokens: Formatting.tokens(active.totalTokens),
            maxTokens: Formatting.tokens(maxTokens),
            cost: active.costUSD,
            burnRate: Formatting.tokens(Int(active.burnRate?.tokensPerMinute ?? 0)),
            estimatedCost: active.projection?.totalCost ?? 0,
            resetIn: Formatting.duration(minutes: remainingMinutes),
            startLocal: local.string(from: startTime),
            endLocal: local.string(from: endTime)
        ))
    }
}

final class UsageBlockFetcher {
    private func run() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "npx --yes ccusage blocks --json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data.isEmpty ? nil : data
    }

    func fetch() -> UsageBlockResult {
        guard let data = run() else { return .unavailable }
        return UsageBlockParsing.parse(data, now: Date())
    }
}

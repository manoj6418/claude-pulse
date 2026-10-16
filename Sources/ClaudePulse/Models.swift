import Foundation

struct LimitWindow: Codable, Equatable {
    var usedPercentage: Double
    var resetsAt: Date
}

/// Plan usage limits as last reported to any session's status line.
struct LimitsSnapshot: Codable, Equatable {
    var fiveHour: LimitWindow?
    var sevenDay: LimitWindow?
    var capturedAt: Date
}

/// What the status line bridge saw for one session on its last run.
struct BridgeSession: Codable {
    var sessionId: String
    var sessionName: String?
    var cwd: String?
    var projectDir: String?
    var transcriptPath: String?
    var modelId: String?
    var modelName: String?
    var effort: String?
    var contextUsedPercentage: Double?
    var contextWindowSize: Int?
    var contextTokens: Int?
    var costUSD: Double?
    var linesAdded: Int?
    var linesRemoved: Int?
    var durationMs: Double?
    var version: String?
    var updatedAt: Date
}

enum HookState: String, Codable {
    case working
    case needsPermission = "needs_permission"
    case waitingInput = "waiting_input"
    case idle
    case compacting
}

/// What the hook bridge saw for one session on its last event.
struct HookStateRecord: Codable {
    var sessionId: String
    var state: HookState
    var message: String?
    var updatedAt: Date
    /// When the current (or last) turn began: the last UserPromptSubmit.
    var turnStartedAt: Date?
    /// Set on Stop: when the turn ended and the start of Claude's final reply.
    var finishedAt: Date?
    var finalReply: String?
}

/// One row of ~/.claude/sessions/<pid>.json, written by Claude Code itself.
struct RegistryEntry: Decodable {
    var pid: Int32
    var sessionId: String
    var cwd: String?
    var startedAt: Double?
    var kind: String?
    var entrypoint: String?
    var name: String?
    var status: String?
    var updatedAt: Double?
}

/// Last assistant turn read from a transcript.
struct TranscriptInfo {
    var modelId: String?
    var requestedModel: String?
    var effort: String?
    var contextTokens: Int?
    var outputTokens: Int?
    var gitBranch: String?
    var lastAssistantAt: Date?
}

enum ActivityState: Int, Comparable {
    case needsPermission = 0
    case waitingInput
    case working
    case compacting
    case idle

    static func < (lhs: ActivityState, rhs: ActivityState) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .needsPermission: return "Needs permission"
        case .waitingInput: return "Waiting for you"
        case .working: return "Working"
        case .compacting: return "Compacting"
        case .idle: return "Idle"
        }
    }

    var needsAttention: Bool { self == .needsPermission || self == .waitingInput }
}

struct SessionSummary: Identifiable {
    var id: String { sessionId }
    var pid: Int32
    var sessionId: String
    var name: String
    var cwd: String
    var startedAt: Date?
    var activity: ActivityState
    var attentionMessage: String?
    var modelId: String?
    var modelName: String
    var effort: String?
    var contextTokens: Int?
    var contextWindowSize: Int
    var contextPercentage: Double?
    var gitBranch: String?
    var costUSD: Double?
    var linesAdded: Int?
    var linesRemoved: Int?
    var lastActivity: Date?
    var transcriptPath: String?
    var entrypoint: String?
    var turnStartedAt: Date?
    var finishedAt: Date?
    var finalReply: String?

    var projectName: String { (cwd as NSString).lastPathComponent }
}

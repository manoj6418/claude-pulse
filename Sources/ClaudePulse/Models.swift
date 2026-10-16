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
    /// Session totals so far, for the daily ledger.
    var totalInputTokens: Int?
    var totalOutputTokens: Int?
    var updatedAt: Date
}

enum HookState: String, Codable {
    case working
    case needsPermission = "needs_permission"
    case waitingInput = "waiting_input"
    case idle
    case compacting
}

/// Your own pin, name and colour for a session.
struct SessionLabel: Codable, Equatable {
    var pinned = false
    var name: String?
    /// One of SessionLabel.colors.
    var color: String?

    static let colors = ["red", "orange", "yellow", "green", "blue", "purple"]
}

/// One tool call on the main thread, for the session's step history.
struct StepRecord: Codable, Identifiable {
    var id: String
    var text: String
    var startedAt: Date
    var endedAt: Date?
    var failed: Bool?
    /// First line of the error, e.g. "Exit code 1".
    var error: String?
    var interrupted: Bool?
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
    /// The tool running right now (PreToolUse → PostToolUse), e.g. "Running go test ./...".
    var currentStep: String?
    var currentStepStartedAt: Date?
    /// How many times this session compacted its context.
    var compactCount: Int?
    /// Last 10 main-thread tool calls, newest last.
    var steps: [StepRecord]?
    /// Background agents running now: agent_id → when it started.
    var agents: [String: Date]?
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
    /// Prompt cache on the last request: tokens read from cache vs. written to it.
    var cacheReadTokens: Int?
    var cacheWriteTokens: Int?
    var uncachedTokens: Int?
    /// 3600 when Claude Code used the 1-hour cache, 300 for 5 minutes; nil if unknown.
    var cacheTTL: TimeInterval?
}

/// How warm a session's prompt cache is.
struct CacheInfo {
    /// Share of the last request's input served from cache (0...1).
    var hitRate: Double
    /// When the cache expires if nothing new is sent (last reply + TTL).
    var warmUntil: Date?
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
        case .waitingInput: return "Your turn"
        case .working: return "Working"
        case .compacting: return "Compacting"
        case .idle: return "Idle"
        }
    }

    /// States a hook reported that stay until the session moves on.
    var needsAttention: Bool { self == .needsPermission || self == .waitingInput }
    /// Only a permission prompt blocks the session; "your turn" is the normal resting state.
    var isBlocking: Bool { self == .needsPermission }
}

/// A permission prompt waiting in a session, written by the PermissionRequest
/// hook while it waits for an answer from the panel or a notification.
struct PermissionRequestRecord: Codable, Identifiable {
    var id: String
    var sessionId: String
    var cwd: String?
    var toolName: String
    /// What the tool will do: the command, file path, URL, or a short input summary.
    var summary: String
    var detail: String?
    /// Claude Code offered a rule (e.g. "always allow this command"), so "Always allow" can apply it.
    var canAlwaysAllow: Bool
    var createdAt: Date
    var hookPid: Int32
}

enum PermissionDecision: String, Codable {
    case allow
    case alwaysAllow = "always_allow"
    case deny
}

struct PermissionResponse: Codable {
    var id: String
    var decision: PermissionDecision
}

/// One entry in the panel's Recent list.
struct RecentEvent: Codable, Identifiable {
    enum Kind: String, Codable {
        case finished
        case needsPermission
        case limit
    }

    var id = UUID()
    var kind: Kind
    var title: String
    var detail: String
    var sessionId: String?
    var pid: Int32?
    var at: Date
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
    var totalInputTokens: Int?
    var totalOutputTokens: Int?
    var linesAdded: Int?
    var linesRemoved: Int?
    var lastActivity: Date?
    var transcriptPath: String?
    var entrypoint: String?
    var turnStartedAt: Date?
    var finishedAt: Date?
    var finalReply: String?
    var permissionRequests: [PermissionRequestRecord] = []
    var currentStep: String?
    var currentStepStartedAt: Date?
    var compactCount: Int = 0
    var cache: CacheInfo?
    var git: GitState?
    var steps: [StepRecord] = []
    var runningAgents = 0

    /// The newest finished step failed (not counting ones you interrupted).
    var lastStepFailed: StepRecord? {
        guard let last = steps.last(where: { $0.endedAt != nil }), last.failed == true, last.interrupted != true else { return nil }
        return last
    }
    /// This session's share of all spend in the last hour (0...1), when there was any.
    var burnShare: Double?

    var projectName: String { (cwd as NSString).lastPathComponent }

    /// Working, no tool running, and nothing new for 10 minutes.
    func looksStuck(now: Date) -> Bool {
        guard activity == .working, currentStep == nil, let last = lastActivity else { return false }
        return now.timeIntervalSince(last) > 600
    }
}

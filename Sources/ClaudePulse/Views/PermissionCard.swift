import SwiftUI

/// A waiting permission prompt with Allow / Always allow / Deny. The same
/// prompt is open in the terminal; whichever is answered first wins.
struct PermissionCard: View {
    var request: PermissionRequestRecord
    var moreCount: Int
    /// The top prompt in the panel answers to ⌘↩ (Allow) and ⌘⌫ (Deny).
    var isPrimary = false
    var onAnswer: (PermissionDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "hand.raised.fill")
                Text("\(request.toolName) wants permission")
                    .fontWeight(.semibold)
                if moreCount > 0 {
                    Text("+\(moreCount) more").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.orange)

            // Zero-width spaces after "/" let long paths wrap instead of leaving a blank box.
            Text(request.summary.replacingOccurrences(of: "/", with: "/\u{200B}"))
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(4)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

            if let detail = request.detail, !detail.isEmpty, detail != request.summary {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                Button("Deny") { onAnswer(.deny) }
                    .shortcut(.delete, .command, when: isPrimary)
                    .help(isPrimary ? "Deny (⌘⌫)" : "Deny")
                Spacer()
                if request.canAlwaysAllow {
                    Button("Always allow") { onAnswer(.alwaysAllow) }
                        .help("Allow now and add Claude Code's suggested rule so it won't ask again")
                }
                Button("Allow") { onAnswer(.allow) }
                    .shortcut(.return, .command, when: isPrimary)
                    .help(isPrimary ? "Allow (⌘↩)" : "Allow")
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
            .controlSize(.small)
        }
    }
}

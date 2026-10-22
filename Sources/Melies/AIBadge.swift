import SwiftUI

/// Shown at the top of the editor while an AI app is editing through the MCP server, and a moment after,
/// so the changes that appear are never a surprise: who is acting and what it is doing.
struct AIBadge: View {
    @ObservedObject private var server = MCPServer.shared

    var body: some View {
        if server.showBadge {
            let who = server.clientName ?? L("ai.default_client")
            let what = (server.busyTool ?? server.lastTool ?? "").replacingOccurrences(of: "_", with: " ")
            HStack(spacing: 8) {
                if server.busyTool != nil {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Text(server.busyTool != nil ? L("ai.working", who) : L("ai.done", who))
                    .font(.system(size: 12, weight: .semibold))
                if !what.isEmpty {
                    Text(what).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
            .padding(.top, 10)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .allowsHitTesting(false)
        }
    }
}

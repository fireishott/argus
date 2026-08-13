import AppKit
import Security
import SwiftUI

@main
struct ArgusMenuBarApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            ArgusPopover(store: store)
        } label: {
            StatusLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

struct StatusLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        let provider = store.providers.first
        HStack(spacing: 4) {
            Image(systemName: "eye")
            Text(provider?.headline ?? "--")
                .monospacedDigit()
        }
        .task { await store.start() }
    }
}

struct ArgusPopover: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Argus", systemImage: "eye")
                    .font(.headline)
                Spacer()
                Text(store.lastUpdatedText)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }

            if let error = store.error {
                ContentUnavailableView("Argus is unavailable", systemImage: "wifi.exclamationmark", description: Text(error))
            } else if store.providers.isEmpty {
                ProgressView("Loading provider usage")
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ForEach(store.providers) { provider in
                    ProviderRow(provider: provider)
                }
            }

            Divider()
            Button("Open Dashboard") { store.openDashboard() }
                .disabled(store.dashboardURL == nil)
        }
        .padding(14)
        .frame(width: 380)
    }
}

struct ProviderRow: View {
    let provider: ProviderUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(provider.statusColor)
                    .frame(width: 8, height: 8)
                Text(provider.label).fontWeight(.semibold)
                Spacer()
                Text(provider.headline).monospacedDigit()
            }
            ForEach(provider.windows) { window in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(window.label).foregroundStyle(.secondary)
                        Spacer()
                        Text(window.remainingText).monospacedDigit()
                    }
                    ProgressView(value: window.progress)
                        .tint(window.tint)
                }
                .font(.caption)
            }
            if let balance = provider.balanceText {
                Text(balance).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(provider.accessibilitySummary)
    }
}

@MainActor
final class UsageStore: ObservableObject {
    @Published var providers: [ProviderUsage] = []
    @Published var error: String?
    @Published var dashboardURL: URL?
    @Published var lastUpdatedText = "Not updated"

    private let client = ArgusClient()
    private var refreshTask: Task<Void, Never>?

    deinit { refreshTask?.cancel() }

    func start() async {
        guard refreshTask == nil else { return }
        await refresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        do {
            let payload = try await client.snapshot()
            providers = payload.providers
            dashboardURL = payload.links.dashboardURL
            lastUpdatedText = "Updated now"
            error = nil
        } catch {
            self.error = "Check Argus URL and access token in Settings."
        }
    }

    func openDashboard() {
        if let dashboardURL { NSWorkspace.shared.open(dashboardURL) }
    }
}

struct ArgusClient {
    private let decoder = JSONDecoder()

    func snapshot() async throws -> SnapshotPayload {
        let endpoint = UserDefaults.standard.string(forKey: "argus.endpoint") ?? "http://127.0.0.1:8090/api/v1/snapshot"
        guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = Keychain.read(service: "Argus", account: "api-token"), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SnapshotPayload.self, from: data)
    }
}

struct SnapshotPayload: Decodable {
    let schemaVersion: Int
    let providers: [ProviderUsage]
    let links: Links

    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", providers, links }
    struct Links: Decodable { let dashboardURL: URL?; enum CodingKeys: String, CodingKey { case dashboardURL = "dashboard_url" } }
}

struct ProviderUsage: Decodable, Identifiable {
    let provider: String
    let label: String
    let status: String
    let windows: [UsageWindow]
    let balance: Balance?
    var id: String { provider }
    var headline: String { windows.first.map { $0.remainingText } ?? balanceText ?? "n/a" }
    var balanceText: String? { balance.map { "Balance: \($0.currency) \(String(format: "%.2f", $0.remaining))" } }
    var statusColor: Color { status == "active" ? .green : (status == "degraded" ? .orange : .secondary) }
    var accessibilitySummary: String { "\(label), \(headline), \(status)" }
}

struct UsageWindow: Decodable, Identifiable {
    let id: String
    let label: String
    let remainingPercent: Int?
    let resetAt: Date?
    var progress: Double { Double(remainingPercent ?? 0) / 100 }
    var remainingText: String { remainingPercent.map { "\($0)% left" } ?? "n/a" }
    var tint: Color { (remainingPercent ?? 100) <= 5 ? .red : ((remainingPercent ?? 100) <= 15 ? .orange : .green) }
    enum CodingKeys: String, CodingKey { case id, label, remainingPercent = "remaining_percent", resetAt = "reset_at" }
}

struct Balance: Decodable {
    let kind: String
    let remaining: Double
    let currency: String
}

enum Keychain {
    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

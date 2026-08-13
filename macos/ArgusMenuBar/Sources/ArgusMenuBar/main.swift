import AppKit
import Security
import SwiftUI

@main
struct ArgusMenuBarApp: App {
    @StateObject private var store = UsageStore()
    @StateObject private var preferences = ArgusPreferences()

    var body: some Scene {
        MenuBarExtra {
            ArgusPopover(store: store, preferences: preferences)
        } label: {
            StatusBarProviders(store: store, preferences: preferences)
        }
        .menuBarExtraStyle(.window)

        Settings {
            ArgusSettingsView(preferences: preferences)
        }
    }
}

// MARK: - Menu bar

struct StatusBarProviders: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var preferences: ArgusPreferences

    var body: some View {
        HStack(spacing: 7) {
            ForEach(preferences.orderedEnabledProviders(from: store.providers)) { provider in
                ProviderStatusChip(provider: provider, preferences: preferences)
            }
            if preferences.orderedEnabledProviders(from: store.providers).isEmpty {
                Image(systemName: "eye.slash")
            }
        }
        .task { await store.start(refreshSeconds: preferences.refreshSeconds) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Argus provider usage")
    }
}

struct ProviderStatusChip: View {
    let provider: ProviderUsage
    @ObservedObject var preferences: ArgusPreferences

    var body: some View {
        let color = preferences.color(for: provider.remainingPercent)
        Group {
            switch preferences.displayMode {
            case .usageBar:
                HStack(spacing: 3) {
                    ProviderMark(provider: provider, mode: preferences.iconMode).foregroundStyle(color)
                    UsageBar(remainingPercent: provider.remainingPercent, preferences: preferences)
                }
            case .fuelGauge:
                FuelGauge(provider: provider, preferences: preferences)
            default:
                HStack(spacing: 3) {
                    ProviderMark(provider: provider, mode: preferences.iconMode).foregroundStyle(color)
                    if preferences.displayMode != .iconOnly {
                        Text(preferences.valueText(for: provider)).monospacedDigit().foregroundStyle(color)
                    }
                }
            }
        }
        .help(provider.tooltip)
        .accessibilityLabel(provider.accessibilitySummary)
    }
}

struct UsageBar: View {
    let remainingPercent: Int?
    @ObservedObject var preferences: ArgusPreferences

    var body: some View {
        let used = Double(100 - (remainingPercent ?? 0)) / 100
        Capsule()
            .fill(.quaternary)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(preferences.usageGradient)
                        .frame(width: max(2, proxy.size.width * used))
                }
                .clipShape(Capsule())
            }
            .frame(width: 30, height: 7)
            .accessibilityLabel("\(Int(used * 100)) percent used")
    }
}

struct FuelGauge: View {
    let provider: ProviderUsage
    @ObservedObject var preferences: ArgusPreferences

    var body: some View {
        let used = Double(100 - (provider.remainingPercent ?? 0)) / 100
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.quaternary)
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(preferences.usageGradient)
                    .frame(width: proxy.size.width * used)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            ProviderMark(provider: provider, mode: preferences.iconMode)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.primary)
        }
        .frame(width: 24, height: 15)
        .accessibilityLabel("\(provider.label), \(Int(used * 100)) percent used")
    }
}

// Vector-drawn brand marks are intentionally monochrome in the menu bar.
// This keeps them readable under any macOS menu-bar appearance and lets the
// selected quota color carry the only urgent signal.
struct ProviderMark: View {
    let provider: ProviderUsage
    let mode: IconMode

    var body: some View {
        switch mode {
        case .brandMark:
            brandVector
                .frame(width: 14, height: 14)
        case .monogram:
            Text(provider.monogram)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .frame(minWidth: 14)
        case .systemSymbol:
            Image(systemName: provider.symbolName)
                .font(.system(size: 12, weight: .semibold))
        }
    }

    @ViewBuilder private var brandVector: some View {
        switch provider.provider {
        case "claude":
            Image(systemName: "sparkle")
        case "antigravity":
            Image(systemName: "diamond")
        case "codex":
            Image(systemName: "hexagon")
        case "deepseek":
            Image(systemName: "wave.3.right")
        case "minimax":
            Image(systemName: "bolt")
        case "openrouter":
            Image(systemName: "arrow.triangle.branch")
        case "opencode-go":
            Image(systemName: "chevron.left.forwardslash.chevron.right")
        case "xiaomi-tokenplan":
            Image(systemName: "square.grid.2x2")
        default:
            Image(systemName: "cpu")
        }
    }
}

// MARK: - Popover

struct ArgusPopover: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var preferences: ArgusPreferences

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
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Argus settings")
            }

            if let error = store.error {
                ContentUnavailableView("Argus is unavailable", systemImage: "wifi.exclamationmark", description: Text(error))
            } else if store.providers.isEmpty {
                ProgressView("Loading provider usage")
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ForEach(preferences.orderedEnabledProviders(from: store.providers)) { provider in
                    ProviderRow(provider: provider, preferences: preferences)
                }
            }

            Divider()
            HStack {
                SettingsLink("Settings")
                Spacer()
                Button("Open Dashboard") { store.openDashboard() }
                    .disabled(store.dashboardURL == nil)
            }
        }
        .padding(14)
        .frame(width: 390)
    }
}

struct ProviderRow: View {
    let provider: ProviderUsage
    @ObservedObject var preferences: ArgusPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ProviderMark(provider: provider, mode: preferences.iconMode)
                    .foregroundStyle(preferences.color(for: provider.remainingPercent))
                    .frame(width: 16)
                Text(provider.label).fontWeight(.semibold)
                Spacer()
                Text(preferences.valueText(for: provider)).monospacedDigit()
            }
            ForEach(provider.windows) { window in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(window.label).foregroundStyle(.secondary)
                        Spacer()
                        Text(window.remainingText).monospacedDigit()
                    }
                    ProgressView(value: window.progress)
                        .tint(preferences.color(for: window.remainingPercent))
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

// MARK: - Preferences

enum IconMode: String, Codable, CaseIterable, Identifiable {
    case brandMark, monogram, systemSymbol
    var id: String { rawValue }
    var label: String {
        switch self {
        case .brandMark: "Brand vector"
        case .monogram: "Monogram"
        case .systemSymbol: "System symbol"
        }
    }
}

enum DisplayMode: String, Codable, CaseIterable, Identifiable {
    case remainingPercent, balance, usageBar, fuelGauge, iconOnly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .remainingPercent: "Remaining %"
        case .balance: "Balance when available"
        case .usageBar: "Usage bar"
        case .fuelGauge: "Fuel gauge"
        case .iconOnly: "Icon only"
        }
    }
}

struct ProviderPreference: Codable, Identifiable {
    let id: String
    var enabled: Bool
}

struct PersistedPreferences: Codable {
    var iconMode: IconMode = .brandMark
    var displayMode: DisplayMode = .remainingPercent
    var refreshSeconds: Int = 60
    var warningThreshold: Int = 15
    var criticalThreshold: Int = 5
    var healthyColor: StoredColor = .green
    var warningColor: StoredColor = .yellow
    var criticalColor: StoredColor = .red
    var unavailableColor: StoredColor = .white
    var providerOrder: [ProviderPreference] = []
}

enum StoredColor: String, Codable, CaseIterable, Identifiable {
    case green, yellow, red, white, blue, orange
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        case .white: .white
        case .blue: .blue
        case .orange: .orange
        }
    }
    var label: String { rawValue.capitalized }
}

@MainActor
final class ArgusPreferences: ObservableObject {
    @Published private(set) var values: PersistedPreferences
    private let storageKey = "argus.preferences.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(PersistedPreferences.self, from: data) {
            values = decoded
        } else {
            values = PersistedPreferences()
        }
    }

    var iconMode: IconMode { values.iconMode }
    var displayMode: DisplayMode { values.displayMode }
    var refreshSeconds: Int { values.refreshSeconds }

    func update(_ mutate: (inout PersistedPreferences) -> Void) {
        mutate(&values)
        save()
    }

    func orderedEnabledProviders(from providers: [ProviderUsage]) -> [ProviderUsage] {
        sync(providers)
        let indexes = Dictionary(uniqueKeysWithValues: values.providerOrder.enumerated().map { ($0.element.id, $0.offset) })
        let enabled = Set(values.providerOrder.filter(\.enabled).map(\.id))
        return providers
            .filter { enabled.contains($0.provider) }
            .sorted { indexes[$0.provider, default: .max] < indexes[$1.provider, default: .max] }
    }

    func sync(_ providers: [ProviderUsage]) {
        let known = Set(values.providerOrder.map(\.id))
        let additions = providers.filter { !known.contains($0.provider) }.map { ProviderPreference(id: $0.provider, enabled: true) }
        guard !additions.isEmpty else { return }
        values.providerOrder.append(contentsOf: additions)
        save()
    }

    func color(for remainingPercent: Int?) -> Color {
        guard let remainingPercent else { return values.unavailableColor.color }
        if remainingPercent <= values.criticalThreshold { return values.criticalColor.color }
        if remainingPercent <= values.warningThreshold { return values.warningColor.color }
        return values.healthyColor.color
    }

    // Gradient describes consumption, not remaining balance: green at a new
    // window, yellow near warning, red when the bucket is exhausted.
    var usageGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: values.healthyColor.color, location: 0),
                .init(color: values.warningColor.color, location: Double(100 - values.warningThreshold) / 100),
                .init(color: values.criticalColor.color, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    func valueText(for provider: ProviderUsage) -> String {
        switch values.displayMode {
        case .remainingPercent: provider.remainingPercent.map { "\($0)%" } ?? "n/a"
        case .balance: provider.balanceShortText ?? provider.remainingPercent.map { "\($0)%" } ?? "n/a"
        case .usageBar, .fuelGauge, .iconOnly: ""
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        objectWillChange.send()
    }
}

struct ArgusSettingsView: View {
    @ObservedObject var preferences: ArgusPreferences
    @State private var providerNames: [String: String] = [:]

    var body: some View {
        TabView {
            displayTab.tabItem { Label("Display", systemImage: "menubar.rectangle") }
            ProviderConfigurationView()
                .tabItem { Label("Configuration", systemImage: "key.horizontal") }
        }
        .padding()
        .frame(width: 560, height: 620)
    }

    private var displayTab: some View {
        Form {
            Section("Menu bar") {
                Picker("Provider mark", selection: binding(\.iconMode)) { ForEach(IconMode.allCases) { Text($0.label).tag($0) } }
                Picker("Value next to mark", selection: binding(\.displayMode)) { ForEach(DisplayMode.allCases) { Text($0.label).tag($0) } }
                Picker("Refresh", selection: binding(\.refreshSeconds)) {
                    Text("30 seconds").tag(30); Text("60 seconds").tag(60); Text("2 minutes").tag(120); Text("5 minutes").tag(300)
                }
            }
            Section("Colors by remaining usage") {
                Picker("Healthy", selection: binding(\.healthyColor)) { ForEach(StoredColor.allCases) { Text($0.label).tag($0) } }
                Picker("Warning", selection: binding(\.warningColor)) { ForEach(StoredColor.allCases) { Text($0.label).tag($0) } }
                Picker("Critical", selection: binding(\.criticalColor)) { ForEach(StoredColor.allCases) { Text($0.label).tag($0) } }
                Picker("Unavailable", selection: binding(\.unavailableColor)) { ForEach(StoredColor.allCases) { Text($0.label).tag($0) } }
                Stepper("Warning at \(preferences.values.warningThreshold)% or below", value: binding(\.warningThreshold), in: 1...99)
                Stepper("Critical at \(preferences.values.criticalThreshold)% or below", value: binding(\.criticalThreshold), in: 0...preferences.values.warningThreshold)
            }
            Section("Providers in menu bar") {
                Text("Toggle providers on or off, then drag to set their menu-bar order.").font(.caption).foregroundStyle(.secondary)
                List {
                    ForEach(preferences.values.providerOrder) { item in
                        Toggle(isOn: providerEnabledBinding(item.id)) { Text(providerNames[item.id] ?? item.id) }
                    }.onMove(perform: moveProviders)
                }.frame(minHeight: 160)
            }
        }.formStyle(.grouped)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<PersistedPreferences, T>) -> Binding<T> {
        Binding(get: { preferences.values[keyPath: keyPath] }, set: { value in preferences.update { $0[keyPath: keyPath] = value } })
    }
    private func providerEnabledBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { preferences.values.providerOrder.first(where: { $0.id == id })?.enabled ?? false }, set: { enabled in preferences.update { values in
            guard let index = values.providerOrder.firstIndex(where: { $0.id == id }) else { return }; values.providerOrder[index].enabled = enabled
        } })
    }
    private func moveProviders(from offsets: IndexSet, to destination: Int) { preferences.update { $0.providerOrder.move(fromOffsets: offsets, toOffset: destination) } }
}

struct ProviderConfigurationView: View {
    @State private var selectedID = ProviderCatalog.entries.first!.id
    @State private var credential = ""
    @State private var status = ""
    @State private var isVerifying = false

    private var provider: ProviderDefinition { ProviderCatalog.byID[selectedID] ?? ProviderCatalog.entries[0] }

    var body: some View {
        Form {
            Section("Add or update provider") {
                Picker("Provider", selection: $selectedID) {
                    ForEach(ProviderCatalog.entries) { item in
                        Text(item.label).tag(item.id)
                    }
                }
                .onChange(of: selectedID) { _, _ in loadStoredCredential() }

                LabeledContent("Authentication", value: provider.auth.label)
                if !provider.models.isEmpty {
                    LabeledContent("Models", value: provider.models.joined(separator: ", "))
                        .lineLimit(2)
                }
            }

            Section(provider.auth == .apiKey ? "API key" : "OAuth") {
                if provider.auth == .apiKey {
                    SecureField(provider.placeholder, text: $credential)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button(isVerifying ? "Verifying..." : "Verify and Save") { verifyAndSave() }
                            .disabled(credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifying)
                        if Keychain.read(service: "Argus.Provider", account: provider.id) != nil {
                            Button("Remove", role: .destructive) { Keychain.remove(service: "Argus.Provider", account: provider.id); credential = ""; status = "Removed from this Mac." }
                        }
                    }
                    Text("Saved only in this Mac's Keychain. Argus never displays it again.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(provider.oauthDetail).foregroundStyle(.secondary)
                    Button("Connect with \(provider.label)") { status = "OAuth setup for \(provider.label) is not available in this alpha yet." }
                        .disabled(true)
                    Text("Disabled until Argus implements this provider's documented callback exchange. No fake sign-in flow.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !status.isEmpty { Text(status).font(.caption).foregroundStyle(status.hasPrefix("Connected") ? .green : .secondary) }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadStoredCredential)
    }

    private func loadStoredCredential() { credential = Keychain.read(service: "Argus.Provider", account: provider.id) ?? ""; status = "" }
    private func verifyAndSave() {
        let value = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        isVerifying = true; status = "Verifying \(provider.label)..."
        Task {
            let result = await ProviderVerifier.verify(provider, credential: value)
            isVerifying = false
            switch result {
            case .success(let message):
                Keychain.save(service: "Argus.Provider", account: provider.id, value: value)
                status = "Connected. \(message)"
            case .failure(let error): status = "Could not verify: \(error.localizedDescription)"
            }
        }
    }
}

enum ProviderAuth: String { case apiKey, oauth
    var label: String { self == .apiKey ? "API key" : "OAuth" }
}
struct ProviderDefinition: Identifiable {
    let id: String; let label: String; let auth: ProviderAuth; let models: [String]; let placeholder: String; let oauthDetail: String
}
enum ProviderCatalog {
    static let entries: [ProviderDefinition] = [
        .init(id: "openrouter", label: "OpenRouter", auth: .apiKey, models: ["All routed models"], placeholder: "sk-or-...", oauthDetail: ""),
        .init(id: "deepseek", label: "DeepSeek", auth: .apiKey, models: ["DeepSeek Chat", "DeepSeek Reasoner"], placeholder: "sk-...", oauthDetail: ""),
        .init(id: "minimax", label: "MiniMax", auth: .apiKey, models: ["MiniMax-M2.5", "MiniMax-M3"], placeholder: "sk-cp...", oauthDetail: ""),
        .init(id: "opencode-go", label: "OpenCode Go", auth: .apiKey, models: ["Go plan"], placeholder: "API key", oauthDetail: ""),
        .init(id: "claude", label: "Claude", auth: .oauth, models: ["Claude Code plan"], placeholder: "", oauthDetail: "Claude quota uses an OAuth access token."),
        .init(id: "codex", label: "Codex", auth: .oauth, models: ["Codex"], placeholder: "", oauthDetail: "Codex account usage requires an OAuth flow."),
        .init(id: "gemini", label: "Gemini", auth: .oauth, models: ["Gemini 3.6", "Gemini 2.5"], placeholder: "", oauthDetail: "Gemini supports a documented desktop OAuth flow."),
        .init(id: "mimo", label: "MiMo", auth: .oauth, models: ["MiMo V2.5"], placeholder: "", oauthDetail: "MiMo usage is behind an account session. Its connector is not ready yet."),
    ]
    static let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
}

enum ProviderVerifier {
    static func verify(_ provider: ProviderDefinition, credential: String) async -> Result<String, Error> {
        do {
            let url: URL
            var request: URLRequest
            switch provider.id {
            case "openrouter":
                url = URL(string: "https://openrouter.ai/api/v1/auth/key")!; request = URLRequest(url: url); request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
            case "deepseek":
                url = URL(string: "https://api.deepseek.com/user/balance")!; request = URLRequest(url: url); request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
            case "minimax":
                url = URL(string: "https://www.minimax.io/v1/token_plan/remains")!; request = URLRequest(url: url); request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
            case "opencode-go":
                url = URL(string: "https://opencode.ai/zen/go/v1/usage")!; request = URLRequest(url: url); request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
            default: throw URLError(.unsupportedURL)
            }
            request.timeoutInterval = 15
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard (200...299).contains(http.statusCode) else { throw NSError(domain: "Argus.Provider", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Provider returned HTTP \(http.statusCode)."] ) }
            return .success("\(provider.label) verified.")
        } catch { return .failure(error) }
    }
}

// MARK: - Data

@MainActor
final class UsageStore: ObservableObject {
    @Published var providers: [ProviderUsage] = []
    @Published var error: String?
    @Published var dashboardURL: URL?
    @Published var lastUpdatedText = "Not updated"
    private let client = ArgusClient()
    private var refreshTask: Task<Void, Never>?

    deinit { refreshTask?.cancel() }

    func start(refreshSeconds: Int) async {
        guard refreshTask == nil else { return }
        await refresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(refreshSeconds))
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

    func openDashboard() { if let dashboardURL { NSWorkspace.shared.open(dashboardURL) } }
}

struct ArgusClient {
    private let decoder = JSONDecoder()
    func snapshot() async throws -> SnapshotPayload {
        let endpoint = UserDefaults.standard.string(forKey: "argus.endpoint") ?? "http://127.0.0.1:8090/api/v1/snapshot"
        guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = Keychain.read(service: "Argus", account: "api-token"), !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
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
    var remainingPercent: Int? { windows.first(where: { $0.id == "5h" })?.remainingPercent ?? windows.first?.remainingPercent }
    var balanceText: String? { balance.map { "Balance: \($0.currency) \(String(format: "%.2f", $0.remaining))" } }
    var balanceShortText: String? { balance.map { "\($0.currency)\(String(format: "%.2f", $0.remaining))" } }
    var monogram: String { label.split(separator: " ").prefix(2).map { String($0.prefix(1)) }.joined().uppercased() }
    var symbolName: String { "cpu" }
    var tooltip: String { "\(label): \(windows.map { "\($0.label) \($0.remainingText)" }.joined(separator: ", "))" }
    var accessibilitySummary: String { "\(label), \(tooltip), \(status)" }
}

struct UsageWindow: Decodable, Identifiable {
    let id: String
    let label: String
    let remainingPercent: Int?
    let resetAt: Date?
    var progress: Double { Double(remainingPercent ?? 0) / 100 }
    var remainingText: String { remainingPercent.map { "\($0)% left" } ?? "n/a" }
    enum CodingKeys: String, CodingKey { case id, label, remainingPercent = "remaining_percent", resetAt = "reset_at" }
}

struct Balance: Decodable { let kind: String; let remaining: Double; let currency: String }

enum Keychain {
    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(service: String, account: String, value: String) {
        remove(service: service, account: account)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func remove(service: String, account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}

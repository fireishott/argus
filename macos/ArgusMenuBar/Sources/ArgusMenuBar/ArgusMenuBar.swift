import AppKit
import Security
import SwiftUI

@main
struct ArgusMenuBarApp: App {
    @NSApplicationDelegateAdaptor(ArgusAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            ArgusSettingsView(preferences: appDelegate.preferences, store: appDelegate.store)
        }
    }
}

@MainActor
final class ArgusAppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore()
    let preferences = ArgusPreferences()
    let settingsWindow = ArgusSettingsWindow()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        settingsWindow.configure(store: store)
        store.configure(preferences: preferences, settingsWindow: settingsWindow)
        Task { await store.start(refreshSeconds: preferences.refreshSeconds, preferences: preferences) }
    }
}

// MARK: - Menu bar

/// Every provider target and the optional Argus control are real NSStatusItems.
/// macOS can therefore position them independently, just like Stats modules.

struct StatusBarProviders: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var preferences: ArgusPreferences

    var body: some View {
        HStack(spacing: 7) {
            ForEach(preferences.orderedEnabledTargets(from: store.statusTargets)) { target in
                StatusTargetChip(target: target, preferences: preferences)
            }
            if preferences.orderedEnabledTargets(from: store.statusTargets).isEmpty {
                Image(systemName: "eye.slash")
            }
        }
        .task { await store.start(refreshSeconds: preferences.refreshSeconds, preferences: preferences) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Argus provider usage")
    }
}

struct StatusTargetChip: View {
    let target: StatusTarget
    @ObservedObject var preferences: ArgusPreferences

    var body: some View {
        let color = preferences.color(for: target.remainingPercent)
        HStack(spacing: 3) {
            TargetMark(provider: target.provider, iconMode: preferences.iconMode).foregroundStyle(color)
            Text(target.compactLabel).font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
            switch preferences.displayMode {
            case .usageBar:
                UsageBar(remainingPercent: target.remainingPercent, preferences: preferences)
            case .fuelGauge:
                TargetFuelGauge(target: target, preferences: preferences)
            case .iconOnly:
                EmptyView()
            default:
                Text(target.valueText).monospacedDigit().foregroundStyle(color)
            }
        }
        .help(target.label + ": " + target.valueText)
        .accessibilityLabel(target.label + ", " + target.valueText)
    }
}

struct TargetMark: View {
    let provider: String
    let iconMode: IconMode
    var body: some View {
        switch iconMode {
        case .brandMark:
            if let image = ProviderIcon.image(for: provider) {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 14, height: 14)
            } else {
                Image(systemName: ProviderIcon.fallbackSymbol(for: provider)).frame(width: 14, height: 14)
            }
        case .monogram:
            Text(String(provider.prefix(2)).uppercased()).font(.system(size: 10, weight: .bold, design: .rounded)).frame(minWidth: 14)
        case .systemSymbol:
            Image(systemName: ProviderIcon.fallbackSymbol(for: provider)).font(.system(size: 12, weight: .semibold))
        }
    }
}

enum ProviderIcon {
    private static let assetNames: [String: String] = [
        "claude": "claude", "deepseek": "deepseek", "minimax": "minimax",
        "openrouter": "openrouter", "opencode-go": "opencode-go", "xiaomi-tokenplan": "mimo"
    ]
    static func image(for provider: String) -> NSImage? {
        guard let name = assetNames[provider], let url = Bundle.module.url(forResource: name, withExtension: "svg"), let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }
    static func fallbackSymbol(for provider: String) -> String {
        switch provider {
        case "claude": "sparkle"; case "deepseek": "wave.3.right"; case "minimax": "bolt"; case "openrouter": "arrow.triangle.branch"; case "opencode-go": "chevron.left.forwardslash.chevron.right"; default: "cpu"
        }
    }
}

struct TargetFuelGauge: View {
    let target: StatusTarget
    @ObservedObject var preferences: ArgusPreferences
    var body: some View {
        let used = Double(100 - (target.remainingPercent ?? 0)) / 100
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(.quaternary)
            GeometryReader { proxy in RoundedRectangle(cornerRadius: 5).fill(preferences.usageGradient).frame(width: proxy.size.width * used) }.clipShape(RoundedRectangle(cornerRadius: 5))
            TargetMark(provider: target.provider, iconMode: preferences.iconMode).font(.system(size: 9, weight: .bold)).foregroundStyle(.primary)
        }.frame(width: 24, height: 15)
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

struct ConsumptionBar: View {
    let remainingPercent: Int?
    @ObservedObject var preferences: ArgusPreferences

    var body: some View {
        let used = max(0, min(1, Double(100 - (remainingPercent ?? 0)) / 100))
        Capsule()
            .fill(.quaternary)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(preferences.usageGradient)
                        .frame(width: proxy.size.width * used)
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)
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
    @ObservedObject var settingsWindow: ArgusSettingsWindow

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
                Button { settingsWindow.open(preferences: preferences, targets: store.statusTargets) } label: {
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
                Button("Settings") { settingsWindow.open(preferences: preferences, targets: store.statusTargets) }
                Spacer()
                Button("Open Dashboard") { store.openDashboard() }
                    .disabled(store.dashboardURL == nil)
            }
        }
        .padding(14)
        .frame(width: 390)
    }
}

@MainActor
final class ArgusSettingsWindow: ObservableObject {
    private var controller: NSWindowController?
    private weak var store: UsageStore?

    func configure(store: UsageStore) { self.store = store }

    func open(preferences: ArgusPreferences, targets: [StatusTarget] = []) {
        if let window = controller?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let store else { return }
        let hosting = NSHostingController(rootView: ArgusSettingsView(preferences: preferences, store: store))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Argus Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 560, height: 620))
        window.isReleasedWhenClosed = false
        let controller = NSWindowController(window: window)
        self.controller = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
                if let balance = provider.balanceShortText {
                    Text(balance).monospacedDigit()
                } else {
                    Text(preferences.valueText(for: provider)).monospacedDigit()
                }
            }
            ForEach(provider.windows) { window in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(window.label).foregroundStyle(.secondary)
                        Spacer()
                        Text(window.remainingText).monospacedDigit()
                    }
                    ConsumptionBar(remainingPercent: window.remainingPercent, preferences: preferences)
                }
                .font(.caption)
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

struct StatusTargetPreference: Codable, Identifiable {
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
    var statusTargetOrder: [StatusTargetPreference] = []
    var showControlItem = false
    var installedIndividualTargetLayout = false
    var statusLayoutRevision = 0
    var controlItemMigrationRevision = 0
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
        // Old alpha builds stored only provider-level menu items. Keep those
        // defaults, but let new provider/window targets populate on refresh.
        // The dedicated graph control was an alpha experiment. Provider items
        // are the real surface, so remove that control from existing installs.
        if values.controlItemMigrationRevision < 1 {
            values.showControlItem = false
            values.controlItemMigrationRevision = 1
            save()
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

    func orderedEnabledTargets(from targets: [StatusTarget]) -> [StatusTarget] {
        syncTargets(targets)
        let indexes = Dictionary(uniqueKeysWithValues: values.statusTargetOrder.enumerated().map { ($0.element.id, $0.offset) })
        let enabled = Set(values.statusTargetOrder.filter(\.enabled).map(\.id))
        return targets.filter { enabled.contains($0.id) }
            .sorted { indexes[$0.id, default: .max] < indexes[$1.id, default: .max] }
    }

    func sync(_ providers: [ProviderUsage]) {
        let known = Set(values.providerOrder.map(\.id))
        let additions = providers.filter { !known.contains($0.provider) }.map { ProviderPreference(id: $0.provider, enabled: true) }
        guard !additions.isEmpty else { return }
        values.providerOrder.append(contentsOf: additions)
        save()
    }

    func syncTargets(_ targets: [StatusTarget]) {
        let preferred = [
            "window:claude:session-5h", "window:claude:weekly-7d",
            "window:minimax:m-series-5h", "window:minimax:m-series-7d",
            "balance:deepseek", "balance:openrouter",
            "window:opencode-go:session-5h", "window:opencode-go:weekly-7d", "window:opencode-go:monthly-30d",
        ]
        let positions = Dictionary(uniqueKeysWithValues: preferred.enumerated().map { ($0.element, $0.offset) })
        // Revision 2 repairs the first alpha migration, which could run while
        // an upstream quota API was temporarily unavailable and pin nothing.
        if values.statusLayoutRevision < 2 {
            values.statusTargetOrder = targets
                .sorted { positions[$0.id, default: .max] < positions[$1.id, default: .max] }
                .map { StatusTargetPreference(id: $0.id, enabled: preferred.contains($0.id)) }
            values.installedIndividualTargetLayout = true
            values.statusLayoutRevision = 2
            save()
            return
        }
        let known = Set(values.statusTargetOrder.map(\.id))
        let additions = targets.filter { !known.contains($0.id) }.map { target in
            StatusTargetPreference(id: target.id, enabled: preferred.contains(target.id))
        }
        guard !additions.isEmpty else { return }
        values.statusTargetOrder.append(contentsOf: additions)
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
    @ObservedObject var store: UsageStore
    private var statusTargets: [StatusTarget] { store.statusTargets }
    @State private var selectedTargetID: String?
    @State private var providerNames: [String: String] = [:]

    var body: some View {
        TabView {
            displayTab.tabItem { Label("Display", systemImage: "menubar.rectangle") }
            ProviderConfigurationView()
                .tabItem { Label("Configuration", systemImage: "key.horizontal") }
        }
        .padding()
        .frame(width: 760, height: 760)
    }

    private var displayTab: some View {
        Form {
            Section("Menu bar") {
                Picker("Provider mark", selection: binding(\.iconMode)) { ForEach(IconMode.allCases) { Text($0.label).tag($0) } }
                Picker("Value next to mark", selection: binding(\.displayMode)) { ForEach(DisplayMode.allCases) { Text($0.label).tag($0) } }
                Picker("Refresh", selection: binding(\.refreshSeconds)) {
                    Text("5 seconds").tag(5); Text("15 seconds").tag(15); Text("30 seconds").tag(30); Text("60 seconds").tag(60); Text("2 minutes").tag(120); Text("5 minutes").tag(300)
                }
                Toggle("Show Argus control item", isOn: binding(\.showControlItem))
                Text("Turn this off to hide the eye. Double-click any pinned provider item to open Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Colors by remaining usage") {
                Picker("Healthy", selection: binding(\.healthyColor)) { ForEach(StoredColor.allCases) { Text($0.label).tag($0) } }
                Picker("Warning", selection: binding(\.warningColor)) { ForEach(StoredColor.allCases) { Text($0.label).tag($0) } }
                Picker("Critical", selection: binding(\.criticalColor)) { ForEach(StoredColor.allCases) { Text($0.label).tag($0) } }
                Picker("Unavailable", selection: binding(\.unavailableColor)) { ForEach(StoredColor.allCases) { Text($0.label).tag($0) } }
                Stepper("Warning at \(preferences.values.warningThreshold)% or below", value: binding(\.warningThreshold), in: 1...99)
                Stepper("Critical at \(preferences.values.criticalThreshold)% or below", value: binding(\.criticalThreshold), in: 0...preferences.values.warningThreshold)
            }
            Section("Status bar layout") {
                Text("Select an item, then pin it, remove it, or move it. The pinned list is the exact left-to-right menu-bar order.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Available").font(.caption).foregroundStyle(.secondary)
                        targetList(availableTargets)
                    }
                    VStack(spacing: 8) {
                        Button(action: pinSelected) { Image(systemName: "arrow.right") }
                            .disabled(!canPinSelected)
                        Button(action: unpinSelected) { Image(systemName: "arrow.left") }
                            .disabled(!canUnpinSelected)
                        Divider().frame(height: 18)
                        Button(action: moveSelectedLeft) { Image(systemName: "chevron.left") }
                            .disabled(!canMoveSelectedLeft)
                        Button(action: moveSelectedRight) { Image(systemName: "chevron.right") }
                            .disabled(!canMoveSelectedRight)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 28)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pinned to status bar").font(.caption).foregroundStyle(.secondary)
                        targetList(pinnedTargets)
                    }
                }
                .frame(minHeight: 250)
            }
        }.formStyle(.grouped)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<PersistedPreferences, T>) -> Binding<T> {
        Binding(get: { preferences.values[keyPath: keyPath] }, set: { value in preferences.update { $0[keyPath: keyPath] = value } })
    }
    private var orderedTargets: [StatusTarget] {
        preferences.syncTargets(statusTargets)
        let positions = Dictionary(uniqueKeysWithValues: preferences.values.statusTargetOrder.enumerated().map { ($0.element.id, $0.offset) })
        return statusTargets.sorted { positions[$0.id, default: .max] < positions[$1.id, default: .max] }
    }
    private var pinnedTargets: [StatusTarget] { orderedTargets.filter { isPinned($0.id) } }
    private var availableTargets: [StatusTarget] { orderedTargets.filter { !isPinned($0.id) } }
    private func isPinned(_ id: String) -> Bool { preferences.values.statusTargetOrder.first(where: { $0.id == id })?.enabled ?? false }
    private var canPinSelected: Bool { selectedTargetID.map { !isPinned($0) } ?? false }
    private var canUnpinSelected: Bool { selectedTargetID.map(isPinned) ?? false }
    private var selectedPinnedIndex: Int? { guard let selectedTargetID else { return nil }; return pinnedTargets.firstIndex(where: { $0.id == selectedTargetID }) }
    private var canMoveSelectedLeft: Bool { (selectedPinnedIndex ?? 0) > 0 }
    private var canMoveSelectedRight: Bool { guard let index = selectedPinnedIndex else { return false }; return index < pinnedTargets.count - 1 }

    @ViewBuilder private func targetList(_ targets: [StatusTarget]) -> some View {
        ScrollView {
            LazyVStack(spacing: 3) {
                ForEach(targets) { target in
                    Button { selectedTargetID = target.id } label: { targetRow(target) }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 7).padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selectedTargetID == target.id ? Color.accentColor.opacity(0.28) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
            .padding(4)
        }
        .frame(minWidth: 285, maxWidth: .infinity, minHeight: 235, maxHeight: 235)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    @ViewBuilder private func targetRow(_ target: StatusTarget) -> some View {
        HStack(spacing: 7) {
            TargetMark(provider: target.provider, iconMode: preferences.iconMode).foregroundStyle(preferences.color(for: target.remainingPercent))
            Text(target.shortLabel).lineLimit(1)
            Spacer(minLength: 6)
            Text(target.valueText).monospacedDigit().foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
    private func pinSelected() { setPinned(selectedTargetID, true) }
    private func unpinSelected() { setPinned(selectedTargetID, false) }
    private func setPinned(_ id: String?, _ enabled: Bool) {
        guard let id else { return }
        preferences.update { values in
            guard let index = values.statusTargetOrder.firstIndex(where: { $0.id == id }) else { return }
            values.statusTargetOrder[index].enabled = enabled
        }
    }
    private func moveSelectedLeft() { moveSelected(by: -1) }
    private func moveSelectedRight() { moveSelected(by: 1) }
    private func moveSelected(by offset: Int) {
        guard let id = selectedTargetID, let current = pinnedTargets.firstIndex(where: { $0.id == id }) else { return }
        let pinned = pinnedTargets.map(\.id)
        let destination = current + offset
        guard pinned.indices.contains(destination) else { return }
        let swapID = pinned[destination]
        preferences.update { values in
            guard let source = values.statusTargetOrder.firstIndex(where: { $0.id == id }), let target = values.statusTargetOrder.firstIndex(where: { $0.id == swapID }) else { return }
            values.statusTargetOrder.swapAt(source, target)
        }
    }
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
                        Button("Remove", role: .destructive) { Keychain.remove(service: "Argus.Provider", account: provider.id); credential = ""; status = "Removed from this Mac." }
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
    }

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
    @Published var statusTargets: [StatusTarget] = []
    private let statusItems = ArgusStatusItems()
    private var preferencesForStatusItems: ArgusPreferences?
    private weak var settingsWindowForStatusItems: ArgusSettingsWindow?
    @Published var error: String?
    @Published var dashboardURL: URL?
    @Published var lastUpdatedText = "Not updated"
    private let client = ArgusClient()
    private var refreshTask: Task<Void, Never>?

    deinit { refreshTask?.cancel() }

    func configure(preferences: ArgusPreferences, settingsWindow: ArgusSettingsWindow) {
        preferencesForStatusItems = preferences
        settingsWindowForStatusItems = settingsWindow
    }

    func start(refreshSeconds: Int, preferences: ArgusPreferences) async {
        preferencesForStatusItems = preferences
        guard refreshTask == nil else { return }
        await refresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.preferencesForStatusItems?.values.refreshSeconds ?? refreshSeconds
                try? await Task.sleep(for: .seconds(interval))
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        do {
            let payload = try await client.snapshot()
            providers = payload.providers
            statusTargets = payload.statusTargets
            if let preferencesForStatusItems {
                statusItems.update(
                    targets: preferencesForStatusItems.orderedEnabledTargets(from: payload.statusTargets),
                    providers: payload.providers,
                    preferences: preferencesForStatusItems,
                    settingsWindow: settingsWindowForStatusItems,
                    dashboardURL: payload.links.dashboardURL
                )
            }
            dashboardURL = payload.links.dashboardURL
            lastUpdatedText = "Updated now"
            error = nil
        } catch {
            self.error = "Check Argus URL and access token in Settings."
        }
    }

    func openDashboard() { if let dashboardURL { NSWorkspace.shared.open(dashboardURL) } }
}

@MainActor
final class ArgusStatusItems {
    private var items: [String: NSStatusItem] = [:]
    private var handlers: [String: StatusItemHandler] = [:]
    private var controlItem: NSStatusItem?
    private var controlHandler: StatusItemHandler?
    private let popover = NSPopover()

    func update(targets: [StatusTarget], providers: [ProviderUsage], preferences: ArgusPreferences, settingsWindow: ArgusSettingsWindow?, dashboardURL: URL?) {
        updateControl(preferences: preferences, settingsWindow: settingsWindow)
        let wanted = Set(targets.map(\.id))
        for (id, item) in items where !wanted.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            items.removeValue(forKey: id)
            handlers.removeValue(forKey: id)
        }
        for target in targets {
            let item = items[target.id] ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            items[target.id] = item
            let provider = providers.first(where: { $0.provider == target.provider })
            configure(item, target: target, provider: provider, preferences: preferences, settingsWindow: settingsWindow, dashboardURL: dashboardURL)
        }
    }

    private func updateControl(preferences: ArgusPreferences, settingsWindow: ArgusSettingsWindow?) {
        guard preferences.values.showControlItem else {
            if let controlItem { NSStatusBar.system.removeStatusItem(controlItem) }
            controlItem = nil; controlHandler = nil
            return
        }
        let item = controlItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        controlItem = item
        guard let button = item.button else { return }
        button.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "Argus controls")
        button.image?.isTemplate = true
        button.title = ""
        button.toolTip = "Argus - click for Settings"
        let handler = StatusItemHandler { [weak settingsWindow] event in
            guard event.clickCount >= 1 else { return }
            settingsWindow?.open(preferences: preferences, targets: [])
        }
        controlHandler = handler
        button.target = handler
        button.action = #selector(StatusItemHandler.handleClick(_:))
    }

    private func configure(_ item: NSStatusItem, target: StatusTarget, provider: ProviderUsage?, preferences: ArgusPreferences, settingsWindow: ArgusSettingsWindow?, dashboardURL: URL?) {
        guard let button = item.button else { return }
        let color = statusNSColor(target: target, preferences: preferences)
        let textColor = statusTextNSColor(target: target, preferences: preferences)
        let icon = ProviderIcon.image(for: target.provider) ?? NSImage(
            systemSymbolName: ProviderIcon.fallbackSymbol(for: target.provider),
            accessibilityDescription: target.label
        )
        let renderedIcon = icon?.resized(to: NSSize(width: 14, height: 14)) ?? NSImage(size: NSSize(width: 14, height: 14))
        button.image = statusItemImage(icon: renderedIcon, target: target, preferences: preferences, iconColor: color, textColor: textColor)
        button.imagePosition = .imageOnly
        button.contentTintColor = nil
        button.title = ""
        let peek = provider?.quickPeek ?? "\(target.shortLabel): \(target.valueText) - \(target.statusText)"
        button.toolTip = peek
        button.setAccessibilityLabel(peek)
        let handler = StatusItemHandler { [weak self, weak settingsWindow, weak button] event in
            guard let self else { return }
            if event.clickCount >= 2 {
                settingsWindow?.open(preferences: preferences, targets: [])
            } else if let provider, let button {
                self.presentDetail(provider: provider, from: button, dashboardURL: dashboardURL)
            }
        }
        handlers[target.id] = handler
        button.target = handler
        button.action = #selector(StatusItemHandler.handleClick(_:))
    }

    private func presentDetail(provider: ProviderUsage, from button: NSStatusBarButton, dashboardURL: URL?) {
        popover.contentViewController = NSHostingController(rootView: ProviderDetailView(provider: provider, dashboardURL: dashboardURL))
        popover.behavior = .transient
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func statusNSColor(target: StatusTarget, preferences: ArgusPreferences) -> NSColor {
        if target.status == "inactive" || target.status == "unavailable" { return .systemRed }
        if let remaining = target.remainingPercent {
            if remaining <= preferences.values.criticalThreshold { return .systemRed }
            if remaining <= preferences.values.warningThreshold { return .systemYellow }
        }
        if target.status == "in_use" { return .systemGreen }
        return .white
    }

    private func statusTextNSColor(target: StatusTarget, preferences: ArgusPreferences) -> NSColor {
        if target.status == "inactive" || target.status == "unavailable" { return .systemRed }
        if let remaining = target.remainingPercent {
            if remaining <= preferences.values.criticalThreshold { return .systemRed }
            if remaining <= preferences.values.warningThreshold { return .systemYellow }
        }
        return .white
    }

    private func statusComposite(icon: NSImage, text: String, iconColor: NSColor, textColor: NSColor) -> NSImage {
        let iconSize = NSSize(width: 14, height: 14)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let textAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let textSize = (text as NSString).size(withAttributes: textAttrs)
        let spacing: CGFloat = 2
        let width = iconSize.width + spacing + ceil(textSize.width)
        let height = max(iconSize.height, ceil(textSize.height))
        let tintedIcon = icon.tinted(with: iconColor)
        let output = NSImage(size: NSSize(width: width, height: height))
        output.lockFocus()
        tintedIcon.draw(in: NSRect(x: 0, y: (height - iconSize.height) / 2, width: iconSize.width, height: iconSize.height))
        (text as NSString).draw(
            in: NSRect(x: iconSize.width + spacing, y: (height - textSize.height) / 2, width: ceil(textSize.width), height: ceil(textSize.height)),
            withAttributes: textAttrs
        )
        output.unlockFocus()
        return output
    }

    private func statusItemImage(icon: NSImage, target: StatusTarget, preferences: ArgusPreferences, iconColor: NSColor, textColor: NSColor) -> NSImage {
        switch preferences.values.displayMode {
        case .usageBar:
            return statusBarComposite(icon: icon, remainingPercent: target.remainingPercent, color: iconColor)
        case .fuelGauge:
            return statusGaugeComposite(icon: icon, remainingPercent: target.remainingPercent, color: iconColor)
        case .iconOnly:
            return icon.tinted(with: iconColor)
        default:
            let text = statusValueText(for: target, preferences: preferences)
            return statusComposite(icon: icon, text: text, iconColor: iconColor, textColor: textColor)
        }
    }

    private func statusValueText(for target: StatusTarget, preferences: ArgusPreferences) -> String {
        switch preferences.values.displayMode {
        case .balance:
            return target.balance?.displayText ?? target.remainingPercent.map { "\($0)%" } ?? "n/a"
        case .remainingPercent:
            return target.remainingPercent.map { "\($0)%" } ?? target.balance?.displayText ?? "n/a"
        case .usageBar, .fuelGauge, .iconOnly:
            return ""
        }
    }

    private func statusBarComposite(icon: NSImage, remainingPercent: Int?, color: NSColor) -> NSImage {
        let iconSize = NSSize(width: 14, height: 14)
        let barWidth: CGFloat = 5
        let barHeight: CGFloat = 14
        let spacing: CGFloat = 2
        let width = iconSize.width + spacing + barWidth
        let height = max(iconSize.height, barHeight)
        let used = CGFloat(max(0, min(100, 100 - (remainingPercent ?? 0)))) / 100.0
        let tintedIcon = icon.tinted(with: color)
        let output = NSImage(size: NSSize(width: width, height: height))
        output.lockFocus()
        tintedIcon.draw(in: NSRect(x: 0, y: (height - iconSize.height) / 2, width: iconSize.width, height: iconSize.height))
        let barX = iconSize.width + spacing
        let barY = (height - barHeight) / 2
        let radius = barWidth / 2
        let track = NSBezierPath(roundedRect: NSRect(x: barX, y: barY, width: barWidth, height: barHeight), xRadius: radius, yRadius: radius)
        NSColor.white.withAlphaComponent(0.22).setFill()
        track.fill()
        let fillHeight = barHeight * used
        if fillHeight > 0 {
            NSGraphicsContext.saveGraphicsState()
            track.addClip()
            color.setFill()
            NSRect(x: barX, y: barY, width: barWidth, height: fillHeight).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        output.unlockFocus()
        return output
    }

    private func statusGaugeComposite(icon: NSImage, remainingPercent: Int?, color: NSColor) -> NSImage {
        let iconSize = NSSize(width: 14, height: 14)
        let gaugeWidth: CGFloat = 7
        let gaugeHeight: CGFloat = 14
        let spacing: CGFloat = 2
        let width = iconSize.width + spacing + gaugeWidth
        let height = max(iconSize.height, gaugeHeight)
        let used = CGFloat(max(0, min(100, 100 - (remainingPercent ?? 0)))) / 100.0
        let tintedIcon = icon.tinted(with: color)
        let output = NSImage(size: NSSize(width: width, height: height))
        output.lockFocus()
        tintedIcon.draw(in: NSRect(x: 0, y: (height - iconSize.height) / 2, width: iconSize.width, height: iconSize.height))
        let gaugeX = iconSize.width + spacing
        let gaugeY = (height - gaugeHeight) / 2
        let radius: CGFloat = 2
        let tank = NSBezierPath(roundedRect: NSRect(x: gaugeX, y: gaugeY, width: gaugeWidth, height: gaugeHeight), xRadius: radius, yRadius: radius)
        NSColor.white.withAlphaComponent(0.18).setFill()
        tank.fill()
        let fillHeight = gaugeHeight * used
        if fillHeight > 0 {
            NSGraphicsContext.saveGraphicsState()
            tank.addClip()
            color.setFill()
            NSRect(x: gaugeX, y: gaugeY, width: gaugeWidth, height: fillHeight).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        NSColor.white.withAlphaComponent(0.4).setStroke()
        tank.lineWidth = 1
        tank.stroke()
        output.unlockFocus()
        return output
    }

    private func providerSymbol(_ provider: String) -> String {
        switch provider {
        case "claude": "sparkle"
        case "deepseek": "wave.3.right"
        case "minimax": "bolt"
        case "openrouter": "arrow.triangle.branch"
        case "opencode-go": "chevron.left.forwardslash.chevron.right"
        default: "cpu"
        }
    }
}

@MainActor
final class StatusItemHandler: NSObject {
    private let action: (NSEvent) -> Void
    init(action: @escaping (NSEvent) -> Void) { self.action = action }
    @objc func handleClick(_ sender: Any?) { action(NSApp.currentEvent ?? NSEvent()) }
}

struct ProviderDetailView: View {
    let provider: ProviderUsage
    let dashboardURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(provider.label).font(.headline)
                Spacer()
                Text(provider.status.capitalized).font(.caption).foregroundStyle(.secondary)
            }
            if let balance = provider.balanceShortText {
                LabeledContent("Balance", value: balance).monospacedDigit()
            }
            if !provider.windows.isEmpty {
                Divider()
                ForEach(provider.windows) { window in
                    HStack {
                        Text(window.label)
                        Spacer()
                        Text(window.remainingText).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            HStack {
                Text("Hover: quick peek").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let dashboardURL { Link("Dashboard", destination: dashboardURL) }
            }
        }
        .padding(14)
        .frame(width: 310)
    }
}

extension NSImage {
    func resized(to newSize: NSSize) -> NSImage {
        let output = NSImage(size: newSize)
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: newSize), from: .zero, operation: .sourceOver, fraction: 1)
        output.unlockFocus()
        return output
    }

    func tinted(with color: NSColor) -> NSImage {
        let output = NSImage(size: size)
        output.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        // Draw the source first to establish the shape/alpha mask.
        draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        // Then replace the opaque pixels with the target color, keeping alpha.
        NSGraphicsContext.current?.cgContext.setBlendMode(.sourceAtop)
        color.set()
        rect.fill()
        output.unlockFocus()
        return output
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
        // Local Argus binds to loopback and does not require a bearer token.
        // Do not auto-read Keychain during refresh: background auth prompts can
        // block the macOS desktop without an interactive input path.
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SnapshotPayload.self, from: data)
    }
}

struct SnapshotPayload: Decodable {
    let schemaVersion: Int
    let providers: [ProviderUsage]
    let statusTargets: [StatusTarget]
    let links: Links
    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", providers, statusTargets = "status_targets", links }
    struct Links: Decodable { let dashboardURL: URL?; enum CodingKeys: String, CodingKey { case dashboardURL = "dashboard_url" } }
}

struct StatusTarget: Decodable, Identifiable {
    let id: String
    let provider: String
    let kind: String
    let label: String
    let status: String
    let remainingPercent: Int?
    let balance: Balance?
    enum CodingKeys: String, CodingKey { case id, provider, kind, label, status, balance, remainingPercent = "remaining_percent" }
    var valueText: String {
        if let balance { return balance.displayText }
        return remainingPercent.map { "\($0)%" } ?? "n/a"
    }
    var compactLabel: String {
        if kind == "balance" { return "Bal" }
        guard kind == "window" else { return "" }
        let lower = label.lowercased()
        if lower.contains("5h") { return "5h" }
        if lower.contains("7d") { return "7d" }
        if lower.contains("30d") { return "30d" }
        return "Use"
    }
    var shortLabel: String {
        let providerName = provider == "opencode-go" ? "OpenCode" : provider.capitalized
        return compactLabel.isEmpty ? providerName : "\(providerName) \(compactLabel)"
    }
    var statusText: String {
        switch status {
        case "in_use": "Active"
        case "inactive", "unavailable": "Unavailable"
        case "degraded": "Degraded"
        default: "Standby"
        }
    }
}

struct ProviderUsage: Decodable, Identifiable {
    let provider: String
    let label: String
    let status: String
    let windows: [UsageWindow]
    let balance: Balance?
    var id: String { provider }
    var remainingPercent: Int? { windows.first(where: { $0.id == "5h" })?.remainingPercent ?? windows.first?.remainingPercent }
    var balanceText: String? { balance.map { "Balance: \($0.displayText)" } }
    var balanceShortText: String? { balance.map(\.displayText) }
    var monogram: String { label.split(separator: " ").prefix(2).map { String($0.prefix(1)) }.joined().uppercased() }
    var symbolName: String { "cpu" }
    var tooltip: String { "\(label): \(windows.map { "\($0.label) \($0.remainingText)" }.joined(separator: ", "))" }
    var quickPeek: String {
        let quota = windows.map { "\($0.label): \($0.remainingText)" }.joined(separator: " | ")
        let balancePart = balanceShortText.map { " | Balance: \($0)" } ?? ""
        return "\(label) - \(status.capitalized)\(quota.isEmpty ? "" : " | \(quota)")\(balancePart)"
    }
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

struct Balance: Decodable {
    let kind: String
    let remaining: Double
    let currency: String
    var displayText: String {
        let symbol = currency.uppercased() == "USD" ? "$" : "\(currency) "
        return "\(symbol)\(String(format: "%.2f", remaining))"
    }
}

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

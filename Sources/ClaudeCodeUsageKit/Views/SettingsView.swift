import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Settings window (General + Tier Theme)

/// One settings window, tabbed General / Tier Theme. Every control writes
/// straight to `Config` and calls `onChange` immediately — no Save step.
/// Text fields (which can hold invalid intermediate input while typing) are
/// buffered in local `@State` and committed on submit/disappear; every other
/// control is backed by `@State` synced to `Config` so edits redraw the view.
struct SettingsView: View {
    let onChange: () -> Void
    let pricingFeed: PricingFeed

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var planTier = Config.planTier
    @State private var monthlyBudgetText = String(format: "%.0f", Config.monthlyBudgetDollars)
    @State private var billingCycleResetDay = Config.billingCycleResetDay
    @State private var themes = Config.tierThemes
    @State private var activeThemeId = Config.activeTierThemeId
    @State private var workingDays = Config.workingDays
    @FocusState private var focusedIconStepId: UUID?
    @State private var pricingCatalog: PricingCatalog
    @State private var isRefreshingPrices = false

    init(onChange: @escaping () -> Void, pricingFeed: PricingFeed) {
        self.onChange = onChange
        self.pricingFeed = pricingFeed
        _pricingCatalog = State(initialValue: pricingFeed.catalog)
    }

    /// Weekday chips in Monday-first order (Calendar weekday numbers: 1 = Sunday).
    private let orderedWeekdays: [(number: Int, label: String)] = [
        (2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat"), (1, "Sun"),
    ]

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            tierThemeTab
                .tabItem { Label("Tier Theme", systemImage: "chart.bar.fill") }
            pricingTab
                .tabItem { Label("Pricing", systemImage: "tag") }
        }
        .padding(20)
        .frame(width: 440, height: 400)
    }

    // MARK: General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { launchAtLogin = $0; setLaunchAtLogin($0) }
            ))

            HStack {
                Text("Plan")
                Spacer()
                Picker("", selection: Binding(
                    get: { planTier },
                    set: { planTier = $0; Config.planTier = $0; onChange() }
                )) {
                    ForEach(PlanTier.allCases, id: \.self) { plan in
                        Text(plan.displayName).tag(plan)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            HStack {
                Text("Monthly budget")
                Spacer()
                TextField("1000", text: $monthlyBudgetText)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                    .onSubmit(commitMonthlyBudget)
                Text("$ / month").foregroundStyle(.secondary)
            }

            Stepper(value: Binding(
                get: { billingCycleResetDay },
                set: { billingCycleResetDay = $0; Config.billingCycleResetDay = $0; onChange() }
            ), in: 1...28) {
                Text("Cycle resets on day \(billingCycleResetDay)")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Working days")
                Text("Used to project your month total; days you don't work aren't extrapolated.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(orderedWeekdays, id: \.number) { day in
                        Toggle(day.label, isOn: Binding(
                            get: { workingDays.contains(day.number) },
                            set: { isOn in
                                if isOn { workingDays.insert(day.number) } else { workingDays.remove(day.number) }
                                Config.workingDays = workingDays
                                onChange()
                            }
                        ))
                        .toggleStyle(.button)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear(perform: commitMonthlyBudget)
    }

    private func commitMonthlyBudget() {
        guard let value = Double(monthlyBudgetText), value > 0 else {
            monthlyBudgetText = String(format: "%.0f", Config.monthlyBudgetDollars)
            return
        }
        Config.monthlyBudgetDollars = value
        onChange()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Launch-at-login toggle failed: \(error.localizedDescription)")
        }
    }

    /// Focus a step's emoji field and open the system emoji & symbols palette,
    /// so the picked character lands in that field. Clears the field first so
    /// the selection replaces the current emoji rather than appending to it.
    private func openEmojiPicker(for stepId: UUID, in themeIndex: Int) {
        if let index = themes[themeIndex].steps.firstIndex(where: { $0.id == stepId }) {
            themes[themeIndex].steps[index].icon = ""
        }
        focusedIconStepId = stepId
        DispatchQueue.main.async {
            NSApp.orderFrontCharacterPalette(nil)
        }
    }

    // MARK: Tier Theme

    private var tierThemeTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Active ladder", selection: Binding(
                get: { activeThemeId },
                set: { activeThemeId = $0; Config.activeTierThemeId = $0; onChange() }
            )) {
                ForEach(themes) { theme in
                    Text(theme.name).tag(theme.id)
                }
            }

            if let themeIndex = themes.firstIndex(where: { $0.id == activeThemeId }) {
                List {
                    ForEach($themes[themeIndex].steps) { $step in
                        HStack {
                            TextField("🙂", text: $step.icon)
                                .frame(width: 32)
                                .focused($focusedIconStepId, equals: step.id)
                            Button {
                                openEmojiPicker(for: step.id, in: themeIndex)
                            } label: {
                                Image(systemName: "face.smiling")
                            }
                            .buttonStyle(.borderless)
                            .help("Pick an emoji")
                            TextField("Name", text: $step.name).frame(width: 130)
                            Text("$")
                            TextField("0", value: $step.unlockAtDollars, format: .number)
                                .frame(width: 56)
                                .multilineTextAlignment(.trailing)
                            Spacer()
                            Button {
                                themes[themeIndex].steps.removeAll { $0.id == step.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Button("Add step") {
                    themes[themeIndex].steps.append(TierStep(name: "New step", icon: "⭐️", unlockAtDollars: 0))
                }
            }
        }
        .onChange(of: themes) { newValue in
            Config.tierThemes = newValue
            onChange()
        }
    }

    // MARK: Pricing

    /// Shows where the rates came from, so numbers never change without a
    /// visible reason, and lets the user re-check on demand.
    private var pricingTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(pricingOriginDescription)
            Text("Published \(pricingCatalog.updatedAt) · schema v\(pricingCatalog.schemaVersion)")
                .font(.caption).foregroundStyle(.secondary)

            if let source = pricingCatalog.source, let url = URL(string: source) {
                Link("Anthropic's published rates", destination: url).font(.caption)
            }

            Divider()

            Text("Rates in USD per million tokens.").font(.caption).foregroundStyle(.secondary)
            List(pricingCatalog.models, id: \.id) { model in
                HStack {
                    Text(model.displayName)
                    if model.legacy {
                        Text("legacy").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(currentRateDescription(for: model)).monospacedDigit()
                }
            }

            if let failure = pricingFeed.lastFailureReason {
                Text("Last check failed: \(failure)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }

            HStack {
                Button(isRefreshingPrices ? "Checking…" : "Check for new prices") {
                    isRefreshingPrices = true
                    pricingFeed.refreshNow {
                        pricingCatalog = pricingFeed.catalog
                        isRefreshingPrices = false
                    }
                }
                .disabled(isRefreshingPrices)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pricingOriginDescription: String {
        switch pricingCatalog.origin {
        case .bundled:
            return "Using the prices shipped with this version."
        case let .feed(fetchedAt):
            let stamp = fetchedAt.formatted(date: .abbreviated, time: .shortened)
            return "Using the published price list, last checked \(stamp)."
        }
    }

    /// The rate in effect today, which is what a user is being billed at now.
    private func currentRateDescription(for model: ModelPricing) -> String {
        guard let period = model.periods.first(where: { $0.covers(Date()) }) ?? model.periods.first else {
            return "—"
        }
        return String(format: "$%g in / $%g out", period.inputPerMillion, period.outputPerMillion)
    }
}

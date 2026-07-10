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

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var planTier = Config.planTier
    @State private var monthlyBudgetText = String(format: "%.0f", Config.monthlyBudgetDollars)
    @State private var billingCycleResetDay = Config.billingCycleResetDay
    @State private var themes = Config.tierThemes
    @State private var activeThemeId = Config.activeTierThemeId

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            tierThemeTab
                .tabItem { Label("Tier Theme", systemImage: "chart.bar.fill") }
        }
        .padding(20)
        .frame(width: 440, height: 340)
    }

    // MARK: General

    private var generalTab: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { launchAtLogin = $0; setLaunchAtLogin($0) }
            ))

            Picker("Plan", selection: Binding(
                get: { planTier },
                set: { planTier = $0; Config.planTier = $0; onChange() }
            )) {
                ForEach(PlanTier.allCases, id: \.self) { plan in
                    Text(plan.displayName).tag(plan)
                }
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
        }
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
                            TextField("🙂", text: $step.icon).frame(width: 36)
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
}

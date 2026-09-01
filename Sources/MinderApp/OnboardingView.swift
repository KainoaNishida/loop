import AppKit
import SwiftUI
import MinderCore

struct OnboardingView: View {
    @ObservedObject var model: OnboardingViewModel

    private var palette: LoopPalette {
        model.profile.appColorScheme.palette
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                ScrollView {
                    stepContent
                        .padding(28)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                footer
            }
        }
        .frame(minWidth: 860, minHeight: 640)
        .environment(\.loopPalette, palette)
        .tint(palette.primary)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            model.load()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Label(model.profile.hasCompletedOnboarding ? "Loop Settings" : "Loop Setup", systemImage: "checklist.checked")
                    .font(.title3.weight(.semibold))
                Text("Permissions stay visible. Nothing connects silently.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 4) {
                ForEach(OnboardingStep.allCases) { step in
                    Button {
                        model.saveProfile()
                        model.selectedStep = step
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: step.systemImage)
                                .frame(width: 18)
                            Text(step.title)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .foregroundStyle(model.selectedStep == step ? palette.primary : Color.primary)
                        .background(model.selectedStep == step ? palette.primary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                HealthStatusPill(health: PermissionHealth(
                    kind: .appleMessages,
                    state: model.health(for: .appleMessages).state,
                    detail: model.messagesNextAction ?? "Messages setup is ready."
                ))
                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(18)
        .frame(width: 230)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.selectedStep {
        case .welcome:
            WelcomeStep()
        case .profile:
            ProfileStep(model: model)
        case .appearance:
            AppearanceStep(model: model)
        case .messages:
            MessagesStep(model: model)
        case .cloudAI:
            CloudAIStep(model: model)
        case .privacy:
            PrivacyStep(model: model)
        case .about:
            AboutStep()
        case .summary:
            SummaryStep(model: model)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.isWorking {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                model.refreshPermissions()
            } label: {
                Label("Check Again", systemImage: "arrow.clockwise")
            }

            Spacer()

            Button("Back") {
                model.back()
            }
            .disabled(!model.canMoveBack)

            if model.canMoveForward {
                Button {
                    model.next()
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    model.completeOnboarding()
                } label: {
                    Label(model.profile.hasCompletedOnboarding ? "Done" : "Finish Setup", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .controlSize(.regular)
    }
}

struct LoopSettingsPanelView: View {
    @ObservedObject var model: OnboardingViewModel

    private var palette: LoopPalette {
        model.profile.appColorScheme.palette
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                ScrollView {
                    stepContent
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                footer
            }
        }
        .environment(\.loopPalette, palette)
        .tint(palette.primary)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            model.load()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(model.profile.hasCompletedOnboarding ? "Settings" : "Setup", systemImage: "gearshape")
                .font(.headline.weight(.semibold))

            VStack(spacing: 4) {
                ForEach(OnboardingStep.allCases) { step in
                    Button {
                        model.saveProfile()
                        model.selectedStep = step
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: step.systemImage)
                                .frame(width: 16)
                            Text(step.title)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .foregroundStyle(model.selectedStep == step ? palette.primary : Color.primary)
                        .background(model.selectedStep == step ? palette.primary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                HealthStatusPill(health: PermissionHealth(
                    kind: .appleMessages,
                    state: model.health(for: .appleMessages).state,
                    detail: model.messagesNextAction ?? "Messages setup is ready."
                ))
                Text(model.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding(14)
        .frame(width: 178)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.selectedStep {
        case .welcome:
            WelcomeStep()
        case .profile:
            ProfileStep(model: model)
        case .appearance:
            AppearanceStep(model: model)
        case .messages:
            MessagesStep(model: model)
        case .cloudAI:
            CloudAIStep(model: model)
        case .privacy:
            PrivacyStep(model: model)
        case .about:
            AboutStep()
        case .summary:
            SummaryStep(model: model)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.isWorking {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                model.refreshPermissions()
            } label: {
                Label("Check Again", systemImage: "arrow.clockwise")
            }

            Spacer()

            Button("Back") {
                model.back()
            }
            .disabled(!model.canMoveBack)

            if model.canMoveForward {
                Button {
                    model.next()
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    model.completeOnboarding()
                } label: {
                    Label(model.profile.hasCompletedOnboarding ? "Done" : "Finish Setup", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .controlSize(.small)
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(
                title: "Set up Loop",
                subtitle: "Loop reviews Apple Messages locally and gives you a short list of conversations you may want to complete."
            )

            VStack(alignment: .leading, spacing: 12) {
                PrincipleRow(systemImage: "lock.shield", title: "Local by default", detail: "Messages are imported read-only into a local cache for this prototype.")
                PrincipleRow(systemImage: "eye", title: "Clear setup", detail: "The app shows whether Messages, Full Disk Access, and optional Contacts are ready.")
                PrincipleRow(systemImage: "checkmark.circle", title: "One simple action", detail: "Each conversation gets at most one alert, and you can mark it completed when you are done.")
            }
        }
    }
}

private struct ProfileStep: View {
    @ObservedObject var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(
                title: "Your profile",
                subtitle: "These defaults help Loop decide when and how to nudge you."
            )

            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("Display name") {
                    TextField("Your name", text: $model.profile.displayName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                }

                LabeledContent("Timezone") {
                    TextField("Timezone", text: $model.profile.timeZoneIdentifier)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                }

                LabeledContent("Notification cadence") {
                    Picker("Notification cadence", selection: $model.profile.notificationCadence) {
                        ForEach(NotificationCadence.allCases, id: \.rawValue) { cadence in
                            Text(cadence.displayName).tag(cadence)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 420)
                }

                Stepper("Quiet hours start: \(timeLabel(model.profile.quietHoursStartMinutes))", value: $model.profile.quietHoursStartMinutes, in: 0...1439, step: 60)
                    .frame(maxWidth: 360, alignment: .leading)
                Stepper("Quiet hours end: \(timeLabel(model.profile.quietHoursEndMinutes))", value: $model.profile.quietHoursEndMinutes, in: 0...1439, step: 60)
                    .frame(maxWidth: 360, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Source priority")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack {
                        SourcePriorityPill(text: "Apple Messages")
                    }
                }
            }
        }
    }
}

private struct AppearanceStep: View {
    @ObservedObject var model: OnboardingViewModel

    private var palette: LoopPalette {
        model.profile.appColorScheme.palette
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(
                title: "Theme",
                subtitle: "Queue, controls, and status accents."
            )

            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("Color scheme") {
                    Picker("Color scheme", selection: $model.profile.appColorScheme) {
                        ForEach(AppColorScheme.allCases, id: \.rawValue) { scheme in
                            Text(scheme.displayName).tag(scheme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 520)
                }

                HStack(spacing: 10) {
                    ForEach(0..<palette.swatches.count, id: \.self) { index in
                        Circle()
                            .fill(palette.swatches[index])
                            .frame(width: 22, height: 22)
                    }
                }
                .padding(.horizontal, 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(model.profile.appColorScheme.displayName) theme colors")
            }
        }
        .onChange(of: model.profile.appColorScheme) { _, _ in
            model.saveProfile()
        }
    }
}

private struct MessagesStep: View {
    @ObservedObject var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(
                title: "Apple Messages",
                subtitle: "Loop imports 30 days of Messages context read-only after Full Disk Access is granted. Active alerts use that same 30-day window."
            )

            SourceSetupCard(
                title: "Apple Messages",
                systemImage: "message.fill",
                readiness: model.messagesReadiness,
                status: model.health(for: .appleMessages),
                detail: "Requires Full Disk Access because Apple does not provide a stable public API for local message history.",
                primaryTitle: "Import Recent Messages",
                primarySystemImage: "square.and.arrow.down",
                primaryDisabled: !model.canImportMessages,
                helperText: model.messagesNextAction,
                action: { model.importMessagesRecent() }
            )

            PermissionCard(
                health: model.health(for: .fullDiskAccess),
                detail: "After granting access, return here and click Check Again.",
                primaryTitle: "Open System Settings",
                primarySystemImage: "lock.open",
                primaryAction: { model.openSettings(for: .fullDiskAccess) },
                secondaryTitle: nil,
                secondaryAction: nil,
                helperText: "Grant Full Disk Access to the current app bundle shown below. If macOS asks to quit and reopen, return here and use Relaunch Current Build."
            )

            CurrentAppBundleCard(model: model)

            SourceSetupCard(
                title: "Contact Names",
                systemImage: "person.crop.circle.badge.checkmark",
                readiness: model.contactsReadiness,
                status: model.health(for: .contacts),
                detail: "Optional but recommended. Contacts are used locally to show names instead of phone numbers or email handles.",
                primaryTitle: "Request Contacts",
                primarySystemImage: "person.2",
                primaryDisabled: !model.canRequestContacts,
                helperText: model.contactsNextAction,
                action: { model.request(.contacts) }
            )

            SetupPathBox(lines: [
                "1. Run scripts/build-dev-app.sh from the project folder.",
                "2. Open Privacy & Security > Full Disk Access.",
                "3. Add .build/LoopDev/Loop.app, then return and click Check Again.",
                "4. Optional: request Contacts before importing so handles resolve to names."
            ])
        }
    }
}

private struct CurrentAppBundleCard: View {
    @ObservedObject var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Current Running App", systemImage: "app.badge")
                    .font(.headline)
                Spacer()
                Text(model.currentAppBuildStamp)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(model.currentAppBundlePath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("This is the exact app that needs Full Disk Access. Avoid macOS relaunching another Loop copy by using the relaunch button here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button {
                    model.revealCurrentAppBundle()
                } label: {
                    Label("Reveal App", systemImage: "folder")
                }

                Button {
                    model.copyCurrentAppBundlePath()
                } label: {
                    Label("Copy Path", systemImage: "doc.on.doc")
                }

                Button {
                    model.relaunchCurrentAppBundle()
                } label: {
                    Label("Relaunch Current Build", systemImage: "arrow.clockwise.circle")
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct PermissionStep: View {
    var title: String
    var subtitle: String
    var health: PermissionHealth
    var primaryTitle: String
    var primarySystemImage: String
    var request: () -> Void
    var openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(title: title, subtitle: subtitle)
            PermissionCard(
                health: health,
                detail: health.detail,
                primaryTitle: primaryTitle,
                primarySystemImage: primarySystemImage,
                primaryAction: request,
                secondaryTitle: "Open System Settings",
                secondaryAction: openSettings
            )
        }
    }
}

private struct CloudAIStep: View {
    @ObservedObject var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(
                title: "AI",
                subtitle: "Local suggestions stay on by default. Gemini is optional and only used after you save a key and turn Cloud AI on."
            )

            PermissionCard(
                health: model.health(for: .cloudAI),
                detail: model.hasGeminiConfig ? "Gemini credentials were detected. Enable cloud AI only if you are comfortable sending selected Messages snippets for structured suggestions." : "No Gemini credentials were detected. Local suggestions remain active.",
                primaryTitle: "Check Credentials",
                primarySystemImage: "arrow.clockwise",
                primaryAction: { model.refreshPermissions() },
                secondaryTitle: nil,
                secondaryAction: nil
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("Gemini Setup")
                    .font(.headline)

                SecureField("Gemini API key", text: $model.geminiAPIKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                TextField("Model", text: $model.geminiModelInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                Text(model.geminiInputValidation.userFacingMessage)
                    .font(.caption)
                    .foregroundStyle(model.geminiInputValidation.isValid ? Color.secondary : Color.orange)

                Button {
                    model.saveGeminiConfig()
                } label: {
                    Label("Save Gemini Setup", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSaveGeminiConfig)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }

            Toggle("Enable Cloud AI suggestions", isOn: $model.profile.cloudAIEnabled)
                .toggleStyle(.switch)
                .disabled(!model.hasGeminiConfig)

            Text(model.hasGeminiConfig ? "Gemini will only be used after this toggle is on and setup is saved." : "Local fallback suggestions remain active without credentials.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PrivacyStep: View {
    @ObservedObject var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(
                title: "Privacy",
                subtitle: "Loop keeps imported Messages and generated suggestions in a local SQLite database for this alpha."
            )

            SetupPathBox(lines: [
                "Imported Messages are stored locally so the queue can show evidence and avoid duplicates.",
                "The alpha database is not encrypted yet. Delete local data before sharing or returning a test machine.",
                "Cloud AI is off unless you save Gemini credentials and enable the toggle in AI settings."
            ])

            VStack(alignment: .leading, spacing: 12) {
                Text("Local Data")
                    .font(.headline)
                Button("Delete Generated Suggestions") {
                    model.clearGeneratedSuggestions()
                }
                Button("Delete Imported Messages Cache", role: .destructive) {
                    model.clearImportedConversationCache()
                }
                Button("Delete All Local Loop Data", role: .destructive) {
                    model.eraseAllData()
                }
            }
            .controlSize(.small)
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
    }
}

#if LOOP_INTERNAL_DIAGNOSTICS
private struct DiagnosticsSettingsStep: View {
    @ObservedObject var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(
                title: "Diagnostics",
                subtitle: "Diagnostics report counts, health states, and a temporary local Messages decode trace."
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button {
                        model.runAppleMessagesDecodeTrace()
                    } label: {
                        Label("Run Mom/Hunter Trace", systemImage: "text.magnifyingglass")
                    }
                    .disabled(model.isWorking)

                    Button {
                        model.runAppleMessagesTextDiagnostic()
                    } label: {
                        Label("Check Messages Text", systemImage: "text.bubble")
                    }
                    .disabled(model.isWorking)

                    Button("Clear Diagnostics") {
                        model.clearGeminiDiagnostics()
                    }
                    .disabled(model.isWorking)
                }
                .controlSize(.small)

                if let report = model.appleMessagesDecodeTraceReport {
                    OnboardingMessagesDecodeTraceView(report: report)
                }

                if let diagnostics = model.appleMessagesTextDiagnostics {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Messages Text Check")
                            .font(.headline)
                        Text("Since \(diagnostics.checkedSince.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(diagnostics.outgoingWithPlainText) sent rows have plain text. \(diagnostics.recoveredOutgoingWithoutPlainTextCount) sent rows can be recovered from alternate message payloads. \(diagnostics.outgoingUnresolvedAfterDecode) sent rows are still unresolved.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if model.appleMessagesDecodeTraceReport == nil {
                    Text("Run the Mom/Hunter trace after granting Full Disk Access to see exactly where each outgoing body is stored. Snippets stay in memory and are not written to Loop storage.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
    }
}

private struct OnboardingMessagesDecodeTraceView: View {
    var report: AppleMessagesDecodeTraceReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Messages Decode Trace", systemImage: "text.magnifyingglass")
                    .font(.headline)
                Spacer()
                Text(report.checkedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text("\(report.threadMatches.count) chat matches. \(report.outgoingRowCount) sent rows. \(report.placeholderRowCount) placeholders.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if !report.unmatchedTitles.isEmpty {
                Text("No matching chat title or contact-resolved participant found for \(report.unmatchedTitles.joined(separator: ", ")).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(report.threadMatches) { thread in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(thread.chatTitle) · \(thread.chatKind.displayName)")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(thread.outgoingRows.count) sent")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Text(thread.chatGUID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    if thread.outgoingRows.isEmpty {
                        Text("No outgoing rows found since \(report.checkedSince.formatted(date: .abbreviated, time: .shortened)).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(thread.outgoingRows) { row in
                            OnboardingMessagesDecodeTraceRowView(row: row)
                        }
                    }
                }
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }

            Text("Temporary local trace only. Snippets are not written to Loop storage or files.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct OnboardingMessagesDecodeTraceRowView: View {
    var row: AppleMessagesDecodeTraceRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(row.failureReason == nil ? "Readable" : "Placeholder", systemImage: row.failureReason == nil ? "checkmark.bubble" : "exclamationmark.bubble")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(row.failureReason == nil ? .green : .red)
                Text(row.sentAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(row.messageGUID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            OnboardingTraceLine(title: "message.text", value: messageTextValue)
            OnboardingTraceLine(title: "attributedBody", value: blobValue(row.attributedBody))
            OnboardingTraceLine(title: "payload_data", value: blobValue(row.payloadData))
            OnboardingTraceLine(title: "summary_info", value: blobValue(row.messageSummaryInfo))
            OnboardingTraceLine(title: "final body", value: row.finalBody)
            if let failureReason = row.failureReason {
                OnboardingTraceLine(title: "failure", value: failureReason, tint: .red)
            }
        }
        .padding(.vertical, 4)
        .textSelection(.enabled)
    }

    private var messageTextValue: String {
        if let snippet = row.messageTextSnippet {
            return "present, \(row.messageTextLength) chars, snippet: \(snippet)"
        }
        if row.messageTextExists {
            return "present, \(row.messageTextLength) chars, no usable text after whitespace collapse"
        }
        return "missing"
    }

    private func blobValue(_ trace: AppleMessagesBlobDecodeTrace) -> String {
        guard trace.isPresent else {
            return "missing"
        }
        var parts = ["present, \(trace.byteLength) bytes"]
        if let prefix = trace.hexPrefix {
            parts.append("prefix: \(prefix)")
        }
        if let decodedSnippet = trace.decodedSnippet {
            parts.append("decoded: \(decodedSnippet)")
        } else {
            parts.append("decoded: none")
        }
        return parts.joined(separator: " | ")
    }
}

private struct OnboardingTraceLine: View {
    var title: String
    var value: String
    var tint: Color?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 104, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(tint ?? .primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
#endif

private struct AboutStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(
                title: "About Loop",
                subtitle: "Messages-only trusted alpha for catching follow-ups, deadlines, and small tasks from local conversations."
            )

            VStack(alignment: .leading, spacing: 10) {
                AboutRow(title: "Channel", value: LoopReleaseChannel.current().displayName)
                AboutRow(title: "Bundle ID", value: Bundle.main.bundleIdentifier ?? LoopReleaseChannel.current().bundleIdentifier)
                AboutRow(title: "Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
                AboutRow(title: "Build", value: Bundle.main.object(forInfoDictionaryKey: "LoopDevBuildStamp") as? String ?? "unstamped")
                AboutRow(title: "Bundle path", value: Bundle.main.bundleURL.path)
                AboutRow(title: "Local data", value: LoopReleaseChannel.current().appSupportDirectoryName)
            }
        }
    }
}

private struct SummaryStep: View {
    @ObservedObject var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(
                title: "Setup summary",
                subtitle: "You can finish with missing optional permissions. Loop will keep showing degraded states honestly."
            )

            VStack(spacing: 10) {
                ForEach([PermissionKind.fullDiskAccess, .appleMessages, .contacts], id: \.rawValue) { kind in
                    PermissionSummaryRow(health: model.health(for: kind))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Sources")
                    .font(.headline)
                SourceSummaryRow(
                    title: "Apple Messages",
                    systemImage: "message",
                    readiness: model.messagesReadiness,
                    health: model.health(for: .appleMessages),
                    source: model.source(for: .appleMessages),
                    importResult: model.lastImportResults[.appleMessages]
                )
            }

            Text("Messages is the prototype source. Contacts are optional and only improve display names.")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct StepHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.largeTitle.weight(.semibold))
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PrincipleRow: View {
    @Environment(\.loopPalette) private var palette

    var systemImage: String
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.primary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SourceSetupCard: View {
    var title: String
    var systemImage: String
    var readiness: OnboardingReadinessState?
    var status: PermissionHealth
    var detail: String
    var primaryTitle: String?
    var primarySystemImage: String?
    var primaryDisabled = false
    var helperText: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer()
                if let readiness {
                    ReadinessPill(readiness: readiness)
                }
                HealthStatusPill(health: status)
            }

            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let primaryTitle, let primarySystemImage, let action {
                Button(action: action) {
                    Label(primaryTitle, systemImage: primarySystemImage)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(primaryDisabled)
            }

            if let helperText {
                Text(helperText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct PermissionCard: View {
    var health: PermissionHealth
    var detail: String
    var primaryTitle: String
    var primarySystemImage: String
    var primaryAction: () -> Void
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?
    var primaryDisabled = false
    var helperText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(health.kind.displayName, systemImage: health.kind.systemImage)
                    .font(.headline)
                Spacer()
                HealthStatusPill(health: health)
            }

            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(action: primaryAction) {
                    Label(primaryTitle, systemImage: primarySystemImage)
                }
                .buttonStyle(.borderedProminent)
                .disabled(primaryDisabled)

                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                }
            }
            .controlSize(.small)

            if let helperText {
                Text(helperText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct PermissionSummaryRow: View {
    var health: PermissionHealth

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: health.kind.systemImage)
                .frame(width: 22)
                .foregroundStyle(health.state.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(health.kind.displayName)
                    .font(.callout.weight(.medium))
                Text(health.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            HealthStatusPill(health: health)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SourceSummaryRow: View {
    var title: String
    var systemImage: String
    var readiness: OnboardingReadinessState
    var health: PermissionHealth
    var source: ConversationSource?
    var importResult: ImportResult?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 22)
                .foregroundStyle(health.state.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            ReadinessPill(readiness: readiness)
            HealthStatusPill(health: health)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var detail: String {
        if let importResult {
            return "Last import added \(importResult.insertedMessages), skipped \(importResult.skippedMessages)."
        }
        if let lastSyncAt = source?.lastSyncAt {
            return "Last synced \(summaryRelativeLabel(lastSyncAt))."
        }
        return health.detail
    }
}

private struct SetupPathBox: View {
    var lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ReadinessPill: View {
    var readiness: OnboardingReadinessState

    var body: some View {
        Label(readiness.rawValue, systemImage: readiness.systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(readiness.tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(readiness.tint.opacity(0.12), in: Capsule())
    }
}

private struct HealthStatusPill: View {
    var health: PermissionHealth

    var body: some View {
        Label(health.state.displayName, systemImage: health.state.systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(health.state.tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(health.state.tint.opacity(0.12), in: Capsule())
    }
}

private struct SourcePriorityPill: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

private struct AboutRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private func timeLabel(_ minutes: Int) -> String {
    let normalized = ((minutes % 1440) + 1440) % 1440
    let hour = normalized / 60
    let minute = normalized % 60
    let date = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
    return TimeFormatters.hour.string(from: date)
}

private func summaryRelativeLabel(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}

private enum TimeFormatters {
    static let hour: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

private extension PermissionKind {
    var systemImage: String {
        switch self {
        case .fullDiskAccess: return "internaldrive"
        case .appleMessages: return "message"
        case .contacts: return "person.crop.circle"
        case .notifications: return "bell"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .cloudAI: return "cloud"
        }
    }
}

private extension HealthState {
    var displayName: String {
        switch self {
        case .available: return "Available"
        case .missing: return "Missing"
        case .degraded: return "Degraded"
        case .revoked: return "Revoked"
        case .unsupported: return "Unsupported"
        }
    }

    var systemImage: String {
        switch self {
        case .available: return "checkmark.circle"
        case .missing: return "minus.circle"
        case .degraded: return "exclamationmark.circle"
        case .revoked: return "xmark.circle"
        case .unsupported: return "slash.circle"
        }
    }

    var tint: Color {
        switch self {
        case .available: return .green
        case .missing, .degraded: return .orange
        case .revoked: return .red
        case .unsupported: return .secondary
        }
    }
}

private extension OnboardingReadinessState {
    var systemImage: String {
        switch self {
        case .ready:
            return "play.circle"
        case .needsSetup:
            return "wrench.and.screwdriver"
        case .needsPermission:
            return "lock.open"
        case .connected:
            return "link.circle"
        case .imported:
            return "checkmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .ready, .connected:
            return .blue
        case .needsSetup, .needsPermission:
            return .orange
        case .imported:
            return .green
        }
    }
}

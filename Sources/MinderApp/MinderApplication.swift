import AppKit
import SwiftUI
import MinderCore

final class MinderApplication: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private static var retainedDelegate: MinderApplication?
    private static let backgroundSyncInterval: TimeInterval = 15 * 60

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var syncTimer: Timer?
    private var viewModel: MinderViewModel?
    private var store: MinderStore?
    private var permissionService: MacPermissionService?
    private var settingsViewModel: OnboardingViewModel?
    private var queueWindow: NSWindow?

    static func main() {
        let app = NSApplication.shared
        let delegate = MinderApplication()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let store = try MinderStore()
            let permissionService = MacPermissionService()
            let messagesImporter = AppleMessagesConversationImporter(contactResolver: MacContactResolver())
            self.store = store
            self.permissionService = permissionService

            let model = MinderViewModel(
                store: store,
                permissionService: permissionService,
                messagesImporter: messagesImporter
            )
            model.showQueueWindow = { [weak self] in
                Task { @MainActor in
                    self?.showQueueWindow()
                }
            }
            viewModel = model

            let settingsModel = makeSettingsViewModel(
                store: store,
                permissionService: permissionService,
                messagesImporter: messagesImporter
            )
            settingsViewModel = settingsModel

            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentSize = NSSize(width: 760, height: 820)
            popover.contentViewController = NSHostingController(rootView: InboxView(model: model, settingsModel: settingsModel))
            self.popover = popover

            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem.button?.image = NSImage(systemSymbolName: "checklist.checked", accessibilityDescription: "Loop")
            statusItem.button?.title = " Loop"
            statusItem.button?.target = self
            statusItem.button?.action = #selector(togglePopover)
            self.statusItem = statusItem

            model.refresh()
            model.refreshPermissionHealth()
            if model.profile?.hasCompletedOnboarding != true {
                model.openSetup()
                showPopover()
            } else {
                startBackgroundSync()
            }
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
        }
    }

    @MainActor
    @objc private func togglePopover() {
        guard let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    @MainActor
    private func showPopover() {
        guard let button = statusItem?.button, let popover else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func makeSettingsViewModel(
        store: MinderStore,
        permissionService: MacPermissionService,
        messagesImporter: AppleMessagesConversationImporter
    ) -> OnboardingViewModel {
        OnboardingViewModel(
            store: store,
            permissionService: permissionService,
            messagesImporter: messagesImporter,
            onComplete: { [weak self] in
                self?.viewModel?.refresh()
                self?.viewModel?.selectedTab = .queue
                self?.startBackgroundSync()
            },
            onChange: { [weak self] in
                self?.viewModel?.refresh()
            }
        )
    }

    @MainActor
    private func showQueueWindow() {
        if let queueWindow {
            queueWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let viewModel, let settingsViewModel else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Loop Queue"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: InboxView(model: viewModel, settingsModel: settingsViewModel))
        window.delegate = self
        queueWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func startBackgroundSync() {
        guard syncTimer == nil else { return }
        syncTimer = Timer.scheduledTimer(withTimeInterval: Self.backgroundSyncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.viewModel?.syncAndGenerateSuggestions(reason: .periodic)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        syncTimer?.invalidate()
        syncTimer = nil
    }
}

extension MinderApplication: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === queueWindow {
            queueWindow = nil
        }
    }
}

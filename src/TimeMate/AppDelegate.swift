//  Created by homielab.com

import AppKit
import Combine
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

  // MARK: - Properties
  private var statusItem: NSStatusItem!
  private var popover: NSPopover!
  private let timer = PomodoroTimer()
  private var hostingController: NSHostingController<AnyView>!
  private let sleepPreventer = SleepPreventer()
  private var breakOverlayController: BreakOverlayWindowController!
  private var desktopWidgetController: DesktopWidgetWindowController!
  private var menuBarCancellables = Set<AnyCancellable>()
  @AppStorage("hideMenuBarTime") private var hideMenuBarTime = false

  private func menuBarWidth() -> CGFloat {
    if hideMenuBarTime { return 24.0 }
    let seconds = timer.displayTime
    if seconds >= 36000 { return 132.0 }  // HH:MM:SS
    if seconds >= 3600 { return 120.0 }   // H:MM:SS
    return 90.0                           // MM:SS
  }

  // MARK: - App Lifecycle
  func applicationDidFinishLaunching(_ notification: Notification) {
    self.setDockIcon(hidden: UserDefaults.standard.hideDockIcon)
    self.setKeepAwake(enabled: UserDefaults.standard.keepAwake)

    // Register defaults
    UserDefaults.standard.register(defaults: [
      "overlayEnabled": true,
      "notificationsEnabled": true,
      "keepAwake": false,
      "hideDockIcon": true,
      "alwaysVisible": false,
      "showProgressCircle": true,
      "autoStartNextSession": true,
      "showDesktopWidget": true,
    ])

    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
      _, _ in
    }

    NSColorPanel.shared.showsAlpha = true

    let initialWidth = menuBarWidth()
    statusItem = NSStatusBar.system.statusItem(withLength: initialWidth)

    let menuBarView = MenuBarView(timer: timer, hideTime: $hideMenuBarTime)
    let hostingView = PassThroughHostingView(rootView: AnyView(menuBarView))
    hostingView.frame = NSRect(
      x: 0, y: 0, width: initialWidth, height: NSStatusBar.system.thickness)

    statusItem.button?.subviews.forEach { $0.removeFromSuperview() }
    statusItem.button?.addSubview(hostingView)
    hostingView.frame = statusItem.button?.bounds ?? .zero

    statusItem.button?.target = self
    statusItem.button?.action = #selector(togglePopover)

    // --- Popover Setup ---
    let contentView = ContentView().environmentObject(timer).environmentObject(self)
    hostingController = NSHostingController(rootView: AnyView(contentView))
    popover = NSPopover()
    popover.behavior = .transient
    popover.contentViewController = hostingController

    // --- Initial State ---
    updatePopoverSize()
    NSApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      self.togglePopover()
    }

    // --- Break Overlay ---
    breakOverlayController = BreakOverlayWindowController(timer: timer)

    // --- Desktop Widget ---
    desktopWidgetController = DesktopWidgetWindowController(timer: timer)

    // Resize the menu bar slot when the displayed time changes (e.g. crosses 1h boundary)
    timer.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self] in
        guard let self = self else { return }
        let newWidth = self.menuBarWidth()
        if self.statusItem.length != newWidth {
          self.statusItem.length = newWidth
          self.statusItem.button?.subviews.first?.frame =
            self.statusItem.button?.bounds ?? .zero
        }
      }
      .store(in: &menuBarCancellables)
  }

  func updatePopoverSize() {
    DispatchQueue.main.async {
      self.popover.contentSize = self.hostingController.view.fittingSize
    }
  }

  func setDockIcon(hidden: Bool) {
    NSApp.setActivationPolicy(hidden ? .accessory : .regular)
  }

  func setKeepAwake(enabled: Bool) {
    if enabled {
      sleepPreventer.enable()
    } else {
      sleepPreventer.disable()
    }
  }

  func setPopoverBehavior(alwaysVisible: Bool) {
    // Always use transient behavior to allow closing on outside clicks
    popover.behavior = .transient
  }

  func updateMenuBarWidth(hideTime: Bool) {
    let newWidth = menuBarWidth()
    let wasShown = popover.isShown

    // Close popover if shown to reposition it
    if wasShown {
      popover.performClose(nil)
    }

    statusItem.length = newWidth

    // Recreate the menu bar view to force immediate refresh
    let menuBarView = MenuBarView(timer: timer, hideTime: $hideMenuBarTime)
    let hostingView = PassThroughHostingView(rootView: AnyView(menuBarView))
    hostingView.frame = NSRect(x: 0, y: 0, width: newWidth, height: NSStatusBar.system.thickness)

    statusItem.button?.subviews.forEach { $0.removeFromSuperview() }
    statusItem.button?.addSubview(hostingView)
    hostingView.frame = statusItem.button?.bounds ?? .zero

    // Reopen popover if it was shown
    if wasShown {
      DispatchQueue.main.async {
        self.togglePopover()
      }
    }
  }

  @objc func togglePopover() {
    guard let button = statusItem.button else { return }

    if popover.isShown {
      popover.performClose(nil)
    } else {
      NSApp.activate(ignoringOtherApps: true)
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
  }

  // MARK: - Reopen Window from Dock
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    if !popover.isShown {
      togglePopover()
    }
    return true
  }
}

// MARK: - Pass-through hosting view for menu bar (allows clicks to reach NSStatusBarButton)
// NOTE: Using AnyView instead of a generic parameter to work around a Swift 6.2 compiler crash
// in the SIL optimizer (EarlyPerfInliner) when processing the deinit of generic NSHostingView subclasses.
private class PassThroughHostingView: NSHostingView<AnyView> {
  override func hitTest(_ point: NSPoint) -> NSView? {
    // Return nil so that clicks pass through to the underlying NSStatusBarButton
    return nil
  }
}

private struct MenuBarView: View {
  @ObservedObject var timer: PomodoroTimer
  @Binding var hideTime: Bool

  private var iconName: String {
    timer.statusIconName
  }

  private var accentColor: Color {
    timer.statusAccentColor
  }

  private var foregroundColor: Color {
    if timer.state == .active {
      return .white
    }
    return Color(nsColor: .headerTextColor)
  }

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: iconName)
        .font(.system(size: NSFont.systemFontSize + 2))
        .padding(.horizontal, 4)
        .background(
          RoundedRectangle(cornerRadius: 4)
            .fill(timer.state == .active ? accentColor : .clear)
        )
        .foregroundColor(timer.state == .active ? .white : Color(nsColor: .headerTextColor))

      if !hideTime {
        Text(timer.displayTime.toHourMinuteSecondString())
          .font(.system(size: NSFont.systemFontSize + 1, design: .monospaced).weight(.bold))
          .foregroundColor(foregroundColor)
      }
    }
    .frame(width: frameWidth, height: NSStatusBar.system.thickness, alignment: .center)
  }

  private var frameWidth: CGFloat {
    if hideTime { return 24 }
    let seconds = timer.displayTime
    if seconds >= 36000 { return 132 }
    if seconds >= 3600 { return 120 }
    return 90
  }
}

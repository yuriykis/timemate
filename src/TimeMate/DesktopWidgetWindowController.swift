import AppKit
import Combine
import SwiftUI

/// Panel that never takes focus, so it stays a passive part of the desktop.
private class DesktopWidgetPanel: NSPanel {
  override var canBecomeKey: Bool {
    return false
  }

  override var canBecomeMain: Bool {
    return false
  }
}

/// Rounded material background that swallows plain clicks and moves the window only on ⌥-drag.
private class DesktopWidgetContainerView: NSVisualEffectView {
  var onDragEnded: (() -> Void)?
  private var dragStart: (mouse: NSPoint, origin: NSPoint)?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return true
  }

  override func mouseDown(with event: NSEvent) {
    guard event.modifierFlags.contains(.option), let window = window else { return }
    dragStart = (window.convertPoint(toScreen: event.locationInWindow), window.frame.origin)
    NSCursor.closedHand.push()
  }

  override func mouseDragged(with event: NSEvent) {
    guard let start = dragStart, let window = window else { return }
    let mouse = window.convertPoint(toScreen: event.locationInWindow)
    window.setFrameOrigin(
      NSPoint(
        x: start.origin.x + mouse.x - start.mouse.x,
        y: start.origin.y + mouse.y - start.mouse.y))
  }

  override func mouseUp(with event: NSEvent) {
    guard dragStart != nil else { return }
    dragStart = nil
    NSCursor.pop()
    onDragEnded?()
  }
}

// NOTE: AnyView instead of a generic parameter, same Swift 6.2 workaround as in AppDelegate.
private class DesktopWidgetHostingView: NSHostingView<AnyView> {
  override func hitTest(_ point: NSPoint) -> NSView? {
    // Let the container handle every mouse event
    return nil
  }
}

/// Read-only timer window pinned just above the desktop icons, below all app windows.
/// Visible only while a session is running or paused.
class DesktopWidgetWindowController: NSObject {
  private static let size = NSSize(width: 232, height: 100)
  private static let cornerRadius: CGFloat = 22
  private static let bottomMargin: CGFloat = 24
  private static let originKey = "desktopWidgetOrigin"

  private let timer: PomodoroTimer
  private let panel: DesktopWidgetPanel
  private var cancellables = Set<AnyCancellable>()

  init(timer: PomodoroTimer) {
    self.timer = timer
    self.panel = DesktopWidgetPanel(
      contentRect: NSRect(origin: .zero, size: Self.size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: true
    )
    super.init()
    configurePanel()
    restorePosition()
    setupSubscriptions()

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleScreenConfigurationChange),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
  }

  private func configurePanel() {
    panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.isMovable = false
    panel.hidesOnDeactivate = false
    panel.isExcludedFromWindowsMenu = true
    panel.isReleasedWhenClosed = false

    let container = DesktopWidgetContainerView(frame: NSRect(origin: .zero, size: Self.size))
    container.material = .popover
    container.blendingMode = .behindWindow
    container.state = .active
    container.maskImage = Self.roundedMask(cornerRadius: Self.cornerRadius)
    container.onDragEnded = { [weak self] in self?.savePosition() }

    let hostingView = DesktopWidgetHostingView(rootView: AnyView(DesktopWidgetView(timer: timer)))
    hostingView.frame = container.bounds
    hostingView.autoresizingMask = [.width, .height]
    container.addSubview(hostingView)

    panel.contentView = container
  }

  private func setupSubscriptions() {
    timer.$state
      .combineLatest(UserDefaults.standard.publisher(for: \.showDesktopWidget))
      .sink { [weak self] state, enabled in
        self?.setVisible(enabled && state != .idle)
      }
      .store(in: &cancellables)
  }

  private func setVisible(_ visible: Bool) {
    if visible {
      if !panel.isVisible {
        panel.orderFrontRegardless()
      }
    } else {
      panel.orderOut(nil)
    }
  }

  // MARK: - Position

  private func restorePosition() {
    var frame = defaultFrame()
    if let saved = UserDefaults.standard.string(forKey: Self.originKey) {
      frame.origin = NSPointFromString(saved)
    }
    panel.setFrame(clampedToScreen(frame), display: false)
  }

  private func savePosition() {
    let frame = clampedToScreen(panel.frame)
    panel.setFrame(frame, display: true)
    UserDefaults.standard.set(NSStringFromPoint(frame.origin), forKey: Self.originKey)
  }

  @objc private func handleScreenConfigurationChange() {
    restorePosition()
  }

  /// Bottom-centre of the main screen.
  private func defaultFrame() -> NSRect {
    guard let screen = NSScreen.screens.first else {
      return NSRect(origin: .zero, size: Self.size)
    }
    let bounds = screen.visibleFrame
    return NSRect(
      x: bounds.midX - Self.size.width / 2, y: bounds.minY + Self.bottomMargin,
      width: Self.size.width, height: Self.size.height)
  }

  /// Keeps the widget fully inside the screen that shows most of it; falls back to the default
  /// spot when it is on no screen at all (e.g. the saved display was disconnected).
  private func clampedToScreen(_ frame: NSRect) -> NSRect {
    let overlap = { (screen: NSScreen) -> CGFloat in
      let area = screen.visibleFrame.intersection(frame)
      return area.isNull ? 0 : area.width * area.height
    }
    guard let screen = NSScreen.screens.max(by: { overlap($0) < overlap($1) }),
      overlap(screen) > 0
    else { return defaultFrame() }

    let bounds = screen.visibleFrame
    var clamped = frame
    clamped.origin.x = min(max(frame.minX, bounds.minX), bounds.maxX - frame.width)
    clamped.origin.y = min(max(frame.minY, bounds.minY), bounds.maxY - frame.height)
    return clamped
  }

  private static func roundedMask(cornerRadius: CGFloat) -> NSImage {
    let edge = cornerRadius * 2 + 1
    let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
      NSColor.black.setFill()
      NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
      return true
    }
    image.capInsets = NSEdgeInsets(
      top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
    image.resizingMode = .stretch
    return image
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}

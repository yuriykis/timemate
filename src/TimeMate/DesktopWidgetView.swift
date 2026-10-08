import SwiftUI

/// Display-only content of the desktop widget: session phase and the same time as the menu bar.
struct DesktopWidgetView: View {
  @ObservedObject var timer: PomodoroTimer

  private var sessionLabel: LocalizedStringKey {
    if timer.timerMode == .countUp {
      return LocalizedStringKey("Count Up")
    }
    return LocalizedStringKey(timer.currentSessionType.rawValue)
  }

  var body: some View {
    VStack(spacing: 2) {
      HStack(spacing: 6) {
        Image(systemName: timer.statusIconName)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(.white)
          .frame(width: 24, height: 18)
          .background(
            RoundedRectangle(cornerRadius: 5)
              .fill(timer.statusAccentColor)
          )
        Text(sessionLabel)
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.secondary)
      }

      Text(timer.displayTime.toHourMinuteSecondString())
        .font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
        .foregroundColor(timer.statusAccentColor)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
    .padding(.horizontal, 16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .opacity(timer.state == .paused ? 0.5 : 1)
  }
}

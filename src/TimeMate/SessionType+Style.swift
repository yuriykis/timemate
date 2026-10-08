//  Created by homielab.com

import SwiftUI

struct SessionStyle {
  let color: Color
  let iconName: String
}

extension SessionType {
  var style: SessionStyle {
    switch self {
    case .focus:
      return SessionStyle(
        color: .accentColor,
        iconName: "brain.head.profile"
      )
    case .shortBreak:
      return SessionStyle(
        color: .green,
        iconName: "cup.and.saucer.fill"
      )
    case .longBreak:
      return SessionStyle(
        color: .teal,
        iconName: "chair.lounge.fill"
      )
    }
  }
}

extension PomodoroTimer {
  /// Icon for the current timer state, shared by the menu bar and the desktop widget.
  var statusIconName: String {
    if timerMode == .countUp {
      switch state {
      case .paused: return "pause.circle.fill"
      case .idle: return "stopwatch"
      case .active: return "stopwatch.fill"
      }
    }
    switch state {
    case .paused:
      return "pause.circle.fill"
    case .idle:
      return "timer"
    case .active:
      return currentSessionType == .focus ? "play.circle.fill" : currentSessionType.style.iconName
    }
  }

  /// Phase colour for the current timer state, shared by the menu bar and the desktop widget.
  var statusAccentColor: Color {
    if timerMode == .countUp {
      return state == .paused ? .orange : .purple
    }
    if state == .paused {
      return .orange
    }
    let activeColor = currentSessionType.style.color

    if currentSessionType == .shortBreak || currentSessionType == .longBreak {
      return activeColor.opacity(0.8)
    }
    return activeColor
  }
}

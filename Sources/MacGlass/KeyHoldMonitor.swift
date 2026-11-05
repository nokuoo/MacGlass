import AppKit
import CoreGraphics
import Foundation

/// 监听真实键盘的按下与松开，用来实现按住连续调整。
/// Carbon 热键只保证“按一次”回调，长按期间可能提前收到释放事件，因此这里单独
/// 用事件监听跟踪物理按键状态，松手时才停止连调。
@MainActor
final class KeyHoldMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pressedKeyCodes = Set<CGKeyCode>()
    private(set) var isActive = false
    private let onPress: (CGKeyCode) -> Void
    private let onRelease: (CGKeyCode) -> Void

    init(
        onPress: @escaping (CGKeyCode) -> Void,
        onRelease: @escaping (CGKeyCode) -> Void
    ) {
        self.onPress = onPress
        self.onRelease = onRelease
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }
        guard AXIsProcessTrusted() else { return false }

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: keyHoldCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isActive = true
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        pressedKeyCodes.removeAll()
        isActive = false
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        // 系统可能因超时禁用事件监听，这里自动恢复。
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                isActive = true
            }
            return
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == 123 || keyCode == 124 else { return }

        switch type {
        case .keyDown:
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            guard !isRepeat else { return }
            guard event.flags.contains(.maskControl),
                  event.flags.contains(.maskAlternate) else {
                release(keyCode)
                return
            }
            guard !pressedKeyCodes.contains(keyCode) else { return }
            pressedKeyCodes.insert(keyCode)
            onPress(keyCode)

        case .keyUp:
            release(keyCode)

        case .flagsChanged:
            guard !event.flags.contains(.maskControl)
                || !event.flags.contains(.maskAlternate) else {
                return
            }
            for held in pressedKeyCodes {
                release(held)
            }

        default:
            break
        }
    }

    private func release(_ keyCode: CGKeyCode) {
        guard pressedKeyCodes.remove(keyCode) != nil else { return }
        onRelease(keyCode)
    }
}

/// CGEventTap 回调必须是 C 函数指针，不能捕获 Swift 上下文。
private func keyHoldCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<KeyHoldMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    let typeValue = type
    let eventValue = event

    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            monitor.handle(type: typeValue, event: eventValue)
        }
    }
    return Unmanaged.passUnretained(event)
}

import AppKit
import Carbon.HIToolbox

/// 全局快捷键使用 Carbon RegisterEventHotKey，不依赖辅助功能权限，也不会拦截其他应用按键。
final class GlobalHotKey: @unchecked Sendable {
    fileprivate struct Callbacks {
        let onPress: () -> Void
        let onRelease: () -> Void
    }

    fileprivate static let signature: OSType = 0x5747_4C53
    private static var nextID: UInt32 = 1
    fileprivate static var handlers: [UInt32: Callbacks] = [:]
    private static var eventHandler: EventHandlerRef?

    private let hotKeyID: UInt32
    private var hotKeyRef: EventHotKeyRef?

    @MainActor
    init?(
        keyCode: UInt32,
        modifiers: UInt32,
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void
    ) {
        Self.installEventHandlerIfNeeded()

        hotKeyID = Self.nextID
        Self.nextID += 1
        Self.handlers[hotKeyID] = Callbacks(
            onPress: onPress,
            onRelease: onRelease
        )

        let eventHotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: hotKeyID
        )
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            eventHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else {
            Self.handlers.removeValue(forKey: hotKeyID)
            return nil
        }
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        // deinit 可能不在主线程；这里只移除本实例的闭包，避免留下悬空回调。
        Self.handlers[hotKeyID] = nil
    }

    private static func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        let eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]
        _ = eventTypes.withUnsafeBufferPointer { buffer in
            InstallEventHandler(
                GetApplicationEventTarget(),
                hotKeyEventHandler,
                buffer.count,
                buffer.baseAddress,
                nil,
                &eventHandler
            )
        }
    }
}

/// Carbon 要求 C 函数指针，不能捕获 Swift 闭包上下文。
private func hotKeyEventHandler(
    _ handler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == GlobalHotKey.signature else {
        return OSStatus(eventNotHandledErr)
    }

    let callbacks = GlobalHotKey.handlers[hotKeyID.id]
    let kind = GetEventKind(event)
    DispatchQueue.main.async {
        if kind == UInt32(kEventHotKeyPressed) {
            callbacks?.onPress()
        } else if kind == UInt32(kEventHotKeyReleased) {
            callbacks?.onRelease()
        }
    }
    return noErr
}

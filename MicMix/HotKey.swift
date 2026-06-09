//
//  HotKey.swift
//  MicMix
//
//  Global hotkey via Carbon. Default: Control + Option + M.
//

import AppKit
import Carbon.HIToolbox

final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var id = EventHotKeyID(signature: OSType(0x4D4D5848 /* 'MMXH' */), id: 1)
    private var handler: (() -> Void)?

    /// Pass a distinct `id` for each instance so two `HotKey` objects in the same
    /// process can coexist — each handler is installed on the shared application
    /// target, so we must filter by id to avoid one combo firing the other's callback.
    func register(keyCode: UInt32 = UInt32(kVK_ANSI_M),
                  modifiers: UInt32 = UInt32(controlKey | optionKey),
                  id: UInt32 = 1,
                  handler: @escaping () -> Void) {
        self.id = EventHotKeyID(signature: OSType(0x4D4D5848 /* 'MMXH' */), id: id)
        self.handler = handler

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { (_, eventRef, userData) -> OSStatus in
            guard let eventRef, let userData else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(eventRef,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &hkID)
            let me = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            guard hkID.id == me.id.id else { return noErr }
            DispatchQueue.main.async { me.handler?() }
            return noErr
        }, 1, &eventType, selfPtr, &eventHandler)

        RegisterEventHotKey(keyCode, modifiers, self.id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

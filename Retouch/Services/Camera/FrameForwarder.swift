//
//  FrameForwarder.swift
//  Retouch
//
//  Created by Davin P on 26/10/26.
//


import CoreVideo

nonisolated final class FrameForwarder: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (CVPixelBuffer) -> Void)?

    func setHandler(_ handler: (@Sendable (CVPixelBuffer) -> Void)?) {
        lock.withLock { self.handler = handler }
    }

    func send(_ buffer: CVPixelBuffer) {
        let handler = lock.withLock { self.handler }
        handler?(buffer)
    }
}

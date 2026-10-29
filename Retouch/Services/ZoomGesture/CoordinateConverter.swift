//
//  CoordinateConverter.swift
//  Retouch
//
//  Created by Davin P on 25/10/26.
//


import CoreGraphics

nonisolated struct CoordinateConverter {
    let imageSize: CGSize
    let viewSize: CGSize

    private var scale: CGFloat {
        max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
    }

    func toView(_ p: CGPoint) -> CGPoint {
        let s = scale
        let w = imageSize.width * s
        let h = imageSize.height * s
        let ox = (viewSize.width - w) / 2
        let oy = (viewSize.height - h) / 2
        return CGPoint(x: ox + p.x * w, y: oy + (1 - p.y) * h)
    }

    func width(_ normalized: CGFloat) -> CGFloat {
        normalized * imageSize.width * scale
    }
}

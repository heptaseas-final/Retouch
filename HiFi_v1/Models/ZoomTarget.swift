//
//  ZoomTarget.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//

import CoreGraphics

nonisolated enum FaceSide { case left, right }

nonisolated enum ZoomTarget: Equatable {
    case fullFace, leftEye, rightEye, lips, forehead
    case faceSide(FaceSide)

    var zoomScale: CGFloat {
        switch self {
        case .fullFace: 1.1
        case .leftEye, .rightEye: 2.5
        case .lips: 2.0
        case .forehead: 1.75
        case .faceSide: 1.4
        }
    }
}

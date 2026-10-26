//
//  ZoomState.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//
import CoreGraphics

nonisolated struct ZoomState: Equatable {
    var scale: CGFloat = 1
    var offset: CGSize = .zero
}

//
//  PreviewView.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//


import UIKit
import AVFoundation

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
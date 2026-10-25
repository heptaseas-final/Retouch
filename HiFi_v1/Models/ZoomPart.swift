//
//  ZoomPart.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//


enum ZoomPart: CaseIterable, Identifiable {
    case face, leftEye, rightEye, lips

    var id: Self { self }

    var systemName: String {
        switch self {
        case .face: "face.smiling.inverse"
        case .leftEye, .rightEye: "eye.fill"
        case .lips: "mouth.fill"
        }
    }
    
    var target: ZoomTarget {
        switch self {
        case .face: .fullFace
        case .leftEye: .leftEye
        case .rightEye: .rightEye
        case .lips: .lips
        }
    }

    var letter: String? {
        switch self {
        case .leftEye: "L"
        case .rightEye: "R"
        default: nil
        }
    }
}

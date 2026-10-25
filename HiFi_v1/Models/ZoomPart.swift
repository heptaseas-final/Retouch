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

    var letter: String? {
        switch self {
        case .leftEye: "L"
        case .rightEye: "R"
        default: nil
        }
    }
}
//
//  FacePart.swift
//  Retouch
//
//  Created by Gabriella Angelina Widjaja on 06/11/26.
//


import SwiftUI

enum FacePart: CaseIterable, Identifiable {
    case leftEye, rightEye, face, mouth, nose, smile

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .leftEye, .rightEye: "eye.fill"
        case .face:               "person.fill.viewfinder"
        case .mouth:              "mouth.fill"
        case .nose:               "nose.fill"
        case .smile:              "face.smiling.inverse"
        }
    }

    var label: String? {
        switch self {
        case .leftEye:  "L"
        case .rightEye: "R"
        default:        nil
        }
    }

    var title: String {
        switch self {
        case .leftEye:  "Left eye"
        case .rightEye: "Right eye"
        case .face:     "Face"
        case .mouth:    "Mouth"
        case .nose:     "Nose"
        case .smile:    "Smile"
        }
    }
}


#Preview {
    struct Demo: View {
        @State private var part: FacePart = .mouth

        var body: some View {
            HorizontalPicker(
                items: FacePart.allCases,
                selection: $part,
                itemWidth: 88,
                onSelect: { print("Selected:", $0.title) }
            ) { part, isSelected in
                PickerSymbol(
                    systemName: part.systemImage,
                    label: part.label,
                    isSelected: isSelected
                )
                .accessibilityLabel(part.title)
            }
            .frame(width: 300)
            .padding()
        }
    }
    return Demo()
}

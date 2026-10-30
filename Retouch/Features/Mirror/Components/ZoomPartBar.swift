//
//  ZoomPartBar.swift
//  Retouch
//
//  Created by Davin P on 25/10/26.
//

import SwiftUI

struct ZoomPartBar: View {
    let selected: ZoomPart
    let onSelect: (ZoomPart) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ZoomPart.allCases) { part in
                Button { onSelect(part) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: part.systemName)
                        if let letter = part.letter {
                            Text(letter).fontWeight(.semibold)
                        }
                    }
                    .font(.title3)
                    .foregroundStyle(part == selected ? Color.appMagenta : Color.appInactive)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background {
                        if part == selected {
                            Capsule().fill(.white.opacity(0.6))
                                .overlay(Capsule().stroke(.white.opacity(0.8), lineWidth: 1))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassStyle(in: Capsule())
    }
}

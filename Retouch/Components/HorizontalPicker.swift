//
//  HorizontalPicker.swift
//  Retouch
//
//  Created by Gabriella Angelina Widjaja on 06/11/26.
//


import SwiftUI

struct HorizontalPicker<Item: Identifiable, Content: View, Indicator: View, Background: View>: View
    where Item.ID: Hashable
{
    let items: [Item]
    @Binding var selection: Item.ID
    var itemWidth: CGFloat
    var height: CGFloat
    var indicatorWidth: CGFloat
    var clipShape: AnyShape
    var onSelect: ((Item) -> Void)?
    let content: (Item, Bool) -> Content
    let indicator: () -> Indicator
    let background: () -> Background

    @State private var scrolledID: Item.ID?

    init(
        items: [Item],
        selection: Binding<Item.ID>,
        itemWidth: CGFloat = 88,
        height: CGFloat = 56,
        indicatorWidth: CGFloat? = nil,
        clipShape: AnyShape = AnyShape(Capsule()),
        onSelect: ((Item) -> Void)? = nil,
        @ViewBuilder content: @escaping (Item, Bool) -> Content,
        @ViewBuilder indicator: @escaping () -> Indicator,
        @ViewBuilder background: @escaping () -> Background
    ) {
        self.items = items
        self._selection = selection
        self.itemWidth = itemWidth
        self.height = height
        self.indicatorWidth = indicatorWidth ?? itemWidth + 24
        self.clipShape = clipShape
        self.onSelect = onSelect
        self.content = content
        self.indicator = indicator
        self.background = background
    }

    var body: some View {
        ZStack {
            indicator()
                .frame(width: indicatorWidth, height: height)
                .allowsHitTesting(false)

            GeometryReader { proxy in
                let side = max((proxy.size.width - itemWidth) / 2, 0)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(items) { item in
                            content(item, item.id == selection)
                                .frame(width: itemWidth, height: height)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.snappy) { scrolledID = item.id }
                                }
                                .id(item.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrolledID, anchor: .center)
                .contentMargins(.horizontal, side, for: .scrollContent)
            }
            .clipShape(clipShape)
        }
        .frame(height: height)
        .background { background().clipShape(clipShape) }
        .sensoryFeedback(.selection, trigger: selection)
        .onAppear { scrolledID = selection }
        .onChange(of: scrolledID) { _, newValue in
            guard let newValue, newValue != selection else { return }
            selection = newValue
            if let item = items.first(where: { $0.id == newValue }) {
                onSelect?(item)
            }
        }
        .onChange(of: selection) { _, newValue in
            if scrolledID != newValue {
                withAnimation(.snappy) { scrolledID = newValue }
            }
        }
    }
}

extension HorizontalPicker where Indicator == PickerIndicator, Background == PickerBackground {
    init(
        items: [Item],
        selection: Binding<Item.ID>,
        itemWidth: CGFloat = 72,
        height: CGFloat = 56,
        indicatorWidth: CGFloat? = nil,
        indicatorInset: CGFloat = 0,
        onSelect: ((Item) -> Void)? = nil,
        @ViewBuilder content: @escaping (Item, Bool) -> Content
    ) {
        self.init(
            items: items,
            selection: selection,
            itemWidth: itemWidth,
            height: height,
            indicatorWidth: indicatorWidth,
            onSelect: onSelect,
            content: content,
            indicator: { PickerIndicator(inset: indicatorInset) },
            background: { PickerBackground() }
        )
    }
}

struct PickerBackground: View {
    var body: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(Capsule().fill(Color.white.opacity(0.6)))
    }
}

struct PickerIndicator: View {
    /// Jarak kapsul aktif dari tepi area indikator (membuatnya lebih kecil dari tinggi picker).
    var inset: CGFloat = 0

    var body: some View {
        indicator.padding(inset)
    }

    private var indicator: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [.white, Color(white: 0.94)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }
}

struct PickerSymbol: View {
    let systemName: String
    var label: String? = nil
    let isSelected: Bool
    var selectedTint: Color = Color(red: 0.55, green: 0.23, blue: 0.35)
    var unselectedTint: Color = .black.opacity(0.75)
    var size: CGFloat = 24

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: size))
            if let label {
                Text(label)
                    .font(.system(size: size * 0.85, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(isSelected ? selectedTint : unselectedTint)
        .scaleEffect(isSelected ? 1.0 : 0.85)
        .opacity(isSelected ? 1.0 : 0.7)
        .animation(.snappy, value: isSelected)
    }
}


private enum PreviewPart: String, CaseIterable, Identifiable {
    case face, lips, nose
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .face: return "person.crop.square"
        case .lips: return "mouth.fill"
        case .nose: return "nose.fill"
        }
    }
}

#Preview("Default style") {
    struct Demo: View {
        @State private var selected = PreviewPart.lips.id
        var body: some View {
            HorizontalPicker(
                items: PreviewPart.allCases,
                selection: $selected,
                onSelect: { print("Selected:", $0) }
            ) { part, isSelected in
                PickerSymbol(systemName: part.symbol, isSelected: isSelected)
            }
            .frame(width: 290)
            .padding()
        }
    }
    return Demo()
}

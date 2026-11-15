import SwiftUI
import UIKit

// The tab bar: a floating frosted pill with Home, Reels, the Create key, Messages and Library.
// Create is not a tab. It opens the camera over everything.

struct LiveTabBar: View {
    @ObservedObject private var nav = LiveNav.shared
    @Environment(\.colorScheme) private var scheme
    @Namespace private var highlight

    /// Five slots fit on an iPhone SE at this width.
    private let slot: CGFloat = 60

    var body: some View {
        HStack(spacing: 0) {
            item(0, symbol: "person.2.fill", title: "Community")
            item(1, symbol: "play.rectangle.on.rectangle.fill", title: "Reels")
            LiveCreateKey()
                .frame(width: slot + 4)
                .offset(y: -12)
            item(3, symbol: "bubble.left.and.bubble.right.fill", title: "Messages")
            item(4, symbol: "square.stack.fill", title: "Library")
        }
        .padding(5)
        .background {
            Capsule().fill(.regularMaterial)
                .overlay(Capsule().strokeBorder(DL.line.opacity(0.7), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        }
        // Videos is dark whatever the appearance, so the bar is too.
        .environment(\.colorScheme, nav.tab == 1 ? .dark : scheme)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }

    private func item(_ index: Int, symbol: String, title: String) -> some View {
        let chosen = nav.tab == index
        return Image(systemName: symbol)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(chosen ? DL.ink : DL.ink3)
            .frame(width: slot, height: 48)
            .background {
                if chosen {
                    Capsule().fill(DL.ink.opacity(0.1)).matchedGeometryEffect(id: "chosen", in: highlight)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { select(index) }
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityAddTraits(chosen ? AccessibilityTraits([.isButton, .isSelected]) : .isButton)
    }

    private func select(_ index: Int) {
        if LiveStore.shared.s.haptics { UISelectionFeedbackGenerator().selectionChanged() }
        withAnimation(.snappy(duration: 0.3)) { nav.tab = index }
    }
}

/// The gold plus in the middle of the bar. It sits on a darker lip like our keys and springs down when pressed.
struct LiveCreateKey: View {
    var body: some View {
        Button {
            if LiveStore.shared.s.haptics { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            LiveNav.shared.open(.create(nil))
        } label: {
            Image(systemName: "plus").font(.system(size: 24, weight: .black))
        }
        .buttonStyle(CreateKeyStyle())
        .accessibilityLabel("Create")
    }

    private struct CreateKeyStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            let down = configuration.isPressed
            let size: CGFloat = 56, lip: CGFloat = 5
            let shape = RoundedRectangle(cornerRadius: 19, style: .continuous)
            configuration.label
                .foregroundStyle(DL.onGold)
                .frame(width: size, height: size)
                .background(DL.gold, in: shape)
                .offset(y: down ? lip : 0)
                .background(shape.fill(DL.goldLip).offset(y: lip))
                .padding(.bottom, lip)
                .scaleEffect(down ? 0.92 : 1)
                .animation(.spring(response: 0.28, dampingFraction: 0.45), value: down)
        }
    }
}

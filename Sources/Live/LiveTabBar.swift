import SwiftUI
import UIKit

// The tab bar: one floating capsule of glass holding Reels, Community, the Create key, Messages and Library,
// each as its symbol alone. Create is not a tab. It opens the camera over everything.

struct LiveTabBar: View {
    @ObservedObject private var nav = LiveNav.shared
    @Environment(\.colorScheme) private var scheme
    @Namespace private var highlight

    private static let slotHeight: CGFloat = 54
    private static let inset: CGFloat = 4
    /// How tall the bar stands above the home indicator: the room a tab's page leaves at its bottom.
    static let height: CGFloat = 10 + inset + slotHeight + inset + 2

    var body: some View {
        HStack(spacing: 0) {
            item(1, symbol: "play.rectangle.on.rectangle.fill", title: "Reels")
            item(0, symbol: "person.2.fill", title: "Community")
            LiveCreateKey().frame(maxWidth: .infinity)
            item(3, symbol: "bubble.left.and.bubble.right.fill", title: "Messages")
            item(4, symbol: "books.vertical.fill", title: "Library")
        }
        .frame(height: Self.slotHeight)
        .padding(Self.inset)
        .modifier(LiveTabBarGlass())
        // Reels is dark whatever the appearance, so the bar is too.
        .environment(\.colorScheme, nav.tab == 1 ? .dark : scheme)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private func item(_ index: Int, symbol: String, title: String) -> some View {
        let chosen = nav.tab == index
        return Image(systemName: symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(chosen ? DL.ink : DL.ink2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if chosen {
                    // Held in from the slot's edges, so the highlight never crowds the Create key beside it.
                    Capsule().fill(DL.ink.opacity(0.1)).padding(.horizontal, 6).padding(.vertical, 4)
                        .matchedGeometryEffect(id: "chosen", in: highlight)
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

/// The bar's backing: the system's glass where the phone has it, and a frosted capsule before iOS 26.
private struct LiveTabBarGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background {
                Capsule().fill(.regularMaterial)
                    .overlay(Capsule().strokeBorder(DL.line.opacity(0.7), lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
            }
        }
    }
}

/// The gold plus in the middle of the bar: a flat circle, larger than the tabs beside it. It dips when pressed.
struct LiveCreateKey: View {
    var body: some View {
        Button {
            if LiveStore.shared.s.haptics { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            LiveNav.shared.open(.create(nil))
        } label: {
            Image(systemName: "plus").font(.system(size: 22, weight: .bold))
        }
        .buttonStyle(CreateKeyStyle())
        .accessibilityLabel("Create")
    }

    private struct CreateKeyStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            let down = configuration.isPressed
            configuration.label
                .foregroundStyle(DL.onGold)
                .frame(width: 52, height: 52)
                .background(DL.gold, in: Circle())
                .scaleEffect(down ? 0.9 : 1)
                .animation(.spring(response: 0.28, dampingFraction: 0.5), value: down)
        }
    }
}

import SwiftUI

// "Update ready" in the window is upstream's: a card at the foot of the
// column, or a pill by the tabs, while a newer build waits. This fork has no
// updater (Updater.swift), so there is never one; what is left is the card's
// button, which the coding agent's card uses too.

/// The coding agent's Stop on its card (AgentBanner): a small capsule on the ground, under a hairline. `spot`
/// is drawn behind the label, for a control that has to know where it is.
struct CardButton<Spot: View>: View {
    let title: String
    let act: () -> Void
    let spot: Spot
    @State private var hovering = false

    init(title: String, act: @escaping () -> Void, @ViewBuilder spot: () -> Spot) {
        self.title = title
        self.act = act
        self.spot = spot()
    }

    var body: some View {
        Button(action: act) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? Palette.ink : Palette.ink.opacity(0.8))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Palette.ground, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
                .contentShape(Capsule())
                .background(spot)
                .fixedSize()
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
    }
}

extension CardButton where Spot == EmptyView {
    init(title: String, act: @escaping () -> Void) {
        self.init(title: title, act: act) { EmptyView() }
    }
}

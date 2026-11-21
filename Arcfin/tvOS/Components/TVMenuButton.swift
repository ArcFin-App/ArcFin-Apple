// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import UIKit

/// One entry in a `TVMenuButton`'s menu: an action, or a submenu when it has children.
struct TVMenuEntry {
    var title: String
    var systemImage: String? = nil
    var isDestructive = false
    var isDisabled = false
    /// A checkmark, for the chosen one of a set.
    var isSelected = false
    var children: [TVMenuEntry] = []
    var action: () -> Void = {}

    /// Everything that's drawn; the menu is rebuilt only when this changes.
    fileprivate var signature: String {
        "\(title)|\(systemImage ?? "")|\(isDestructive)|\(isDisabled)|\(isSelected)[\(children.map(\.signature).joined(separator: ","))]"
    }
}

/// A round control that opens a menu, drawn like `TVPlayerControlLabel`. It's UIKit because an
/// open SwiftUI `Menu` on tvOS 26 blinks whenever anything around it redraws, and the player
/// redraws as the position moves on (AetherEngine#29).
struct TVMenuButton: UIViewRepresentable {
    let systemImage: String
    let accessibilityLabel: String
    var size: CGFloat = 14
    var diameter: CGFloat = 32
    let entries: [TVMenuEntry]
    /// The menu opens or closes.
    var onOpenChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> TVMenuControl {
        let button = TVMenuControl(systemImage: systemImage, size: size * DT.Scale.font, diameter: diameter * DT.Scale.font)
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = accessibilityLabel
        return button
    }

    func updateUIView(_ button: TVMenuControl, context: Context) {
        let coordinator = context.coordinator
        button.onOpenChange = onOpenChange
        button.accessibilityLabel = accessibilityLabel
        // The actions run the newest closures, so the menu needn't be rebuilt to pick them up.
        coordinator.actions = [:]
        collect(entries, path: "", into: &coordinator.actions)
        let signature = entries.map(\.signature).joined(separator: ",")
        guard signature != coordinator.signature else { return }
        coordinator.signature = signature
        button.menu = UIMenu(children: elements(entries, path: "", coordinator: coordinator))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: TVMenuControl, context: Context) -> CGSize? {
        CGSize(width: diameter * DT.Scale.font, height: diameter * DT.Scale.font)
    }

    private func collect(_ entries: [TVMenuEntry], path: String, into actions: inout [String: () -> Void]) {
        for (index, entry) in entries.enumerated() {
            let id = "\(path)/\(index)"
            if entry.children.isEmpty { actions[id] = entry.action } else { collect(entry.children, path: id, into: &actions) }
        }
    }

    private func elements(_ entries: [TVMenuEntry], path: String, coordinator: Coordinator) -> [UIMenuElement] {
        entries.enumerated().map { index, entry in
            let id = "\(path)/\(index)"
            let image = entry.systemImage.flatMap { UIImage(systemName: $0) }
            if !entry.children.isEmpty {
                return UIMenu(title: entry.title, image: image, children: elements(entry.children, path: id, coordinator: coordinator))
            }
            var attributes: UIMenuElement.Attributes = []
            if entry.isDestructive { attributes.insert(.destructive) }
            if entry.isDisabled { attributes.insert(.disabled) }
            return UIAction(title: entry.title, image: image, attributes: attributes, state: entry.isSelected ? .on : .off) {
                [weak coordinator] _ in coordinator?.actions[id]?()
            }
        }
    }

    final class Coordinator {
        var signature: String?
        var actions: [String: () -> Void] = [:]
    }
}

/// The button itself: white on a soft circle, accent and a little larger while focused.
final class TVMenuControl: UIButton {
    var onOpenChange: (Bool) -> Void = { _ in }
    private let circle = UIView()
    private let symbol = UIImageView()

    init(systemImage: String, size: CGFloat, diameter: CGFloat) {
        super.init(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        circle.isUserInteractionEnabled = false
        circle.layer.cornerRadius = diameter / 2
        circle.frame = bounds
        circle.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(circle)
        symbol.image = UIImage(systemName: systemImage,
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .semibold))
        symbol.contentMode = .center
        symbol.frame = bounds
        symbol.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(symbol)
        applyFocus(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let focused = isFocused
        coordinator.addCoordinatedAnimations { [weak self] in self?.applyFocus(focused) }
    }

    private func applyFocus(_ focused: Bool) {
        circle.backgroundColor = focused ? UIColor(DT.Color.accent) : UIColor.white.withAlphaComponent(0.16)
        symbol.tintColor = focused ? UIColor(DT.Color.backgroundPrimary) : .white
        transform = focused ? CGAffineTransform(scaleX: 1.15, y: 1.15) : .identity
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         willDisplayMenuFor configuration: UIContextMenuConfiguration,
                                         animator: (any UIContextMenuInteractionAnimating)?) {
        super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
        onOpenChange(true)
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         willEndFor configuration: UIContextMenuConfiguration,
                                         animator: (any UIContextMenuInteractionAnimating)?) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        onOpenChange(false)
    }
}

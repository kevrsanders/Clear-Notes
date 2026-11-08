import SwiftUI
import UIKit

// Clear Notes' own menus: a solid sheet from the bottom, its options grouped into cards. Used
// everywhere instead of iOS menus, context menus and confirmation dialogs, which always have a
// frosted see-through background.
//
//     .menuSheet(isPresented: $showingMore) {
//         MenuSheet("Weekly check-in") {
//             MenuGroup {
//                 MenuRow("Rename", systemImage: "pencil") { renaming = true }
//             }
//             DeleteChoices(onMoveToRecentlyDeleted: …, onDeletePermanently: …)
//         }
//     }
//
// Choosing an option closes the sheet first and then runs it, so an option can open an alert,
// another sheet or the share sheet.

// MARK: - Presenting

extension View {
    /// Shows a menu sheet, sized to fit its options.
    func menuSheet<Sheet: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Sheet) -> some View {
        modifier(MenuSheetPresenter(isPresented: isPresented, sheet: content))
    }

    /// Shows a menu sheet about one item, e.g. the meeting that was held down.
    func menuSheet<Item: Identifiable, Sheet: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Sheet) -> some View {
        modifier(MenuSheetItemPresenter(item: item, sheet: content))
    }

    /// Holding this opens a menu, with a tap of feedback: Clear Notes' replacement for
    /// `.contextMenu`. VoiceOver offers it as the "More options" action.
    func onHoldForMenu(_ open: @escaping () -> Void) -> some View {
        modifier(HoldForMenu(open: open))
    }
}

/// What the options in a menu sheet can ask of it.
struct MenuSheetActions {
    /// Closes the sheet, then runs the option.
    var choose: (@escaping () -> Void) -> Void = { $0() }
    /// The height the options need, so the sheet fits them.
    var fit: (CGFloat) -> Void = { _ in }
}

private struct MenuSheetActionsKey: EnvironmentKey {
    static let defaultValue = MenuSheetActions()
}

extension EnvironmentValues {
    var menuSheet: MenuSheetActions {
        get { self[MenuSheetActionsKey.self] }
        set { self[MenuSheetActionsKey.self] = newValue }
    }
}

private struct MenuSheetPresenter<Sheet: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let sheet: () -> Sheet

    /// The option chosen, run once the sheet has gone.
    @State private var chosen: (() -> Void)?
    @State private var height: CGFloat = 320

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: runChosen) {
            sheet()
                .environment(\.menuSheet, MenuSheetActions(
                    choose: { action in
                        chosen = action
                        isPresented = false
                    },
                    fit: { needed in
                        if abs(needed - height) > 0.5 { height = needed }
                    }
                ))
                .presentationDetents([.height(height)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
                .presentationBackground(Theme.sheetBackground)
        }
    }

    private func runChosen() {
        guard let action = chosen else { return }
        chosen = nil
        action()
    }
}

private struct MenuSheetItemPresenter<Item: Identifiable, Sheet: View>: ViewModifier {
    @Binding var item: Item?
    let sheet: (Item) -> Sheet

    /// The item last shown, so the sheet keeps its options while it slides away.
    @State private var lastItem: Item?

    func body(content: Content) -> some View {
        content
            .onChange(of: item?.id) {
                if let item { lastItem = item }
            }
            .modifier(MenuSheetPresenter(
                isPresented: Binding(get: { item != nil }, set: { if !$0 { item = nil } }),
                sheet: {
                    if let shown = item ?? lastItem {
                        sheet(shown)
                    }
                }
            ))
    }
}

private struct HoldForMenu: ViewModifier {
    let open: () -> Void
    @State private var held = 0

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(minimumDuration: 0.4) {
                held += 1
                open()
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: held)
            .accessibilityAction(named: "More options", open)
    }
}

// MARK: - The sheet

/// The contents of a menu sheet: an optional title and message, then groups of options.
struct MenuSheet<Content: View>: View {
    var title: String?
    var message: String?
    @ViewBuilder var content: Content

    @Environment(\.menuSheet) private var menu

    init(_ title: String? = nil, message: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.message = message
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if title != nil || message != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        if let title {
                            Text(title)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                        }
                        if let message {
                            Text(message)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                }
                content
            }
            .padding(.horizontal, 14)
            .padding(.top, 28)
            .padding(.bottom, 14)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: MenuSheetHeightKey.self, value: proxy.size.height)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onPreferenceChange(MenuSheetHeightKey.self) { menu.fit($0) }
    }
}

private struct MenuSheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A card of options. Rows inside it are divided by hairlines.
struct MenuGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Theme.sheetGroup)
        // Also hides the first row's hairline, which sits just above it.
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// One option: an icon, a title and an optional line under it. Destructive options are red.
struct MenuRow: View {
    var title: String
    var subtitle: String?
    var systemImage: String?
    var role: ButtonRole?
    /// Shows a tick, for the current choice in a list.
    var isSelected = false
    var action: () -> Void

    @Environment(\.menuSheet) private var menu
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.displayScale) private var displayScale

    init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.role = role
        self.isSelected = isSelected
        self.action = action
    }

    private var isDestructive: Bool { role == .destructive }

    var body: some View {
        Button {
            menu.choose(action)
        } label: {
            HStack(spacing: 14) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(isDestructive ? Theme.danger : Theme.brand)
                        .frame(width: 24)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(isDestructive ? Theme.danger : Color.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.brand)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
        .opacity(isEnabled ? 1 : 0.4)
        .overlay(alignment: .top) {
            // Just above the row, so it divides it from the one before; the group clips the first.
            Rectangle()
                .fill(Theme.stroke)
                .frame(height: 1 / displayScale)
                .padding(.leading, systemImage == nil ? 16 : 54)
                .offset(y: -1 / displayScale)
                .accessibilityHidden(true)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.07) : Color.clear)
    }
}

/// A row of choices shown as chips, e.g. a meeting's type. Picking one closes the sheet.
struct MenuChips<Option: Hashable>: View {
    var title: String
    var systemImage: String
    var options: [Option]
    var selection: Option
    var label: (Option) -> String
    var onSelect: (Option) -> Void

    @Environment(\.menuSheet) private var menu

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.brand)
                    .frame(width: 24)
                Text(title)
            }
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let isSelected = option == selection
                    Button {
                        guard !isSelected else { return }
                        menu.choose { onSelect(option) }
                    } label: {
                        Text(label(option))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(isSelected ? Theme.brand : Theme.textSecondary)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(isSelected ? Theme.brand.opacity(0.16) : Color.primary.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.leading, 38)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

/// "Cancel", on its own card at the bottom of a confirmation.
struct MenuCancelButton: View {
    @Environment(\.menuSheet) private var menu

    var body: some View {
        Button {
            menu.choose {}
        } label: {
            Text("Cancel")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
        .background(Theme.sheetGroup)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Sharing

/// Opens the iOS share sheet over whatever is showing. Used by menu options, which run once their
/// sheet has closed, so a `ShareLink` can't be used there.
enum SystemShare {
    @MainActor
    static func present(_ items: [Any]) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              var top = scene.keyWindow?.rootViewController
        else { return }
        while let presented = top.presentedViewController { top = presented }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 80, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }
}

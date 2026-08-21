import SwiftUI
import UIKit

enum RemoteTheme {
    static let accent = dynamicColor(
        light: UIColor(red: 0.18, green: 0.36, blue: 0.75, alpha: 1),
        dark: UIColor(red: 0.404, green: 0.620, blue: 0.996, alpha: 1)
    )
    static let thinking = dynamicColor(
        light: UIColor(red: 0.40, green: 0.30, blue: 0.73, alpha: 1),
        dark: UIColor(red: 0.55, green: 0.49, blue: 0.96, alpha: 1)
    )
    static let tool = dynamicColor(
        light: UIColor(red: 0.62, green: 0.28, blue: 0.04, alpha: 1),
        dark: UIColor(red: 0.92, green: 0.55, blue: 0.25, alpha: 1)
    )
    static let success = dynamicColor(
        light: UIColor(red: 0.05, green: 0.47, blue: 0.20, alpha: 1),
        dark: UIColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1)
    )
    static let warning = dynamicColor(
        light: UIColor(red: 0.58, green: 0.31, blue: 0.00, alpha: 1),
        dark: UIColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1)
    )
    static let danger = dynamicColor(
        light: UIColor(red: 0.73, green: 0.16, blue: 0.16, alpha: 1),
        dark: UIColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 1)
    )

    static let canvas = dynamicColor(
        light: UIColor(red: 0.976, green: 0.980, blue: 0.984, alpha: 1),
        dark: UIColor(red: 0.082, green: 0.082, blue: 0.090, alpha: 1)
    )
    static let surface = dynamicColor(
        light: .white,
        dark: UIColor(red: 0.137, green: 0.137, blue: 0.141, alpha: 1)
    )
    static let raisedSurface = dynamicColor(
        light: UIColor(red: 0.965, green: 0.969, blue: 0.976, alpha: 1),
        dark: UIColor(red: 0.173, green: 0.173, blue: 0.180, alpha: 1)
    )
    static let mutedSurface = dynamicColor(
        light: UIColor(red: 0.945, green: 0.953, blue: 0.965, alpha: 1),
        dark: UIColor(red: 0.208, green: 0.212, blue: 0.220, alpha: 1)
    )
    static let userBubble = dynamicColor(
        light: UIColor(red: 0.929, green: 0.953, blue: 0.996, alpha: 1),
        dark: UIColor(red: 0.173, green: 0.173, blue: 0.180, alpha: 1)
    )
    static let codeSurface = dynamicColor(
        light: UIColor(red: 0.945, green: 0.953, blue: 0.965, alpha: 1),
        dark: UIColor(red: 0.059, green: 0.059, blue: 0.067, alpha: 1)
    )
    static let hairline = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.09)
            : UIColor.black.withAlphaComponent(0.075)
    })
    static let strongHairline = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.14)
            : UIColor.black.withAlphaComponent(0.12)
    })
    static let shadow = Color.black.opacity(0.12)

    static let pagePadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 22
    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 13

    private static func dynamicColor(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

enum RemoteButtonKind {
    case primary
    case secondary
    case ghost
    case danger
}

struct RemoteActionButtonStyle: ButtonStyle {
    let kind: RemoteButtonKind
    var fillsWidth = true
    var compact = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.semibold) : .body.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(minHeight: compact ? 44 : 50)
            .padding(.horizontal, compact ? 13 : 16)
            .background(backgroundColor(configuration: configuration))
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 11 : RemoteTheme.controlRadius)
                    .stroke(borderColor, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: compact ? 11 : RemoteTheme.controlRadius))
            .contentShape(RoundedRectangle(cornerRadius: compact ? 11 : RemoteTheme.controlRadius))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.42)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary: .white
        case .secondary, .ghost: .primary
        case .danger: RemoteTheme.danger
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary: RemoteTheme.accent.opacity(0.75)
        case .secondary: RemoteTheme.strongHairline
        case .ghost: .clear
        case .danger: RemoteTheme.danger.opacity(0.22)
        }
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        let pressed = configuration.isPressed
        return switch kind {
        case .primary:
            RemoteTheme.accent.opacity(pressed ? 0.78 : 1)
        case .secondary:
            RemoteTheme.raisedSurface.opacity(pressed ? 0.72 : 1)
        case .ghost:
            pressed ? RemoteTheme.mutedSurface : .clear
        case .danger:
            RemoteTheme.danger.opacity(pressed ? 0.18 : 0.10)
        }
    }
}

struct RemoteIconButtonStyle: ButtonStyle {
    var tint: Color = .primary
    var emphasized = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(
                emphasized ? tint.opacity(configuration.isPressed ? 0.20 : 0.12)
                    : RemoteTheme.raisedSurface.opacity(configuration.isPressed ? 0.65 : 1),
                in: RoundedRectangle(cornerRadius: 13)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(RemoteTheme.hairline, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct RemoteToolbarButtonStyle: ButtonStyle {
    var tint: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(
                configuration.isPressed ? RemoteTheme.mutedSurface : Color.clear,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .contentShape(Rectangle())
    }
}

struct RemotePageHeader<Trailing: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let subtitle: String?
    let showsBackButton: Bool
    let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        showsBackButton: Bool = true,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsBackButton = showsBackButton
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            if showsBackButton {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                }
                .buttonStyle(RemoteToolbarButtonStyle())
                .accessibilityLabel("返回")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                }
            }
            .layoutPriority(1)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)
            trailing
        }
        .frame(minHeight: 56)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(RemoteTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(RemoteTheme.hairline)
                .frame(height: 0.5)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

extension RemotePageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, showsBackButton: Bool = true) {
        self.init(title: title, subtitle: subtitle, showsBackButton: showsBackButton) {
            EmptyView()
        }
    }
}

struct RemoteSheetHeader<Trailing: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let subtitle: String?
    let closeLabel: String
    let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        closeLabel: String = "关闭",
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.closeLabel = closeLabel
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                }
            }
            Spacer(minLength: 8)
            trailing
            Button { dismiss() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(RemoteToolbarButtonStyle())
            .accessibilityLabel(closeLabel)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(RemoteTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(RemoteTheme.hairline).frame(height: 0.5)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

extension RemoteSheetHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, closeLabel: String = "关闭") {
        self.init(title: title, subtitle: subtitle, closeLabel: closeLabel) { EmptyView() }
    }
}

struct RemoteSectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }
}

struct RemoteStatusPill: View {
    let text: String
    var color: Color = .secondary
    var icon: String?

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .frame(minHeight: 24)
        .background(color.opacity(0.11), in: Capsule())
        .overlay { Capsule().stroke(color.opacity(0.14), lineWidth: 1) }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct RemoteInlineNotice: View {
    enum Tone {
        case info, warning, danger, success

        var color: Color {
            switch self {
            case .info: RemoteTheme.accent
            case .warning: RemoteTheme.warning
            case .danger: RemoteTheme.danger
            case .success: RemoteTheme.success
            }
        }
    }

    let title: String
    let message: String?
    let icon: String
    var tone: Tone = .info
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tone.color)
                .frame(width: 24, height: 24)
                .background(tone.color.opacity(0.11), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tone.color)
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(12)
        .background(tone.color.opacity(0.075), in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(tone.color.opacity(0.16), lineWidth: 1)
        }
    }
}

struct RemoteEmptyState<ActionLabel: View>: View {
    let icon: String
    let title: String
    let message: String
    let actionLabel: ActionLabel
    let action: (() -> Void)?

    init(
        icon: String,
        title: String,
        message: String,
        action: (() -> Void)? = nil,
        @ViewBuilder actionLabel: () -> ActionLabel
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.action = action
        self.actionLabel = actionLabel()
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 27, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 58, height: 58)
                .background(RemoteTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 17))
                .overlay {
                    RoundedRectangle(cornerRadius: 17)
                        .stroke(RemoteTheme.hairline, lineWidth: 1)
                }
                .padding(.bottom, 18)

            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.top, 7)

            if let action {
                Button(action: action) { actionLabel }
                    .buttonStyle(RemoteActionButtonStyle(kind: .primary))
                    .padding(.top, 22)
            }
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}

struct RemoteLoadingState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 17)
                    .fill(RemoteTheme.raisedSurface)
                RoundedRectangle(cornerRadius: 17)
                    .stroke(RemoteTheme.hairline, lineWidth: 1)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(RemoteTheme.accent)
            }
            .frame(width: 58, height: 58)
            .overlay(alignment: .bottomTrailing) {
                ProgressView()
                    .controlSize(.small)
                    .padding(4)
                    .background(RemoteTheme.canvas, in: Circle())
                    .offset(x: 5, y: 5)
            }
            .padding(.bottom, 18)

            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.top, 7)
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

struct RemoteDestructiveConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let icon: String
    let title: String
    let message: String
    let confirmTitle: String
    let confirm: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(RemoteToolbarButtonStyle())
                    .accessibilityLabel("取消")
                }

                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(RemoteTheme.danger)
                    .frame(width: 54, height: 54)
                    .background(RemoteTheme.danger.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.top, 2)

                Text(title)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 14)
                    .padding(.top, 7)

                actionButtons
                    .padding(.top, 22)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .background(RemoteTheme.canvas.ignoresSafeArea())
    }

    @ViewBuilder
    private var actionButtons: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                Button(confirmTitle, action: performConfirm)
                    .buttonStyle(RemoteActionButtonStyle(kind: .danger))
                Button("取消") { dismiss() }
                    .buttonStyle(RemoteActionButtonStyle(kind: .secondary))
            }
        } else {
            HStack(spacing: 10) {
                Button("取消") { dismiss() }
                    .buttonStyle(RemoteActionButtonStyle(kind: .secondary))
                Button(confirmTitle, action: performConfirm)
                    .buttonStyle(RemoteActionButtonStyle(kind: .danger))
            }
        }
    }

    private func performConfirm() {
        confirm()
        dismiss()
    }
}

extension RemoteEmptyState where ActionLabel == EmptyView {
    init(icon: String, title: String, message: String) {
        self.init(icon: icon, title: title, message: message, action: nil) { EmptyView() }
    }
}

private struct RemoteSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let elevated: Bool

    func body(content: Content) -> some View {
        content
            .background(RemoteTheme.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(RemoteTheme.hairline, lineWidth: 1)
            }
            .shadow(
                color: elevated ? RemoteTheme.shadow.opacity(0.55) : .clear,
                radius: elevated ? 18 : 0,
                y: elevated ? 8 : 0
            )
    }
}

private struct RemoteFieldSurfaceModifier: ViewModifier {
    let focused: Bool
    let invalid: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 13)
            .frame(minHeight: 50)
            .background(RemoteTheme.surface, in: RoundedRectangle(cornerRadius: RemoteTheme.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: RemoteTheme.controlRadius)
                    .stroke(
                        invalid ? RemoteTheme.danger.opacity(0.7)
                            : (focused ? RemoteTheme.accent.opacity(0.78) : RemoteTheme.hairline),
                        lineWidth: focused || invalid ? 1.25 : 1
                    )
            }
    }
}

extension View {
    func remoteSurface(cornerRadius: CGFloat = RemoteTheme.cardRadius, elevated: Bool = false) -> some View {
        modifier(RemoteSurfaceModifier(cornerRadius: cornerRadius, elevated: elevated))
    }

    func remoteFieldSurface(focused: Bool = false, invalid: Bool = false) -> some View {
        modifier(RemoteFieldSurfaceModifier(focused: focused, invalid: invalid))
    }

    func remoteNavigationChromeHidden() -> some View {
        toolbar(.hidden, for: .navigationBar)
            .background(RemoteInteractivePopGestureSupport().frame(width: 0, height: 0))
    }
}

private struct RemoteInteractivePopGestureSupport: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        GestureController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    private final class GestureController: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}

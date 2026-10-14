import SwiftUI

/// Main action: blue, at least 52 pt tall. The gradient is allowed only on the active primary button.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration)
    }

    private struct PrimaryButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundColor(isEnabled ? .ecOnBlue : .ecTextSecondary)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: Metrics.primaryButtonHeight)
                .background(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .fill(isEnabled
                              ? AnyShapeStyle(LinearGradient(colors: [Color.ecBlue, Color(hex: 0x5468FF)], startPoint: .leading, endPoint: .trailing))
                              : AnyShapeStyle(Color.ecInput))
                )
                .opacity(configuration.isPressed ? 0.82 : 1)
                .contentShape(Rectangle())
        }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = .ecTextPrimary

    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonBody(configuration: configuration, tint: tint)
    }

    private struct SecondaryButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.body.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundColor(isEnabled ? tint : .ecTextSecondary.opacity(0.6))
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .fill(Color.ecInput)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .stroke(Color.ecDivider, lineWidth: 1)
                )
                .opacity(configuration.isPressed ? 0.75 : 1)
                .contentShape(Rectangle())
        }
    }
}

/// Confirms an irreversible removal: coral fill, dark text, same size as the primary button.
struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DestructiveBody(configuration: configuration)
    }

    private struct DestructiveBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundColor(isEnabled ? .ecOnAccent : .ecTextSecondary)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: Metrics.primaryButtonHeight)
                .background(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .fill(isEnabled ? Color.ecCoral : Color.ecInput)
                )
                .opacity(configuration.isPressed ? 0.82 : 1)
                .contentShape(Rectangle())
        }
    }
}

/// Compact inline action (e.g. "Include Everyone"), still at least 44 pt tall.
struct InlineButtonStyle: ButtonStyle {
    var tint: Color = Color(hex: 0x8FB0FF)

    func makeBody(configuration: Configuration) -> some View {
        InlineBody(configuration: configuration, tint: tint)
    }

    private struct InlineBody: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.callout.weight(.semibold))
                .foregroundColor(isEnabled ? tint : .ecTextSecondary.opacity(0.6))
                .padding(.horizontal, 12)
                .frame(minHeight: Metrics.minTapTarget)
                .background(Capsule().fill(Color.ecInput.opacity(configuration.isPressed ? 0.6 : 1)))
                .contentShape(Rectangle())
        }
    }
}

/// A square-ish icon button with a 44×44 pt tap area.
struct IconButton: View {
    let systemName: String
    let label: String
    var tint: Color = .ecTextPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundColor(tint)
                .frame(width: Metrics.minTapTarget, height: Metrics.minTapTarget)
                .background(Circle().fill(Color.ecInput))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Square checkbox used for "I have already made this payment outside Even Circle."
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: Spacing.s) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundColor(configuration.isOn ? .ecBlue : .ecTextSecondary)
                    .frame(width: 28, height: 28)
                configuration.label
                    .foregroundColor(.ecTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: Metrics.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "Checked" : "Not checked")
    }
}

import SwiftUI

/// Screens 01–03. Illustrations never create events or debts; all text and controls are code.
struct OnboardingView: View {
    enum Mode {
        /// First launch: finishing stores onboardingCompleted and opens Events.
        case firstRun
        /// Opened from Settings: closing returns to Settings.
        case replay
    }

    struct Page: Equatable {
        let illustration: Illustration
        let title: String
        let body: String
    }

    static let pages = [
        Page(illustration: .onboardingExpenses,
             title: "Good plans. Clear expenses.",
             body: "Keep group purchases in one place and see who paid for what."),
        Page(illustration: .onboardingSplit,
             title: "Split it the way it happened",
             body: "Share equally, use different shares or assign each receipt item."),
        Page(illustration: .onboardingSettle,
             title: "Know what is left to settle",
             body: "See suggested payments and record transfers made outside the app."),
    ]

    let mode: Mode
    let onFinish: () -> Void

    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var page: Page { Self.pages[index] }
    private var isLast: Bool { index == Self.pages.count - 1 }

    private func go(to newIndex: Int) {
        guard Self.pages.indices.contains(newIndex) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { index = newIndex }
    }

    var body: some View {
        ZStack {
            Color.ecBackground.ignoresSafeArea()
            GeometryReader { proxy in
                Image(decorative: page.illustration.rawValue)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .id(index)
                    .transition(.opacity)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)

            // Keeps text readable over the calm lower part of the artwork.
            LinearGradient(
                colors: [Color.ecBackground.opacity(0), Color.ecBackground.opacity(0.85), Color.ecBackground],
                startPoint: UnitPoint(x: 0.5, y: 0.35),
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(mode == .replay ? "Close" : "Skip", action: onFinish)
                        .buttonStyle(InlineButtonStyle(tint: .ecTextPrimary))
                        .accessibilityIdentifier("onboardingSkip")
                }
                Spacer(minLength: Spacing.m)
                textBlock
                controls
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.bottom, Spacing.m)
        }
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -60 { go(to: index + 1) }
                if value.translation.width > 60 { go(to: index - 1) }
            }
        )
    }

    @ViewBuilder
    private var textBlock: some View {
        let content = VStack(alignment: .leading, spacing: Spacing.s) {
            Text(page.title)
                .ecScreenTitleFont()
                .foregroundColor(.ecTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(page.body)
                .font(.body)
                .foregroundColor(.ecTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if isLast {
                Label("Even Circle does not move money.", systemImage: "hand.raised.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundColor(.ecMint)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id("text-\(index)")

        if dynamicTypeSize.isAccessibilitySize {
            ScrollView { content }.frame(maxHeight: 360)
        } else {
            content
        }
    }

    private var controls: some View {
        VStack(spacing: Spacing.m) {
            HStack(spacing: 8) {
                ForEach(Self.pages.indices, id: \.self) { dot in
                    Capsule()
                        .fill(dot == index ? Color.ecBlue : Color.ecDivider)
                        .frame(width: dot == index ? 22 : 8, height: 8)
                }
                Spacer()
                Text("\(index + 1)/\(Self.pages.count)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundColor(.ecTextSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(index + 1) of \(Self.pages.count)")
            .padding(.top, Spacing.l)

            HStack(spacing: Spacing.s) {
                if index > 0 {
                    Button("Back") { go(to: index - 1) }
                        .buttonStyle(SecondaryButtonStyle())
                        .frame(maxWidth: 140)
                        .accessibilityIdentifier("onboardingBack")
                }
                if isLast {
                    Button(mode == .replay ? "Done" : "Get Started", action: onFinish)
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("onboardingGetStarted")
                } else {
                    Button("Next") { go(to: index + 1) }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("onboardingNext")
                }
            }
        }
    }
}

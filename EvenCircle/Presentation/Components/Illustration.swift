import SwiftUI

/// Every planned raster from the asset catalogue (section 6 of the spec), with its on-screen size.
///
/// The PNGs in Assets.xcassets are placeholders with the final names and pixel sizes; replace the
/// files in place (see ASSETS_TODO.md) and no code changes are needed. Illustrations are always
/// decorative: hidden from VoiceOver and never the only way to understand a balance or an action.
enum Illustration: String, CaseIterable {
    /// EC01 – onboarding 1 background, 1290×2796 px, opaque.
    case onboardingExpenses = "ec_onboarding_expenses"
    /// EC02 – onboarding 2 background, 1290×2796 px, opaque.
    case onboardingSplit = "ec_onboarding_split"
    /// EC03 – onboarding 3 background, 1290×2796 px, opaque.
    case onboardingSettle = "ec_onboarding_settle"
    /// EC04 – Events hero, 1024×1024 px transparent, shown at 112×96 pt.
    case eventsHero = "ec_events_hero"
    /// EC05 – empty database, 768×768 px transparent, shown at 160×136 pt.
    case emptyEvent = "ec_empty_event"
    /// EC06 – People with zero participants, 768×768 px transparent, shown at 136×112 pt.
    case peopleGroup = "ec_people_group"
    /// EC07 – Expenses empty, 768×768 px transparent, shown at 144×128 pt.
    case emptyReceipt = "ec_empty_receipt"
    /// EC08 – Balances "All settled", 768×768 px transparent, shown at 88×88 pt.
    case balancedShapes = "ec_balanced_shapes"
    /// EC09 – Record Payment note (64×64 pt) and empty Payment History (112×112 pt), 768×768 px transparent.
    case paymentNote = "ec_payment_note"
    /// EC10 – Share Summary header, 768×768 px transparent, shown at 64×64 pt.
    case summaryFolder = "ec_summary_folder"

    var id: String {
        switch self {
        case .onboardingExpenses: return "EC01"
        case .onboardingSplit: return "EC02"
        case .onboardingSettle: return "EC03"
        case .eventsHero: return "EC04"
        case .emptyEvent: return "EC05"
        case .peopleGroup: return "EC06"
        case .emptyReceipt: return "EC07"
        case .balancedShapes: return "EC08"
        case .paymentNote: return "EC09"
        case .summaryFolder: return "EC10"
        }
    }

    /// Default point size for the spot illustrations.
    var size: CGSize {
        switch self {
        case .onboardingExpenses, .onboardingSplit, .onboardingSettle: return CGSize(width: 430, height: 932)
        case .eventsHero: return CGSize(width: 112, height: 96)
        case .emptyEvent: return CGSize(width: 160, height: 136)
        case .peopleGroup: return CGSize(width: 136, height: 112)
        case .emptyReceipt: return CGSize(width: 144, height: 128)
        case .balancedShapes: return CGSize(width: 88, height: 88)
        case .paymentNote: return CGSize(width: 64, height: 64)
        case .summaryFolder: return CGSize(width: 64, height: 64)
        }
    }
}

struct IllustrationView: View {
    let illustration: Illustration
    let size: CGSize

    init(_ illustration: Illustration, size: CGSize? = nil) {
        self.illustration = illustration
        self.size = size ?? illustration.size
    }

    var body: some View {
        Image(decorative: illustration.rawValue)
            .resizable()
            .scaledToFit()
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)
    }
}

// Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
// Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

import SwiftUI

enum GenkanTheme {
    // MARK: - OLED Dark Backgrounds
    static let oledBackground = Color(red: 0.03, green: 0.04, blue: 0.06)
    static let cardBackground = Color(red: 0.07, green: 0.09, blue: 0.13)
    static let cardBorder = Color.white.opacity(0.12)
    
    // MARK: - Status Colors
    static let activeGreen = Color(red: 0.06, green: 0.80, blue: 0.48)
    static let alertAmber = Color(red: 0.98, green: 0.65, blue: 0.14)
    static let liveBlue = Color(red: 0.23, green: 0.51, blue: 0.96)
    static let errorRed = Color(red: 0.94, green: 0.27, blue: 0.27)
    static let aiIndigo = Color(red: 0.49, green: 0.38, blue: 0.99)
    
    // MARK: - Gradients
    static func backgroundGradient(for phaseTint: Color) -> LinearGradient {
        LinearGradient(
            colors: [
                phaseTint.opacity(0.18),
                oledBackground,
                Color.black
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    static let heroGlowGradient = RadialGradient(
        colors: [
            aiIndigo.opacity(0.35),
            liveBlue.opacity(0.15),
            Color.clear
        ],
        center: .center,
        startRadius: 20,
        endRadius: 160
    )
}

// MARK: - Signage Glass Card Style Modifier
struct SignageGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 24
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(GenkanTheme.cardBackground.opacity(0.85))
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(GenkanTheme.cardBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 8)
    }
}

extension View {
    func signageGlassCard(cornerRadius: CGFloat = 24) -> some View {
        self.modifier(SignageGlassCardModifier(cornerRadius: cornerRadius))
    }
}

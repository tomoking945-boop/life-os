import SwiftUI

/// 画面下部に浮かぶ「＋ なんでも追加」ボタン
struct QuickAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("なんでも追加", systemImage: "plus")
                .font(LifeTypography.button)
                .foregroundStyle(LifeColors.onPrimary)
                .padding(.horizontal, LifeSpacing.lg)
                .frame(minHeight: LifeSpacing.buttonHeight)
                .background(Capsule().fill(LifeColors.primary))
                .contentShape(Capsule())
        }
        .buttonStyle(LifePressButtonStyle())
        .lifeShadow(LifeShadow.floating)
        .accessibilityLabel("なんでも追加")
        .accessibilityHint("予定・ToDo・買い物・支出をまとめて入力できます")
    }
}

/// どの画面からでも「なんでも追加」を開けるようにする
private struct QuickAddAccessoryModifier: ViewModifier {
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            QuickAddButton {
                appState.isQuickAddPresented = true
            }
            .padding(.bottom, LifeSpacing.sm)
        }
    }
}

extension View {
    /// 画面下部に「＋ なんでも追加」を常設する
    func quickAddAccessory() -> some View {
        modifier(QuickAddAccessoryModifier())
    }
}

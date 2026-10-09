import SwiftUI

/// はじめての設定（2026-10-09）。新しく使い始める人に、最初に一度だけ出す。
/// 1画面につき判断は1つ。主ボタンは画面下部（キーボードが出ていても押せる）。前のステップに戻れる。
/// 色・文字・余白は Calm Future の DesignSystem をそのまま使う（テーマとライト／ダークに合わせる）。
struct OnboardingView: View {
    @State private var viewModel: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case groupName
    }

    private let starterColumns = [GridItem(.adaptive(minimum: LifeSpacing.themePreviewWidth), spacing: LifeSpacing.xs)]

    init(appState: AppState, store: LifeStore) {
        _viewModel = State(initialValue: OnboardingViewModel(appState: appState, store: store))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.xl) {
                topBar
                stepContent
                    .id(viewModel.step)
                    .transition(.opacity)
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .lifeScreenBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            primaryButton
        }
    }

    // MARK: - 上部：戻る・ステップの点

    private var topBar: some View {
        HStack(alignment: .center, spacing: LifeSpacing.sm) {
            if viewModel.canGoBack {
                Button {
                    move { viewModel.back() }
                } label: {
                    Label("戻る", systemImage: "chevron.left")
                        .font(LifeTypography.callout)
                        .foregroundStyle(LifeColors.primary)
                        .frame(minHeight: LifeSpacing.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("前のステップに戻ります")
            }
            Spacer(minLength: LifeSpacing.xs)
            stepDots
        }
        .frame(minHeight: LifeSpacing.minTapTarget)
    }

    private var stepDots: some View {
        HStack(spacing: LifeSpacing.rhythmGap) {
            ForEach(0..<OnboardingViewModel.stepCount, id: \.self) { index in
                Capsule()
                    .fill(index <= viewModel.step.rawValue ? LifeColors.primary : LifeColors.divider)
                    .frame(width: index == viewModel.step.rawValue ? LifeSpacing.lg : LifeSpacing.rhythmDot,
                           height: LifeSpacing.rhythmDot)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.stepText)
    }

    // MARK: - 各ステップ

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .welcome:
            welcomeStep
        case .usage:
            usageStep
        case .name:
            nameStep
        case .habits:
            habitsStep
        }
    }

    /// 1. ようこそ（細かい機能説明や Premium の案内は出さない）
    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.lg) {
            LifeLeafMark()
            Text("生活OSへようこそ")
                .font(LifeTypography.heroTitle)
                .foregroundStyle(LifeColors.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("予定や家事、やることをひとつにまとめて、「今日やること」を見やすくします。")
                .font(LifeTypography.editorialCopy)
                .foregroundStyle(LifeColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, LifeSpacing.xl)
    }

    /// 2. 使い方の選択
    private var usageStep: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.lg) {
            question("どのように使いますか？")
            VStack(spacing: LifeSpacing.sm) {
                ForEach(UsageStyle.allCases) { style in
                    usageOption(style)
                }
            }
        }
    }

    private func usageOption(_ style: UsageStyle) -> some View {
        let isSelected = viewModel.usageStyle == style
        return Button {
            withLifeAnimation(LifeMotion.quick, reduceMotion: reduceMotion) { viewModel.selectUsage(style) }
        } label: {
            HStack(alignment: .center, spacing: LifeSpacing.md) {
                Image(systemName: style == .solo ? "person" : "person.2")
                    .font(.title3)
                    .foregroundStyle(LifeColors.primary)
                    .frame(width: LifeSpacing.xl)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                    Text(style.label)
                        .font(LifeTypography.editorialHeadline)
                        .foregroundStyle(LifeColors.text)
                    Text(OnboardingViewModel.usageDescription(style))
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: LifeSpacing.xs)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? LifeColors.primary : LifeColors.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(LifeSpacing.md)
            .frame(maxWidth: .infinity, minHeight: LifeSpacing.buttonHeight, alignment: .leading)
            .lifeSurface(isSelected ? .selected : .normal, cornerRadius: LifeRadius.medium)
            .contentShape(RoundedRectangle(cornerRadius: LifeRadius.medium, style: .continuous))
        }
        .buttonStyle(LifePressButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(style.label)、\(OnboardingViewModel.usageDescription(style))")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    /// 3. 名前（家族・パートナーのときだけ生活グループ名も）
    private var nameStep: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.lg) {
            question("あなたの名前を教えてください")
            textField("あなたの名前", text: $viewModel.name, field: .name, prompt: "名前")
            if viewModel.asksGroupName {
                textField("生活グループ名", text: $viewModel.groupName, field: .groupName, prompt: "例：池上家")
                Text("家族やパートナーとの共有の情報を、この名前でまとめます。")
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("入力した内容は、この iPhone の中にだけ保存されます。")
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            if !viewModel.hasValidName { focusedField = .name }
        }
    }

    private func textField(_ label: String, text: Binding<String>, field: Field, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            LifeSectionTitle(label)
            TextField(prompt, text: text)
                .font(LifeTypography.body)
                .foregroundStyle(LifeColors.text)
                .focused($focusedField, equals: field)
                .submitLabel(field == .name && viewModel.asksGroupName ? .next : .done)
                .onSubmit {
                    if field == .name && viewModel.asksGroupName {
                        focusedField = .groupName
                    } else {
                        focusedField = nil
                        if viewModel.canGoNext { move { viewModel.next() } }
                    }
                }
                .padding(LifeSpacing.md)
                .frame(minHeight: LifeSpacing.buttonHeight)
                .lifeSurface(.normal, cornerRadius: LifeRadius.field)
                .accessibilityLabel(label)
        }
    }

    /// 4. 最初の習慣（選ばなくても完了できる）
    private var habitsStep: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.lg) {
            question("今日から始めることはありますか？")
            Text("いくつでも選べます。選ばなくても始められます。")
                .font(LifeTypography.callout)
                .foregroundStyle(LifeColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: starterColumns, spacing: LifeSpacing.xs) {
                ForEach(viewModel.starters) { starter in
                    LifeChoiceTile(symbol: starter.symbol, title: starter.title, isSelected: viewModel.isSelected(starter)) {
                        withLifeAnimation(LifeMotion.quick, reduceMotion: reduceMotion) { viewModel.toggle(starter) }
                    }
                    .accessibilityLabel(starter.title)
                    .accessibilityHint("今日から始める習慣に選びます")
                }
            }
            Text("習慣はあとから、今日画面の「習慣」で追加・編集できます。")
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func question(_ text: String) -> some View {
        Text(text)
            .font(LifeTypography.editorialTitle)
            .foregroundStyle(LifeColors.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - 下部の主ボタン

    private var primaryButton: some View {
        LifeButton(viewModel.primaryTitle, systemImage: viewModel.step == .habits ? "checkmark" : nil) {
            focusedField = nil
            move { viewModel.primaryAction() }
        }
        .disabled(!viewModel.canGoNext)
        .padding(.horizontal, LifeSpacing.screenHorizontal)
        .padding(.top, LifeSpacing.sm)
        .padding(.bottom, LifeSpacing.sm)
        .background(LifeColors.background.opacity(0.92))
    }

    /// ステップの切り替え（視差効果を減らす がオンなら動かさない）
    private func move(_ changes: () -> Void) {
        withLifeAnimation(reduceMotion: reduceMotion, changes)
    }
}

/// ようこそ画面の小さな印（抽象的な葉。色はテーマに合わせる）
private struct LifeLeafMark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(LifeColors.primarySubtle)
            Image(systemName: "leaf")
                .font(.title)
                .foregroundStyle(LifeColors.primary)
        }
        .frame(width: LifeSpacing.xxl + LifeSpacing.md, height: LifeSpacing.xxl + LifeSpacing.md)
        .accessibilityHidden(true)
    }
}

#Preview {
    let appState = AppState()
    appState.hasCompletedOnboarding = false
    return OnboardingView(appState: appState, store: LifeStore.empty())
        .environment(appState)
}

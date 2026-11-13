import Charts
import SwiftUI

// 月次レポート・支出推移の画面（2026-11-13 Build 26。docs/BUILD_26_MONTHLY_SPENDING_REPORT.md）
//
// - 「お金」の画面の、予算のカードの下・定期支出の上に、控えめな「月次レポート」のカード
// - 月次レポートの画面：月の切り替え・すべて／自分／共有・合計・予算と残り・前月との差・最近6か月の推移・カテゴリー別・支出一覧へ
// - 推移のグラフは Apple の Swift Charts（iOS 16 から。このアプリは iOS 17 から）。外部のライブラリは使わない。アニメーションは付けない
// - 色だけに頼らない：月・金額・割合は文字でも出し、VoiceOver で読める。円グラフは使わない
// - 端末に読み込んである支出だけで数える。集計の結果・見た月は保存しない・送らない・ログに出さない。評価・助言はしない

/// 「お金」の画面の月次レポートのカード（対象の月・合計・予算の残り・いちばん多いカテゴリー・「詳しく見る」）
struct MonthlyReportCard: View {
    let viewModel: MoneyViewModel

    var body: some View {
        let report = viewModel.monthlyReport
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            LifeSectionTitle("月次レポート", trailing: report.month.title)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                Text(viewModel.reportScopeTitle.isEmpty ? "支出の合計" : "支出の合計（\(viewModel.reportScopeTitle)）")
                    .font(LifeTypography.caption)
                    .foregroundStyle(LifeColors.secondaryText)
                Text(report.totalText)
                    .font(LifeTypography.headline)
                    .foregroundStyle(LifeColors.text)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(viewModel.reportTotalSpokenLabel(report))

            ForEach(viewModel.budgetSummaries) { summary in
                if let line = viewModel.reportBudgetLine(summary) {
                    Text(line)
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let top = report.topCategory {
                Text("いちばん多いカテゴリー：\(top.category.label) \(LifeFormatters.yen(top.amount))（\(top.percentText)）")
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("いちばん多いカテゴリー、\(viewModel.categoryShareSpokenLabel(top))")
            }
            LifeButton("詳しく見る", systemImage: "chart.bar", kind: .secondary) {
                viewModel.openMonthlyReport()
            }
            .accessibilityHint("前月との差・最近6か月の推移・カテゴリー別の金額と割合を見ます")
            .accessibilityIdentifier("money.monthlyReport.open")
        }
        .padding(LifeSpacing.md)
        .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
    }
}

/// 月次レポートの画面
struct MonthlyReportSheet: View {
    @Bindable var viewModel: MoneyViewModel

    var body: some View {
        let report = viewModel.monthlyReport
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                    monthSwitcher
                    if viewModel.showsScopeFilter {
                        LifeSegmentControl(ScopeFilter.allCases, selection: $viewModel.scope) { $0.title }
                            .accessibilityIdentifier("money.monthlyReport.scope")
                    }
                    totalSection(report)
                    budgetSection
                    comparisonSection(report.comparison)
                    trendSection(report)
                    categorySection(report)
                    LifeButton("\(report.month.title)の支出一覧を見る", systemImage: "list.bullet", kind: .secondary) {
                        viewModel.openExpenseList()
                    }
                    .accessibilityHint("お金の画面の支出一覧を、この月で絞り込んで見せます")
                    .accessibilityIdentifier("money.monthlyReport.openList")
                    Text("保存してある支出だけを数えています（定期支出の未確認の候補・商品明細は足していません）。この画面の集計は保存・送信しません。")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, LifeSpacing.screenHorizontal)
                .padding(.vertical, LifeSpacing.screenVertical)
            }
            .background(LifeColors.background.ignoresSafeArea())
            .navigationTitle("月次レポート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { viewModel.closeMonthlyReport() }
                        .accessibilityHint("お金の画面に戻ります")
                        .accessibilityIdentifier("money.monthlyReport.close")
                }
            }
        }
    }

    // MARK: - 月の切り替え（前の月・次の月・今月に戻る）

    private var monthSwitcher: some View {
        VStack(spacing: 0) {
            HStack(spacing: LifeSpacing.xs) {
                Button {
                    viewModel.showPreviousMonth()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(LifeColors.text)
                        .frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canShowPreviousMonth)
                .accessibilityLabel("前の月")
                .accessibilityIdentifier("money.monthlyReport.previousMonth")
                Spacer(minLength: LifeSpacing.xs)
                Text(viewModel.displayedMonthTitle)
                    .font(LifeTypography.headline)
                    .foregroundStyle(LifeColors.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: LifeSpacing.xs)
                Button {
                    viewModel.showNextMonth()
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(LifeColors.text)
                        .frame(width: LifeSpacing.minTapTarget, height: LifeSpacing.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canShowNextMonth)
                .accessibilityLabel("次の月")
                .accessibilityIdentifier("money.monthlyReport.nextMonth")
            }
            if !viewModel.isShowingCurrentMonth {
                Button("今月に戻る") { viewModel.showCurrentMonth() }
                    .font(LifeTypography.footnote)
                    .frame(minWidth: LifeSpacing.minTapTarget * 2, minHeight: LifeSpacing.minTapTarget)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("money.monthlyReport.currentMonth")
            }
        }
    }

    // MARK: - 合計

    private func totalSection(_ report: MonthlySpendingReport) -> some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
            Text(viewModel.reportScopeTitle.isEmpty ? "支出の合計" : "支出の合計（\(viewModel.reportScopeTitle)）")
                .font(LifeTypography.caption)
                .foregroundStyle(LifeColors.secondaryText)
            Text(report.totalText)
                .font(LifeTypography.bigNumeral)
                .foregroundStyle(LifeColors.text)
            if report.hasExpenses {
                Text("\(report.expenseCount)件")
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.reportTotalSpokenLabel(report))
        .accessibilityIdentifier("money.monthlyReport.total")
    }

    // MARK: - 予算と残り（自分だけ・わが家で共有を別々に。足さない）

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            LifeSectionTitle("予算と残り")
            ForEach(viewModel.budgetSummaries) { summary in
                VStack(alignment: .leading, spacing: 0) {
                    LifeDivider()
                    HStack(spacing: LifeSpacing.xs) {
                        Text(summary.scope.budgetTitle)
                            .font(LifeTypography.callout)
                            .foregroundStyle(LifeColors.text)
                        if summary.scope == .household { HouseholdSharedMark() }
                    }
                    .frame(minHeight: LifeSpacing.minTapTarget, alignment: .leading)
                    Text(viewModel.reportBudgetLine(summary) ?? "\(summary.scope.budgetTitle)は未設定です")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, LifeSpacing.xs)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(viewModel.budgetSpokenLabel(summary))
            }
            if viewModel.budgetSummaries.count > 1 {
                Text("自分だけの予算と、わが家の共有予算は足さずに別々に出しています。")
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 前月との差（評価・助言はしない）

    private func comparisonSection(_ comparison: MonthlySpendingComparison) -> some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
            LifeSectionTitle("前月との差")
            Text(comparison.text)
                .font(LifeTypography.callout)
                .foregroundStyle(LifeColors.text)
            if comparison.isAvailable {
                Text(comparison.periodText)
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.comparisonSpokenLabel(comparison))
        .accessibilityIdentifier("money.monthlyReport.comparison")
    }

    // MARK: - 最近6か月の推移（古い月から新しい月の順。選んでいる月を強調。タップでその月へ）

    private func trendSection(_ report: MonthlySpendingReport) -> some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            LifeSectionTitle("最近6か月の支出", trailing: "単位：円")
            MonthlyTrendChart(points: report.trend) { month in
                viewModel.selectReportMonth(month)
            }
            .frame(height: 180)
            // グラフの代わりに読める一覧（VoiceOver・色を見分けにくい人向け。押すとその月へ）
            VStack(alignment: .leading, spacing: 0) {
                ForEach(report.trend) { point in
                    Button {
                        viewModel.selectReportMonth(point.month)
                    } label: {
                        HStack {
                            Text(point.month.title)
                                .font(point.isSelected ? LifeTypography.headline : LifeTypography.callout)
                            if point.isSelected {
                                Text("表示中")
                                    .font(LifeTypography.caption)
                                    .foregroundStyle(LifeColors.secondaryText)
                            }
                            Spacer(minLength: LifeSpacing.xs)
                            Text(point.amountText)
                                .font(LifeTypography.callout)
                        }
                        .foregroundStyle(LifeColors.text)
                        .frame(minHeight: LifeSpacing.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(viewModel.trendSpokenLabel(point))
                    .accessibilityHint(Text(point.isSelected ? "表示中の月です" : "この月のレポートを見ます"))
                    .accessibilityIdentifier("money.monthlyReport.trendMonth")
                    LifeDivider()
                }
            }
        }
    }

    // MARK: - カテゴリー別（金額の多い順。金額・割合・棒。押すとその月・カテゴリーの支出一覧へ）

    private func categorySection(_ report: MonthlySpendingReport) -> some View {
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            LifeSectionTitle("カテゴリー別")
            if report.categories.isEmpty {
                Text("\(report.month.title)の支出はありません")
                    .font(LifeTypography.callout)
                    .foregroundStyle(LifeColors.secondaryText)
                    .frame(minHeight: LifeSpacing.minTapTarget, alignment: .leading)
                    .accessibilityIdentifier("money.monthlyReport.categoriesEmpty")
            } else {
                ForEach(report.categories) { share in
                    Button {
                        viewModel.openExpenseList(category: share.category)
                    } label: {
                        VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                            HStack {
                                Text(share.category.label)
                                    .font(LifeTypography.callout)
                                Spacer(minLength: LifeSpacing.xs)
                                Text("\(LifeFormatters.yen(share.amount))（\(share.percentText)）")
                                    .font(LifeTypography.callout)
                                Image(systemName: "chevron.right")
                                    .font(LifeTypography.footnote)
                                    .foregroundStyle(LifeColors.secondaryText)
                            }
                            .foregroundStyle(LifeColors.text)
                            ShareBar(share: share.share)
                        }
                        .frame(minHeight: LifeSpacing.minTapTarget)
                        .padding(.vertical, LifeSpacing.xxs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(viewModel.categoryShareSpokenLabel(share))
                    .accessibilityHint("\(report.month.title)の\(share.category.label)の支出一覧を見ます")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("money.monthlyReport.category")
                    LifeDivider()
                }
            }
        }
    }
}

/// 割合の棒（横棒。長さは割合。色だけでなく、上の行に金額と％を文字で出す）
private struct ShareBar: View {
    let share: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(LifeColors.divider)
                Capsule()
                    .fill(LifeCategoryColors.sage)
                    .frame(width: max(4, geometry.size.width * min(max(share, 0), 1)))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// 最近6か月の縦棒グラフ（Swift Charts。古い月から新しい月の順。選んでいる月は濃い色と「表示中」の文字。タップでその月へ）
struct MonthlyTrendChart: View {
    let points: [MonthlySpendingPoint]
    let onSelect: (BudgetMonth) -> Void

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("月", point.shortTitle),
                y: .value("金額（円）", point.amount)
            )
            .foregroundStyle(point.isSelected ? LifeColors.primary : LifeCategoryColors.sage.opacity(0.55))
            .annotation(position: .top) {
                if point.isSelected {
                    Text("表示中")
                        .font(LifeTypography.caption)
                        .foregroundStyle(LifeColors.text)
                }
            }
            .accessibilityLabel(point.month.title)
            .accessibilityValue(point.isFuture && !point.hasExpenses ? "記録なし" : LifeFormatters.yenSpoken(point.amount))
        }
        // 月の並び（古い月から新しい月）を、金額で並べ替えずにそのまま使う
        .chartXScale(domain: points.map(\.shortTitle))
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Int.self) {
                        Text(LifeFormatters.yen(amount))
                            .font(LifeTypography.caption)
                    }
                }
            }
        }
        .chartYAxisLabel("金額（円）")
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plotFrame = proxy.plotFrame else { return }
                        let x = location.x - geometry[plotFrame].origin.x
                        guard let title: String = proxy.value(atX: x),
                              let point = points.first(where: { $0.shortTitle == title }) else { return }
                        onSelect(point.month)
                    }
            }
        }
        .transaction { $0.animation = nil }
        .accessibilityIdentifier("money.monthlyReport.trendChart")
    }
}

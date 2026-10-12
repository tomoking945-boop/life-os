import SwiftUI

/// 保証書の画面への行き先（リスト・今日の両方の NavigationStack に登録する）
enum WarrantyRoute: Hashable {
    case list
    case detail(WarrantyDocument.ID)
}

extension View {
    /// 保証書の画面を開けるようにする
    func warrantyDestinations() -> some View {
        navigationDestination(for: WarrantyRoute.self) { route in
            switch route {
            case .list:
                WarrantyListView()
            case .detail(let id):
                WarrantyDetailView(documentID: id)
            }
        }
    }
}

/// 保証書の一覧（spec 3）
/// - Free（保存済みの保証書なし）：説明と Premium 案内
/// - Premium：一覧・検索・右上の＋から登録
/// - Premium 終了後：閲覧・写真表示・書き出し・削除だけ
struct WarrantyListView: View {
    @Environment(AppState.self) private var appState
    @Environment(LifeStore.self) private var store

    @State private var query = ""
    @State private var isCreating = false

    private var now: Date { LifeCalendar.now }

    private var access: WarrantyAccess {
        WarrantyAccess.resolve(isPremium: appState.isPremium, hasSavedDocuments: !store.warranties.isEmpty)
    }

    private var filtered: [WarrantyDocument] {
        store.warranties.filter { $0.matches(query) }
    }

    var body: some View {
        Group {
            if access == .locked {
                WarrantyIntroView()
            } else {
                list
            }
        }
        .lifeScreenBackground()
        .navigationTitle("保証書")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if access.canCreate {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreating = true
                    } label: {
                        Image(systemName: "plus")
                            .frame(minWidth: LifeSpacing.minTapTarget, minHeight: LifeSpacing.minTapTarget)
                    }
                    .accessibilityLabel("保証書を登録")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            WarrantyEditorView(repository: store, mode: .create)
                .lifeSheetPresentation()
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                LifeScreenHeader(eyebrow: "DOCUMENTS", title: "保証書", subtitle: "保証期限と、紙の保管場所をひとまとめに。")

                if access == .readOnly {
                    WarrantyReadOnlyNote()
                }

                if store.warranties.isEmpty {
                    LifeEmptyState(
                        systemImage: "doc.text.magnifyingglass",
                        title: "保証書はまだありません",
                        message: "右上の＋から、保証書やレシートの写真を登録できます。"
                    )
                    .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
                } else {
                    searchField

                    let groups = WarrantyListSection.group(filtered, now: now)
                    if groups.isEmpty {
                        Text("「\(query)」に合う保証書はありません")
                            .font(LifeTypography.callout)
                            .foregroundStyle(LifeColors.secondaryText)
                    }
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                            LifeSectionTitle(group.section.title, trailing: "\(group.documents.count)件")
                            LifeRuledList(group.documents) { document in
                                NavigationLink(value: WarrantyRoute.detail(document.id)) {
                                    WarrantyRow(document: document, now: now)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    storageFooter
                }
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
    }

    private var searchField: some View {
        HStack(spacing: LifeSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(LifeColors.secondaryText)
                .accessibilityHidden(true)
            TextField("製品名・メーカー・型番・購入店・保管場所", text: $query)
                .font(LifeTypography.body)
                .submitLabel(.search)
                .accessibilityLabel("保証書を検索")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(LifeColors.secondaryText)
                }
                .accessibilityLabel("検索をクリア")
            }
        }
        .padding(.horizontal, LifeSpacing.md)
        .frame(minHeight: LifeSpacing.buttonHeight)
        .background(RoundedRectangle(cornerRadius: LifeRadius.field, style: .continuous).fill(LifeColors.surface))
        .overlay(RoundedRectangle(cornerRadius: LifeRadius.field, style: .continuous).stroke(LifeColors.divider, lineWidth: 1))
    }

    /// 写真で使っている容量（spec 11：写真で容量を圧迫しないように）
    private var storageFooter: some View {
        let size = ByteCountFormatter.string(fromByteCount: store.warrantyAttachmentByteCount, countStyle: .file)
        return Text("写真 \(store.warrantyAttachments.count)枚・\(size)（この iPhone の中にだけ保存）")
            .font(LifeTypography.footnote)
            .foregroundStyle(LifeColors.secondaryText)
    }
}

/// 一覧の1行：製品名・期限・保管場所
struct WarrantyRow: View {
    let document: WarrantyDocument
    let now: Date

    var body: some View {
        HStack(alignment: .center, spacing: LifeSpacing.sm) {
            Image(systemName: document.category.systemImage)
                .font(.title3)
                .foregroundStyle(LifeColors.primary)
                .frame(width: LifeSpacing.xl)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                Text(document.title)
                    .font(LifeTypography.editorialHeadline)
                    .foregroundStyle(LifeColors.text)
                    .lineLimit(2)
                Text(expirationLine)
                    .font(LifeTypography.footnote)
                    .foregroundStyle(isSoon ? LifeCategoryColors.warmGold : LifeColors.secondaryText)
                if let location = document.physicalStorageLocation {
                    Label(location, systemImage: "archivebox")
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: LifeSpacing.xs)
            Image(systemName: "chevron.right")
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(.vertical, LifeSpacing.md)
        .frame(minHeight: LifeSpacing.minTapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("保証書の詳細を開きます")
    }

    private var isSoon: Bool {
        if case .expiringSoon = WarrantyExpiration.status(of: document, now: now) { return true }
        return false
    }

    private var expirationLine: String {
        guard let expiresAt = document.warrantyExpiresAt else { return "保証終了日 未入力" }
        return "保証終了 \(WarrantyExpiration.dateText(expiresAt))・\(WarrantyExpiration.remainingText(for: document, now: now))"
    }
}

/// Premium 終了後の案内
struct WarrantyReadOnlyNote: View {
    var body: some View {
        Label {
            Text("Premium が終了しているため、閲覧・写真の表示・書き出し・削除だけできます。再加入すると、同じデータから登録・編集を再開できます。")
                .font(LifeTypography.footnote)
                .foregroundStyle(LifeColors.text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock")
                .foregroundStyle(LifeColors.accent)
        }
        .padding(LifeSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lifeSurface(.suggestion, cornerRadius: LifeRadius.band)
    }
}

/// Free の説明（spec 3：実在する利用者データの見本は出さない）
struct WarrantyIntroView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.sectionGap) {
                LifeScreenHeader(eyebrow: "PREMIUM", title: "保証書を、\n探さなくていい場所へ")

                LifeGroupedSection {
                    VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                        introRow("camera", "保証書・レシート・製品ラベルを写真のまま保存")
                        introRow("text.viewfinder", "iPhone の中で文字を読み取り、製品名や購入日の候補を表示")
                        introRow("archivebox", "紙の原本を置いた場所もいっしょに記録")
                        introRow("bell", "保証が終わる30日前・7日前・当日にお知らせ")
                        introRow("lock.shield", "写真も読み取った文字も、外部へは送りません")
                    }
                    .padding(.vertical, LifeSpacing.sm)
                }

                NavigationLink {
                    PremiumView(appState: appState)
                } label: {
                    LifeButtonLabel(title: "Premium を見る", systemImage: "sparkles")
                }
                .buttonStyle(LifePressButtonStyle())
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
    }

    private func introRow(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LifeSpacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(LifeColors.accent)
                .frame(width: LifeSpacing.xl)
                .accessibilityHidden(true)
            Text(text)
                .font(LifeTypography.body)
                .foregroundStyle(LifeColors.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: LifeSpacing.minTapTarget - LifeSpacing.xs)
    }
}

// MARK: - Preview（主要な状態）

#if DEBUG
enum WarrantyPreviewData {
    static func store(now: Date = LifeCalendar.now) -> LifeStore {
        let calendar = LifeCalendar.calendar
        func days(_ value: Int) -> Date { calendar.date(byAdding: .day, value: value, to: LifeCalendar.startOfDay(now)) ?? now }
        let store = LifeStore()
        store.warranties = [
            WarrantyDocument(title: "冷蔵庫", category: .appliance, manufacturer: "見本メーカー", modelNumber: "AB-123",
                             retailer: "見本電器店", purchaseDate: days(-337), warrantyDuration: WarrantyDuration(value: 1, unit: .year),
                             warrantyExpiresAt: days(28), expirationSource: .calculated,
                             physicalStorageLocation: "リビングの書類ケース、上から2段目", createdAt: now, updatedAt: now),
            WarrantyDocument(title: "ソファ", category: .furniture, warrantyExpiresAt: days(300), expirationSource: .manual,
                             physicalStorageLocation: "寝室の引き出し", createdAt: now, updatedAt: now),
            WarrantyDocument(title: "電子レンジ", category: .appliance, warrantyExpiresAt: days(-20), expirationSource: .manual,
                             createdAt: now, updatedAt: now),
            WarrantyDocument(title: "ルーター", category: .digital, createdAt: now, updatedAt: now)
        ]
        return store
    }

    static func appState(plan: PlanType) -> AppState {
        let state = AppState()
        state.plan = plan
        return state
    }
}

#Preview("Premium") {
    NavigationStack { WarrantyListView().warrantyDestinations() }
        .environment(WarrantyPreviewData.appState(plan: .premium))
        .environment(WarrantyPreviewData.store())
}

#Preview("Premium 終了後") {
    NavigationStack { WarrantyListView().warrantyDestinations() }
        .environment(WarrantyPreviewData.appState(plan: .free))
        .environment(WarrantyPreviewData.store())
}

#Preview("Free") {
    NavigationStack { WarrantyListView() }
        .environment(WarrantyPreviewData.appState(plan: .free))
        .environment(LifeStore())
}
#endif

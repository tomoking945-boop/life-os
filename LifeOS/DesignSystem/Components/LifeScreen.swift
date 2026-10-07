import SwiftUI

// Calm Future 第4段階：全画面で同じ言葉づかいにするための共通部品。
// - LifeScreenHeader：小さな英字ラベル＋セリフ体の大見出し（今日画面の見出しと同じ階層）
// - LifeGroupedSection：白いカードではなく、紙色の面だけで区切るグループ（設定の行など）
// - LifeRuledList：カードに入れず、細い線だけで区切る行の並び
// - lifeSheetPresentation：Bottom Sheet の見え方（角丸・つまみ・背景）をそろえる

/// 画面の見出し（例：CALENDAR ／ カレンダー）
struct LifeScreenHeader<Trailing: View>: View {
    private let eyebrow: String
    private let title: String
    private let subtitle: String?
    private let trailing: Trailing

    init(eyebrow: String, title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: LifeSpacing.xs) {
            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                Text(eyebrow)
                    .font(LifeTypography.label)
                    .tracking(LifeTypography.labelTracking)
                    .foregroundStyle(LifeColors.secondaryText)
                    .accessibilityHidden(true)
                Text(title)
                    .font(LifeTypography.display)
                    .foregroundStyle(LifeColors.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(LifeTypography.callout)
                        .foregroundStyle(LifeColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: LifeSpacing.xs)
            trailing
        }
    }
}

extension LifeScreenHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// 紙色の面だけで区切るグループ（影なし）。見出しは小さな英字・日本語のラベル。
struct LifeGroupedSection<Content: View>: View {
    private let title: String?
    private let trailing: String?
    private let content: Content

    init(_ title: String? = nil, trailing: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            if let title {
                LifeSectionTitle(title, trailing: trailing)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, LifeSpacing.md)
            .padding(.vertical, LifeSpacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
        }
    }
}

/// 細い線だけで区切る行の並び（カードに入れない）
struct LifeRuledList<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    private let data: Data
    private let showsEdges: Bool
    private let row: (Data.Element) -> Row

    /// - Parameter showsEdges: 先頭と末尾にも線を引くか
    init(_ data: Data, showsEdges: Bool = true, @ViewBuilder row: @escaping (Data.Element) -> Row) {
        self.data = data
        self.showsEdges = showsEdges
        self.row = row
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsEdges {
                LifeDivider()
            }
            ForEach(Array(data.enumerated()), id: \.element.id) { index, element in
                if index > 0 {
                    LifeDivider()
                }
                row(element)
            }
            if showsEdges {
                LifeDivider()
            }
        }
    }
}

extension View {
    /// Bottom Sheet の見え方をそろえる（つまみ・大きめの角丸・Ivory の背景）
    func lifeSheetPresentation() -> some View {
        self
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(LifeRadius.sheet)
            .presentationBackground(LifeColors.background)
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: LifeSpacing.xl) {
            LifeScreenHeader(eyebrow: "LISTS", title: "リスト", subtitle: "行きたい場所や観たいものを、ためておく場所。")
            LifeGroupedSection("設定") {
                Text("通知").frame(minHeight: LifeSpacing.buttonHeight)
                LifeDivider()
                Text("表示設定").frame(minHeight: LifeSpacing.buttonHeight)
            }
        }
        .padding()
    }
    .background(LifeAmbientBackground(timeOfDay: .day))
}

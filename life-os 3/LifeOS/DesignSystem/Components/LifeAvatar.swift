import SwiftUI
import UIKit

/// プロフィール写真。写真がない場合は名前の頭文字を表示する。
struct LifeAvatar: View {
    enum Size {
        case small
        case medium
        case large
        case extraLarge

        var diameter: CGFloat {
            switch self {
            case .small: return 28
            case .medium: return 40
            case .large: return 64
            case .extraLarge: return 120
            }
        }
    }

    let name: String
    var image: UIImage?
    var size: Size = .medium

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LifeColors.primarySubtle
                Text(String(name.prefix(1)))
                    .font(.system(size: size.diameter * 0.42, design: .serif))
                    .foregroundStyle(LifeColors.primary)
            }
        }
        .frame(width: size.diameter, height: size.diameter)
        .clipShape(Circle())
        .overlay(Circle().stroke(LifeColors.divider, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name)のプロフィール写真")
    }
}

#Preview {
    HStack(spacing: LifeSpacing.md) {
        LifeAvatar(name: "池上", size: .small)
        LifeAvatar(name: "池上", size: .medium)
        LifeAvatar(name: "妻", size: .large)
    }
    .padding()
    .background(LifeColors.background)
}

import PhotosUI
import SwiftUI
import UIKit

/// プロフィール写真の変更。
/// 写真は端末内にだけ保存し、Firebase Storage へのアップロードは行わない。
struct PhotoChangeView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedItem: PhotosPickerItem?
    @State private var isLoading = false
    @State private var isShowingCameraNotice = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: LifeSpacing.xl) {
                ZStack {
                    LifeAvatar(name: appState.profile.name, image: appState.profileImage, size: .extraLarge)
                    if isLoading {
                        ProgressView()
                            .tint(LifeColors.primary)
                            .accessibilityLabel("写真を読み込み中")
                    }
                }
                .padding(.top, LifeSpacing.lg)

                VStack(spacing: LifeSpacing.sm) {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        LifeButtonLabel(title: "写真ライブラリから選択", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(LifePressButtonStyle())

                    // TODO: カメラ撮影は今回未実装（UIのみ）。実装時は Info.plist に NSCameraUsageDescription が必要。
                    LifeButton("写真を撮る", systemImage: "camera", kind: .secondary) {
                        isShowingCameraNotice = true
                    }

                    LifeButton("現在の写真を削除", systemImage: "trash", kind: .destructive) {
                        isConfirmingDelete = true
                    }
                    .disabled(appState.profileImage == nil)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.text)
                }

                Text("写真はこの端末の中だけで変更されます。")
                    .font(LifeTypography.footnote)
                    .foregroundStyle(LifeColors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.bottom, LifeSpacing.screenVertical)
        }
        .background(LifeColors.background.ignoresSafeArea())
        .navigationTitle("写真を変更")
        .navigationBarTitleDisplayMode(.inline)
        .quickAddAccessory()
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadImage(from: newItem) }
        }
        .confirmationDialog("現在の写真を削除しますか？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                appState.updateProfileImage(nil)
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("写真を撮る", isPresented: $isShowingCameraNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("カメラでの撮影はこの試作版ではまだ使えません。")
        }
    }

    @MainActor
    private func loadImage(from item: PhotosPickerItem) async {
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            selectedItem = nil
        }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                appState.updateProfileImage(image)
            } else {
                errorMessage = "写真を読み込めませんでした。"
            }
        } catch {
            errorMessage = "写真を読み込めませんでした。"
        }
    }
}

#Preview {
    NavigationStack {
        PhotoChangeView()
    }
    .environment(AppState())
}

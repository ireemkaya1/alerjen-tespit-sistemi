//
//  ContentView.swift
//  AlerjenTespitSistemi
//
//  Created by ASUS on 28.10.2026.
//

import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("Alerjen Tespit Sistemi")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text("Gıda etiketi fotoğrafı seçiniz.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            imageView

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            PhotosPicker(selection: $selectedItem, matching: .images) {
                Label(
                    selectedImage == nil ? "Fotoğraf Seç" : "Başka Fotoğraf Seç",
                    systemImage: "photo.on.rectangle"
                )
                .frame(maxWidth: .infinity)
                .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoading)

            Spacer()
        }
        .padding(24)
        .task(id: selectedItem) {
            await loadImage()
        }
    }

    @ViewBuilder
    private var imageView: some View {
        if let selectedImage {
            Image(uiImage: selectedImage)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Seçilen fotoğraf")
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.secondary.opacity(0.12))

                if isLoading {
                    ProgressView("Fotoğraf yükleniyor...")
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .accessibilityLabel("Fotoğraf alanı")
        }
    }

    @MainActor
    private func loadImage() async {
        guard let selectedItem else { return }

        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            guard let data = try await selectedItem.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "Fotoğraf yüklenemedi. Lütfen başka bir fotoğraf seçiniz."
                return
            }

            selectedImage = image
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Fotoğraf yüklenirken bir hata oluştu. Lütfen tekrar deneyiniz."
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

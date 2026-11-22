//
//  ContentView.swift
//  AlerjenTespitSistemi
//
//  Created by ASUS on 28.10.2026.
//

import SwiftUI
import PhotosUI

private enum TextResult: Identifiable {
    case raw
    case normalized

    var id: Self { self }

    var title: String {
        switch self {
        case .raw:
            return "Tanınan Ham Metin"
        case .normalized:
            return "Normalize Edilmiş Metin"
        }
    }
}

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var previewImage: UIImage?
    @State private var mode = ImageMode.original
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var prepError: String?
    @State private var isPreparing = false
    @State private var rawText = ""
    @State private var normalizedText = ""
    @State private var ocrError: String?
    @State private var isReading = false
    @State private var imageID = UUID()
    @State private var ocrTask: Task<Void, Never>?
    @State private var prepTask: Task<Void, Never>?
    @State private var activeResult: TextResult?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
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

                    if selectedImage != nil {
                        Picker("Görüntü işleme", selection: $mode) {
                            ForEach(ImageMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    if let prepError {
                        Text(prepError)
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

                    if selectedImage != nil {
                        Button(action: readText) {
                            if isReading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("Metni Oku", systemImage: "text.viewfinder")
                                    .frame(maxWidth: .infinity)
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(isLoading || isPreparing || isReading || previewImage == nil)
                    }

                    if let ocrError {
                        Text(ocrError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    if !rawText.isEmpty {
                        VStack(spacing: 8) {
                            resultRow(.raw)
                            resultRow(.normalized)
                        }
                    }

                    Spacer()
                }
                .padding(24)
                .frame(minHeight: geometry.size.height)
            }
        }
        .task(id: selectedItem) {
            await loadImage()
        }
        .onChange(of: mode) {
            clearRecognition()
            prepareImage()
        }
        .sheet(item: $activeResult) { result in
            resultSheet(result)
        }
    }

    private func resultRow(_ result: TextResult) -> some View {
        Button {
            activeResult = result
        } label: {
            HStack {
                Text(result.title)
                    .fontWeight(.semibold)

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .contentShape(Rectangle())
            .background(
                Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
    }

    private func resultSheet(_ result: TextResult) -> some View {
        NavigationStack {
            ScrollView {
                Text(text(for: result))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle(result.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") {
                        activeResult = nil
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Kopyala", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = text(for: result)
                    }
                }
            }
        }
    }

    private func text(for result: TextResult) -> String {
        switch result {
        case .raw:
            return rawText
        case .normalized:
            return normalizedText
        }
    }

    @ViewBuilder
    private var imageView: some View {
        if let previewImage {
            Image(uiImage: previewImage)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity, maxHeight: 200)
                .accessibilityLabel("Seçilen fotoğraf")
        } else if isPreparing {
            ProgressView("Görüntü hazırlanıyor...")
                .frame(maxWidth: .infinity)
                .frame(height: 200)
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

        resetImageState()
        let currentID = imageID
        isLoading = true
        errorMessage = nil

        defer {
            if currentID == imageID {
                isLoading = false
            }
        }

        do {
            guard let data = try await selectedItem.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                guard currentID == imageID else { return }
                errorMessage = "Fotoğraf yüklenemedi. Lütfen başka bir fotoğraf seçiniz."
                return
            }

            guard !Task.isCancelled, currentID == imageID else { return }
            selectedImage = image
            prepareImage()
        } catch is CancellationError {
            return
        } catch {
            guard currentID == imageID else { return }
            errorMessage = "Fotoğraf yüklenirken bir hata oluştu. Lütfen tekrar deneyiniz."
        }
    }

    @MainActor
    private func readText() {
        guard let selectedImage else { return }

        ocrTask?.cancel()

        let currentID = imageID
        let currentMode = mode
        isReading = true
        rawText = ""
        normalizedText = ""
        activeResult = nil
        ocrError = nil

        ocrTask = Task {
            do {
                let text = try await OCR.recognize(selectedImage, mode: currentMode)
                guard !Task.isCancelled, currentID == imageID else { return }

                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ocrError = "Fotoğrafta okunabilir metin bulunamadı."
                } else {
                    rawText = text
                    normalizedText = TextPrep.normalize(text)
                }
            } catch is CancellationError {
                return
            } catch {
                guard currentID == imageID else { return }
                ocrError = "Metin okunurken bir hata oluştu. Lütfen tekrar deneyiniz."
            }

            guard currentID == imageID else { return }
            isReading = false
        }
    }

    @MainActor
    private func clearRecognition() {
        ocrTask?.cancel()
        ocrTask = nil
        imageID = UUID()
        rawText = ""
        normalizedText = ""
        activeResult = nil
        ocrError = nil
        isReading = false
    }

    @MainActor
    private func prepareImage() {
        prepTask?.cancel()
        prepTask = nil
        previewImage = nil
        prepError = nil

        guard let selectedImage else {
            isPreparing = false
            return
        }

        let currentID = imageID
        let currentMode = mode
        isPreparing = true

        prepTask = Task {
            do {
                let image = try await ImagePrep.process(selectedImage, mode: currentMode)
                guard !Task.isCancelled, currentID == imageID, currentMode == mode else {
                    return
                }
                previewImage = image
            } catch is CancellationError {
                return
            } catch {
                guard currentID == imageID, currentMode == mode else { return }
                prepError = "Görüntü hazırlanırken bir hata oluştu. Lütfen tekrar deneyiniz."
            }

            guard currentID == imageID, currentMode == mode else { return }
            isPreparing = false
        }
    }

    @MainActor
    private func resetImageState() {
        clearRecognition()
        prepTask?.cancel()
        prepTask = nil
        selectedImage = nil
        previewImage = nil
        prepError = nil
        isPreparing = false
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

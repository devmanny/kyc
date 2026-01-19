//
//  CameraPreviewView.swift
//  KYC
//

import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer?

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Remover layers anteriores
        uiView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }

        guard let previewLayer = previewLayer else { return }

        previewLayer.frame = uiView.bounds
        uiView.layer.addSublayer(previewLayer)
    }
}

// Wrapper para manejar el tamaño correctamente
struct CameraPreviewContainer: View {
    let previewLayer: AVCaptureVideoPreviewLayer?

    var body: some View {
        GeometryReader { geometry in
            CameraPreviewView(previewLayer: previewLayer)
                .onAppear {
                    previewLayer?.frame = CGRect(origin: .zero, size: geometry.size)
                }
                .onChange(of: geometry.size) { _, newSize in
                    previewLayer?.frame = CGRect(origin: .zero, size: newSize)
                }
        }
    }
}

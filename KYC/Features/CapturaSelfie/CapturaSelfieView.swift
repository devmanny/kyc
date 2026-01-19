//
//  CapturaSelfieView.swift
//  KYC
//

import SwiftUI

struct CapturaSelfieView: View {
    let tipo: TipoSelfie
    let onCaptura: (UIImage) -> Void
    let onRegresar: () -> Void

    @StateObject private var cameraService = CameraService()
    @State private var fotoPreview: UIImage?
    @State private var mostrandoPreview = false
    @State private var errorCamara: String?
    @State private var previewSize: CGSize = .zero

    private var titulo: String {
        switch tipo {
        case .cercana: return "Selfie Cercana"
        case .lejana: return "Selfie Lejana"
        }
    }

    private var instruccion: String {
        switch tipo {
        case .cercana: return "Acerca tu rostro hasta que llene el óvalo"
        case .lejana: return "Aléjate hasta que tu rostro quepa en el óvalo"
        }
    }

    private var instruccionCorta: String {
        switch tipo {
        case .cercana: return "Acércate"
        case .lejana: return "Aléjate"
        }
    }

    private var tamanoOvalo: (width: CGFloat, height: CGFloat) {
        switch tipo {
        case .cercana: return (220, 300)
        case .lejana: return (140, 190)
        }
    }

    private var iconoTipo: String {
        switch tipo {
        case .cercana: return "person.crop.circle"
        case .lejana: return "person.crop.circle.badge.minus"
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if mostrandoPreview, let foto = fotoPreview {
                previewFotoView(foto)
            } else {
                camaraView
            }
        }
        .navigationTitle(titulo)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: onRegresar) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Atrás")
                    }
                }
            }
        }
        .task {
            await configurarCamara()
        }
        .onDisappear {
            cameraService.detenerCaptura()
        }
        .alert("Error de cámara", isPresented: .constant(errorCamara != nil)) {
            Button("OK") { errorCamara = nil }
        } message: {
            Text(errorCamara ?? "")
        }
    }

    // MARK: - Cámara View

    private var camaraView: some View {
        GeometryReader { geometry in
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom

            ZStack {
                // Preview de cámara (ignora safe areas)
                CameraPreviewContainer(previewLayer: cameraService.previewLayer)
                    .ignoresSafeArea()

                // Guía ovalada con efecto glass
                guiaOvalada

                // Controles flotantes con Liquid Glass (respeta safe areas)
                VStack {
                    // Instrucción superior - debajo de Dynamic Island
                    topInstructionBar
                        .padding(.top, safeTop + 16)

                    Spacer()

                    // Botón de captura
                    botonCaptura
                        .padding(.bottom, safeBottom + 40)
                }
                .padding(.horizontal)
            }
            .onAppear {
                // El preview layer llena TODA la pantalla (ignora safe areas)
                // Necesitamos el tamaño completo, no solo el área segura
                let fullHeight = geometry.size.height + safeTop + safeBottom
                previewSize = CGSize(width: geometry.size.width, height: fullHeight)
                print("CapturaSelfie: previewSize = \(previewSize) (geometry=\(geometry.size), safeTop=\(safeTop), safeBottom=\(safeBottom))")
            }
            .onChange(of: geometry.size) { _, newSize in
                let fullHeight = newSize.height + safeTop + safeBottom
                previewSize = CGSize(width: newSize.width, height: fullHeight)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Top Instruction Bar (Liquid Glass)

    private var topInstructionBar: some View {
        HStack(spacing: 12) {
            Image(systemName: iconoTipo)
                .font(.title2)
                .foregroundStyle(tipo == .cercana ? .green : .blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(instruccionCorta)
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(instruccion)
                    .font(.caption)
                    .opacity(0.8)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: - Guía Ovalada

    private var guiaOvalada: some View {
        ZStack {
            // Óvalo exterior con glow
            Ellipse()
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.8), .white.opacity(0.4)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 3
                )
                .frame(width: tamanoOvalo.width, height: tamanoOvalo.height)
                .shadow(color: .white.opacity(0.3), radius: 10)

            // Indicador de tipo
            VStack {
                Spacer()
                    .frame(height: tamanoOvalo.height / 2 + 20)

                Text(tipo == .cercana ? "CERCA" : "LEJOS")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: .capsule)
            }
        }
    }

    // MARK: - Botón de Captura (Liquid Glass)

    private var botonCaptura: some View {
        VStack(spacing: 12) {
            // Indicador de estado
            HStack(spacing: 8) {
                if cameraService.estaEnfocando {
                    ProgressView()
                        .tint(.yellow)
                    Text("Enfocando...")
                        .font(.caption)
                        .fontWeight(.medium)
                } else if cameraService.estaListo {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Listo")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)

            // Botón de captura estilo iOS 26
            Button(action: capturarFoto) {
                ZStack {
                    // Anillo exterior con glass
                    Circle()
                        .fill(.clear)
                        .frame(width: 80, height: 80)
                        .glassEffect(.regular, in: .circle)

                    // Círculo interior blanco
                    Circle()
                        .fill(.white)
                        .frame(width: 64, height: 64)
                }
            }
            .disabled(!cameraService.estaListo)
            .opacity(cameraService.estaListo ? 1 : 0.5)
        }
    }

    // MARK: - Preview View

    private func previewFotoView(_ foto: UIImage) -> some View {
        ZStack {
            // Fondo negro
            Color.black.ignoresSafeArea()

            // Foto capturada
            Image(uiImage: foto)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Controles flotantes (respetan safe areas)
            VStack {
                // Título superior
                Text("¿La foto se ve bien?")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)

                Spacer()

                // Botones de acción con Liquid Glass
                GlassEffectContainer(spacing: 16) {
                    HStack(spacing: 24) {
                        // Repetir
                        Button(action: repetirFoto) {
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                Text("Repetir")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(.white)
                            .frame(width: 100, height: 90)
                        }
                        .glassEffect(.regular.tint(.red.opacity(0.4)).interactive(), in: RoundedRectangle(cornerRadius: 20))

                        // Usar foto
                        Button(action: usarFoto) {
                            VStack(spacing: 8) {
                                Image(systemName: "checkmark")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                Text("Usar")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(.white)
                            .frame(width: 100, height: 90)
                        }
                        .glassEffect(.regular.tint(.green.opacity(0.4)).interactive(), in: RoundedRectangle(cornerRadius: 20))
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Acciones

    private func configurarCamara() async {
        do {
            try await cameraService.configurarCamara(tipo: .frontal)
            cameraService.iniciarCaptura()
        } catch {
            errorCamara = "No se pudo acceder a la cámara frontal."
        }
    }

    private func capturarFoto() {
        Task {
            // Capturar foto recortada al área visible del preview
            if let foto = await cameraService.capturarFotoVisibleEnPreview(previewSize: previewSize) {
                fotoPreview = foto
                mostrandoPreview = true
                cameraService.detenerCaptura()
            }
        }
    }

    private func repetirFoto() {
        fotoPreview = nil
        mostrandoPreview = false
        cameraService.iniciarCaptura()
    }

    private func usarFoto() {
        if let foto = fotoPreview {
            onCaptura(foto)
        }
    }
}

#Preview {
    NavigationStack {
        CapturaSelfieView(tipo: .cercana, onCaptura: { _ in }, onRegresar: {})
    }
}

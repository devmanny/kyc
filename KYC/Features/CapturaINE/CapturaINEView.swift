//
//  CapturaINEView.swift
//  KYC
//

import SwiftUI

enum TipoCapturaINE {
    case frente
    case reverso

    var titulo: String {
        switch self {
        case .frente: return "Frente de INE"
        case .reverso: return "Reverso de INE"
        }
    }

    var instruccion: String {
        switch self {
        case .frente: return "Coloca el frente de tu INE dentro del marco"
        case .reverso: return "Ahora voltea tu INE y coloca el reverso"
        }
    }
}

struct CapturaINEView: View {
    let tipo: TipoCapturaINE
    let onCaptura: (UIImage) -> Void
    let onRegresar: () -> Void

    @StateObject private var cameraService = CameraService()
    @State private var fotoPreview: UIImage?
    @State private var mostrandoPreview = false
    @State private var errorCamara: String?
    @State private var puntoEnfoque: CGPoint?
    @State private var mostrarIndicadorEnfoque = false
    @State private var mostrarConfiguracion = false
    @State private var previewSize: CGSize = .zero

    var body: some View {
        ZStack {
            // Fondo negro
            Color.black.ignoresSafeArea()

            if mostrandoPreview, let foto = fotoPreview {
                // Vista de preview de foto tomada
                previewFotoView(foto)
            } else {
                // Vista de cámara
                camaraView
            }
        }
        .navigationTitle(tipo.titulo)
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

                // Marco guía para INE (proporción 1.586:1)
                marcoGuiaINE

                // Indicador de enfoque
                if mostrarIndicadorEnfoque, let punto = puntoEnfoque {
                    indicadorEnfoque
                        .position(punto)
                }

                // Controles flotantes con Liquid Glass (respeta safe areas)
                VStack {
                    // Barra superior - debajo de Dynamic Island
                    topControlsBar
                        .padding(.top, safeTop + 12)

                    Spacer()

                    // Selector de lentes sobre el canvas
                    if cameraService.lentesDisponibles.count > 1 {
                        lensSelector
                            .padding(.bottom, 16)
                    }

                    // Botón de captura
                    botonCaptura
                        .padding(.bottom, safeBottom + 30)
                }
                .padding(.horizontal)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                enfocarEn(punto: location, enArea: geometry.size)
            }
            .onAppear {
                // El preview layer llena TODA la pantalla (ignora safe areas)
                // Necesitamos el tamaño completo, no solo el área segura
                let fullHeight = geometry.size.height + safeTop + safeBottom
                previewSize = CGSize(width: geometry.size.width, height: fullHeight)
                print("CapturaINE: previewSize = \(previewSize) (geometry=\(geometry.size), safeTop=\(safeTop), safeBottom=\(safeBottom))")
            }
            .onChange(of: geometry.size) { _, newSize in
                let fullHeight = newSize.height + safeTop + safeBottom
                previewSize = CGSize(width: newSize.width, height: fullHeight)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $mostrarConfiguracion) {
            CameraSettingsView(cameraService: cameraService, isPresented: $mostrarConfiguracion)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Top Controls Bar (Liquid Glass)

    private var topControlsBar: some View {
        GlassEffectContainer(spacing: 20) {
            HStack {
                // Botón de configuración
                Button(action: { mostrarConfiguracion = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)

                Spacer()

                // Instrucciones
                VStack(spacing: 2) {
                    Text(tipo.instruccion)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Toca para enfocar")
                        .font(.caption2)
                        .opacity(0.8)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)

                Spacer()

                // Botón de flash
                Button(action: { cameraService.toggleFlash() }) {
                    Image(systemName: cameraService.flashActivado ? "bolt.fill" : "bolt.slash")
                        .font(.title3)
                        .foregroundStyle(cameraService.flashActivado ? .yellow : .white)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
            }
        }
    }

    // MARK: - Selector de Lentes (Liquid Glass)

    private var lensSelector: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(cameraService.lentesDisponibles) { lente in
                    Button(action: {
                        Task {
                            try? await cameraService.cambiarLente(lente)
                        }
                    }) {
                        Text(lenteSimbolo(lente))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(cameraService.lenteSeleccionado == lente ? .yellow : .white)
                            .frame(width: 48, height: 48)
                    }
                    .glassEffect(
                        cameraService.lenteSeleccionado == lente
                            ? .regular.tint(.yellow.opacity(0.3)).interactive()
                            : .regular.interactive(),
                        in: .circle
                    )
                }
            }
        }
    }

    private func lenteSimbolo(_ lente: LenteCamara) -> String {
        switch lente {
        case .ultraWide: return "0.5"
        case .granAngular: return "1x"
        case .telefoto: return "3"
        }
    }

    private var indicadorEnfoque: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(Color.yellow, lineWidth: 2)
            .frame(width: 80, height: 80)
            .animation(.easeOut(duration: 0.2), value: puntoEnfoque)
    }

    private var marcoGuiaINE: some View {
        GeometryReader { geometry in
            let width = geometry.size.width * 0.9
            let height = width / 1.586 // Proporción de tarjeta INE

            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white, lineWidth: 3)
                .frame(width: width, height: height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    private var botonCaptura: some View {
        VStack(spacing: 12) {
            // Indicador de estado con Liquid Glass
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
            try await cameraService.configurarCamara(tipo: .trasera)
            cameraService.iniciarCaptura()
        } catch {
            errorCamara = "No se pudo acceder a la cámara. Verifica los permisos en Configuración."
        }
    }

    private func capturarFoto() {
        Task {
            // Para INE: usar imagen completa (sin recortar) para mejor detección de rostro y OCR
            // El recorte puede afectar la calidad y cortar partes importantes
            if let foto = await cameraService.capturarFoto() {
                fotoPreview = foto
                mostrandoPreview = true
                cameraService.detenerCaptura()
            }
        }
    }

    /// Calcula el rectángulo de la guía INE basado en el tamaño del preview
    /// - Parameter conMargen: Porcentaje de margen adicional (0.15 = 15% extra en cada lado)
    private func calcularRectINE(enPreviewSize size: CGSize, conMargen margen: CGFloat = 0) -> CGRect {
        let width = size.width * 0.9
        let height = width / 1.586 // Proporción de tarjeta INE

        // Agregar margen proporcional
        let marginX = width * margen
        let marginY = height * margen
        let expandedWidth = width + (marginX * 2)
        let expandedHeight = height + (marginY * 2)

        let x = (size.width - expandedWidth) / 2
        let y = (size.height - expandedHeight) / 2

        return CGRect(x: x, y: y, width: expandedWidth, height: expandedHeight)
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

    private func enfocarEn(punto: CGPoint, enArea size: CGSize) {
        // Mostrar indicador visual
        puntoEnfoque = punto
        mostrarIndicadorEnfoque = true

        // Pasar coordenadas directas del preview layer
        // El CameraService usa captureDevicePointConverted para convertir correctamente
        cameraService.enfocarEn(puntoEnPreview: punto)

        // Ocultar indicador después de 1.5 segundos
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            mostrarIndicadorEnfoque = false
        }
    }
}

#Preview {
    NavigationStack {
        CapturaINEView(tipo: .frente, onCaptura: { _ in }, onRegresar: {})
    }
}

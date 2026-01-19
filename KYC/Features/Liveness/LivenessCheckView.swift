//
//  LivenessCheckView.swift
//  KYC
//
//  Vista de verificación de vida con challenges interactivos
//

import SwiftUI
import AVFoundation

struct LivenessCheckView: View {
    let challenge: LivenessChallenge
    let onCompletado: () -> Void
    let onFallido: (String) -> Void
    let onRegresar: () -> Void

    @StateObject private var cameraService = CameraService()
    @State private var livenessService = LivenessDetectionService()
    @State private var progreso: Float = 0
    @State private var mensaje: String = ""
    @State private var completado = false
    @State private var fallido = false
    @State private var errorCamara: String?
    @State private var tiempoRestante: Int = 15
    @State private var mostrandoExito = false

    private let tiempoLimite = 15 // segundos

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                let safeTop = geometry.safeAreaInsets.top
                let safeBottom = geometry.safeAreaInsets.bottom

                ZStack {
                    // Preview de cámara
                    CameraPreviewContainer(previewLayer: cameraService.previewLayer)
                        .ignoresSafeArea()

                    // Guía ovalada
                    guiaOvalada

                    // UI flotante
                    VStack {
                        // Header con instrucciones
                        instructionHeader
                            .padding(.top, safeTop + 16)

                        Spacer()

                        // Progreso y timer
                        progressSection
                            .padding(.bottom, safeBottom + 40)
                    }
                    .padding(.horizontal)

                    // Overlay de éxito
                    if mostrandoExito {
                        exitoOverlay
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationTitle("Verificación de Vida")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    cameraService.detenerCaptura()
                    onRegresar()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Atrás")
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .task {
            await iniciar()
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

    // MARK: - Instruction Header

    private var instructionHeader: some View {
        VStack(spacing: 12) {
            // Icono del challenge
            Image(systemName: challenge.icono)
                .font(.system(size: 40))
                .foregroundStyle(completado ? .green : .white)
                .frame(width: 80, height: 80)
                .glassEffect(.regular.tint(completado ? .green.opacity(0.3) : .blue.opacity(0.3)), in: .circle)

            // Instrucción
            Text(challenge.instruccion)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)

            // Mensaje de estado
            if !mensaje.isEmpty {
                Text(mensaje)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(completado ? .green.opacity(0.2) : .clear), in: .capsule)
            }
        }
    }

    // MARK: - Guía Ovalada

    private var guiaOvalada: some View {
        ZStack {
            // Óvalo con borde animado
            Ellipse()
                .stroke(
                    LinearGradient(
                        colors: [
                            completado ? .green : .white.opacity(0.8),
                            completado ? .green.opacity(0.6) : .white.opacity(0.4)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: completado ? 4 : 3
                )
                .frame(width: 220, height: 300)
                .shadow(color: completado ? .green.opacity(0.5) : .white.opacity(0.3), radius: 10)

            // Indicador de progreso circular alrededor del óvalo
            if !completado {
                Circle()
                    .trim(from: 0, to: CGFloat(progreso))
                    .stroke(Color.green, lineWidth: 4)
                    .frame(width: 320, height: 320)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: progreso)
            }
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(spacing: 16) {
            // Timer
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .foregroundStyle(tiempoRestante <= 3 ? .red : .white)
                Text("\(tiempoRestante)s")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(tiempoRestante <= 3 ? .red : .white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .glassEffect(.regular.tint(tiempoRestante <= 3 ? .red.opacity(0.3) : .clear), in: .capsule)

            // Barra de progreso
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.2))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(completado ? .green : .blue)
                        .frame(width: geo.size.width * CGFloat(progreso), height: 8)
                        .animation(.linear(duration: 0.1), value: progreso)
                }
            }
            .frame(height: 8)
            .padding(.horizontal, 40)

            // Texto de ayuda
            Text(textoAyuda)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
        }
    }

    private var textoAyuda: String {
        switch challenge {
        case .blink:
            return "Parpadea naturalmente mirando a la cámara"
        case .turnLeft:
            return "Gira lentamente tu cabeza hacia la izquierda"
        case .turnRight:
            return "Gira lentamente tu cabeza hacia la derecha"
        case .smile:
            return "Sonríe de forma natural"
        }
    }

    // MARK: - Éxito Overlay

    private var exitoOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)

                Text("¡Verificación completada!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Eres una persona real")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(40)
            .glassEffect(.regular.tint(.green.opacity(0.2)), in: CGFloat(24))
        }
        .transition(.opacity)
    }

    // MARK: - Lógica

    private func iniciar() async {
        do {
            try await cameraService.configurarCamara(tipo: .frontal)
            cameraService.iniciarCaptura()

            mensaje = "Preparando..."
            try? await Task.sleep(nanoseconds: 500_000_000)
            mensaje = "Mira a la cámara"

            await ejecutarChallenge()
        } catch {
            errorCamara = "No se pudo acceder a la cámara frontal"
        }
    }

    private func ejecutarChallenge() async {
        let startTime = Date()
        var blinkCount = 0
        var hasLookedDirection = false
        var hasSmiled = false
        var lastBlinkTime: Date?

        while Date().timeIntervalSince(startTime) < Double(tiempoLimite) && !completado {
            // Actualizar timer
            await MainActor.run {
                tiempoRestante = max(0, tiempoLimite - Int(Date().timeIntervalSince(startTime)))
            }

            // Capturar frame y procesar
            if let imagen = await cameraService.capturarFoto() {
                do {
                    let state = try await livenessService.processFrame(imagen)

                    await MainActor.run {
                        // Verificar challenge según tipo
                        switch challenge {
                        case .blink:
                            if state.isBlinking {
                                if lastBlinkTime == nil || Date().timeIntervalSince(lastBlinkTime!) > 0.3 {
                                    blinkCount += 1
                                    lastBlinkTime = Date()
                                    mensaje = "¡Parpadeo detectado!"
                                    progreso = 1.0
                                    completarChallenge()
                                }
                            } else {
                                // Mostrar progreso basado en qué tan cerrados están los ojos
                                let eyeCloseness = 1.0 - ((state.leftEyeOpenness + state.rightEyeOpenness) / 2.0)
                                progreso = eyeCloseness
                                if eyeCloseness > 0.3 {
                                    mensaje = "Sigue cerrando los ojos..."
                                } else {
                                    mensaje = "Parpadea cerrando los ojos completamente"
                                }
                            }

                        case .turnLeft:
                            if state.isTurnedLeft {
                                hasLookedDirection = true
                                mensaje = "¡Bien! Giro detectado"
                                progreso = 1.0
                                completarChallenge()
                            } else {
                                progreso = max(0, min(1, Float(-state.yaw) / 0.3))
                                mensaje = state.yaw < -0.1 ? "Sigue girando..." : "Gira a la izquierda"
                            }

                        case .turnRight:
                            if state.isTurnedRight {
                                hasLookedDirection = true
                                mensaje = "¡Bien! Giro detectado"
                                progreso = 1.0
                                completarChallenge()
                            } else {
                                progreso = max(0, min(1, Float(state.yaw) / 0.3))
                                mensaje = state.yaw > 0.1 ? "Sigue girando..." : "Gira a la derecha"
                            }

                        case .smile:
                            progreso = state.smileAmount
                            if state.isSmiling {
                                hasSmiled = true
                                mensaje = "¡Sonrisa detectada!"
                                completarChallenge()
                            } else if state.smileAmount > 0.2 {
                                mensaje = "Sonríe más..."
                            } else {
                                mensaje = "Sonríe"
                            }
                        }
                    }
                } catch {
                    await MainActor.run {
                        mensaje = "Mantén tu rostro visible"
                    }
                }
            }

            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms entre frames
        }

        // Timeout
        if !completado {
            await MainActor.run {
                fallido = true
                mensaje = "Tiempo agotado"
                onFallido("No se completó el desafío a tiempo. Intenta de nuevo.")
            }
        }
    }

    private func completarChallenge() {
        guard !completado else { return }
        completado = true
        progreso = 1.0
        mensaje = "¡Completado!"

        // Mostrar overlay de éxito
        withAnimation {
            mostrandoExito = true
        }

        // Esperar y continuar
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 segundos
            await MainActor.run {
                cameraService.detenerCaptura()
                onCompletado()
            }
        }
    }
}

#Preview {
    NavigationStack {
        LivenessCheckView(
            challenge: .blink,
            onCompletado: { print("Completado") },
            onFallido: { print("Fallido: \($0)") },
            onRegresar: { print("Regresar") }
        )
    }
}

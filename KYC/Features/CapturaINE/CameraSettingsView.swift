//
//  CameraSettingsView.swift
//  KYC
//

import SwiftUI

struct CameraSettingsView: View {
    @ObservedObject var cameraService: CameraService
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 24) {
            // Título
            Text("Configuración de Cámara")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .padding(.top, 8)

            ScrollView {
                VStack(spacing: 20) {
                    // Sección: Lente
                    if !cameraService.lentesDisponibles.isEmpty {
                        settingsSection(title: "Lente", icon: "camera.aperture") {
                            GlassEffectContainer(spacing: 8) {
                                HStack(spacing: 12) {
                                    ForEach(cameraService.lentesDisponibles) { lente in
                                        lensButton(lente)
                                    }
                                }
                            }
                        }
                    }

                    // Sección: Modo de Enfoque
                    settingsSection(title: "Enfoque", icon: "scope") {
                        GlassEffectContainer(spacing: 8) {
                            HStack(spacing: 12) {
                                ForEach(ModoEnfoque.allCases) { modo in
                                    focusModeButton(modo)
                                }
                            }
                        }
                    }

                    // Sección: Flash
                    settingsSection(title: "Iluminación", icon: "bolt.fill") {
                        flashToggle
                    }

                    // Botón forzar enfoque
                    Button(action: {
                        cameraService.forzarEnfoque()
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "scope")
                                .font(.title3)
                            Text("Forzar Enfoque Ahora")
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))

                    // Indicador de estado
                    statusIndicator
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
    }

    // MARK: - Components

    private func settingsSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lensButton(_ lente: LenteCamara) -> some View {
        let isSelected = cameraService.lenteSeleccionado == lente

        return Button(action: {
            Task {
                try? await cameraService.cambiarLente(lente)
            }
        }) {
            VStack(spacing: 6) {
                Image(systemName: lente.icono)
                    .font(.title2)
                Text(lente.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isSelected ? .yellow : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .glassEffect(
            isSelected ? .regular.tint(.yellow.opacity(0.3)).interactive() : .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private func focusModeButton(_ modo: ModoEnfoque) -> some View {
        let isSelected = cameraService.modoEnfoque == modo

        return Button(action: {
            cameraService.cambiarModoEnfoque(modo)
        }) {
            VStack(spacing: 6) {
                Image(systemName: modo.icono)
                    .font(.title2)
                Text(modo.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isSelected ? .blue : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .glassEffect(
            isSelected ? .regular.tint(.blue.opacity(0.3)).interactive() : .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private var flashToggle: some View {
        Button(action: {
            cameraService.toggleFlash()
        }) {
            HStack(spacing: 14) {
                Image(systemName: cameraService.flashActivado ? "bolt.fill" : "bolt.slash")
                    .font(.title2)
                    .foregroundStyle(cameraService.flashActivado ? .yellow : .white)
                    .frame(width: 44, height: 44)
                    .glassEffect(
                        cameraService.flashActivado ? .regular.tint(.yellow.opacity(0.4)) : .regular,
                        in: .circle
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(cameraService.flashActivado ? "Flash Activado" : "Flash Desactivado")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Ilumina el documento")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Toggle indicator
                Capsule()
                    .fill(cameraService.flashActivado ? Color.yellow : Color.gray.opacity(0.4))
                    .frame(width: 50, height: 30)
                    .overlay(
                        Circle()
                            .fill(.white)
                            .frame(width: 26, height: 26)
                            .offset(x: cameraService.flashActivado ? 10 : -10)
                    )
                    .animation(.spring(response: 0.3), value: cameraService.flashActivado)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private var statusIndicator: some View {
        HStack(spacing: 20) {
            // Estado de enfoque
            HStack(spacing: 8) {
                Circle()
                    .fill(cameraService.estaEnfocando ? Color.yellow : Color.green)
                    .frame(width: 10, height: 10)
                Text(cameraService.estaEnfocando ? "Enfocando..." : "Enfocado")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)

            // Estado de cámara
            HStack(spacing: 8) {
                Circle()
                    .fill(cameraService.estaListo ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(cameraService.estaListo ? "Cámara lista" : "Iniciando...")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
        }
    }
}

#Preview {
    CameraSettingsView(
        cameraService: CameraService(),
        isPresented: .constant(true)
    )
    .padding()
    .background(Color.black)
}

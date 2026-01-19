//
//  InicioView.swift
//  KYC
//

import SwiftUI

struct InicioView: View {
    let onIniciar: () -> Void

    var body: some View {
        ZStack {
            // Fondo con gradiente sutil
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color.blue.opacity(0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Icono principal con glass
                iconoPrincipal

                // Título y descripción
                VStack(spacing: 12) {
                    Text("Verificación de Identidad")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Vamos a verificar tu identidad comparando tu INE con tu rostro")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                // Pasos con Liquid Glass
                pasosVerificacion
                    .padding(.horizontal, 24)

                Spacer()

                // Botón de iniciar con Liquid Glass
                botonIniciar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Icono Principal

    private var iconoPrincipal: some View {
        ZStack {
            // Círculo de fondo con glass
            Circle()
                .fill(.clear)
                .frame(width: 140, height: 140)
                .glassEffect(.regular.tint(.blue.opacity(0.2)), in: .circle)

            Image(systemName: "person.text.rectangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .blue.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    // MARK: - Pasos de Verificación

    private var pasosVerificacion: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                PasoInfoView(numero: 1, texto: "Fotografía del frente de tu INE", icono: "creditcard.fill")
                PasoInfoView(numero: 2, texto: "Fotografía del reverso de tu INE", icono: "creditcard.fill")
                PasoInfoView(numero: 3, texto: "Dos selfies para verificación", icono: "person.crop.circle.fill")
            }
        }
    }

    // MARK: - Botón Iniciar

    private var botonIniciar: some View {
        Button(action: onIniciar) {
            HStack(spacing: 12) {
                Text("Iniciar Verificación")
                    .font(.headline)
                    .fontWeight(.semibold)

                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .glassEffect(.regular.tint(.blue.opacity(0.6)).interactive(), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct PasoInfoView: View {
    let numero: Int
    let texto: String
    let icono: String

    var body: some View {
        HStack(spacing: 14) {
            // Número con glass
            Text("\(numero)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)
                .glassEffect(.regular.tint(.blue.opacity(0.2)), in: .circle)

            // Icono
            Image(systemName: icono)
                .font(.body)
                .foregroundStyle(.blue.opacity(0.7))

            // Texto
            Text(texto)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    InicioView(onIniciar: {})
}

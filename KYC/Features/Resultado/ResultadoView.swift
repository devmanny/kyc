//
//  ResultadoView.swift
//  KYC
//

import SwiftUI

struct ResultadoView: View {
    let resultado: ResultadoVerificacion?
    let rostroINE: UIImage?
    let selfieCercana: UIImage?
    let selfieLejana: UIImage?
    let onReiniciar: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Indicador de resultado
                resultadoHeader
                    .padding(.top, 20)

                // Fotos comparadas
                fotosComparacion

                // Puntuaciones
                if let resultado = resultado {
                    puntuacionesView(resultado)
                }

                // Datos de la persona
                if let datos = resultado?.datosPersona {
                    datosPersonaView(datos)
                }

                // Botón reiniciar
                botonReiniciar
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Resultado Header

    private var resultadoHeader: some View {
        VStack(spacing: 16) {
            if let resultado = resultado {
                // Icono con glass
                ZStack {
                    Circle()
                        .fill(.clear)
                        .frame(width: 120, height: 120)
                        .glassEffect(
                            .regular.tint((resultado.esCoincidencia ? Color.green : Color.red).opacity(0.3)),
                            in: .circle
                        )

                    Image(systemName: resultado.esCoincidencia ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(resultado.esCoincidencia ? .green : .red)
                }

                Text(resultado.esCoincidencia ? "Verificación Exitosa" : "Verificación Fallida")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(resultado.mensajeResultado)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Badge de confianza con glass
                Text("Confianza: \(resultado.confianza.rawValue)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(colorConfianza(resultado.confianza))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(colorConfianza(resultado.confianza).opacity(0.2)), in: .capsule)
            } else {
                Text("Sin resultado")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Fotos Comparación

    private var fotosComparacion: some View {
        VStack(spacing: 12) {
            Text("Comparación de rostros")
                .font(.headline)

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 12) {
                    fotoView(imagen: rostroINE, etiqueta: "INE")
                    fotoView(imagen: selfieCercana, etiqueta: "Selfie 1")
                    fotoView(imagen: selfieLejana, etiqueta: "Selfie 2")
                }
            }
            .padding(.horizontal)
        }
    }

    private func fotoView(imagen: UIImage?, etiqueta: String) -> some View {
        VStack(spacing: 6) {
            if let imagen = imagen {
                Image(uiImage: imagen)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 12))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.clear)
                        .frame(width: 100, height: 100)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))

                    Image(systemName: "person.fill")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
            Text(etiqueta)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Puntuaciones

    private func puntuacionesView(_ resultado: ResultadoVerificacion) -> some View {
        VStack(spacing: 12) {
            Text("Puntuaciones de similitud")
                .font(.headline)

            VStack(spacing: 10) {
                puntuacionRow(titulo: "INE vs Selfie cercana", valor: resultado.puntuacionINEvsCercana)
                puntuacionRow(titulo: "INE vs Selfie lejana", valor: resultado.puntuacionINEvsLejana)
                puntuacionRow(titulo: "Selfie cercana vs lejana", valor: resultado.puntuacionCercanavsLejana)
            }
            .padding(16)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
    }

    private func puntuacionRow(titulo: String, valor: Float) -> some View {
        HStack {
            Text(titulo)
                .font(.subheadline)
            Spacer()

            // Valor con badge
            Text(String(format: "%.1f%%", valor * 100))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(colorPuntuacion(valor))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassEffect(.regular.tint(colorPuntuacion(valor).opacity(0.2)), in: .capsule)
        }
    }

    // MARK: - Datos Persona

    private func datosPersonaView(_ datos: DatosINEFrente) -> some View {
        VStack(spacing: 12) {
            Text("Datos de la INE")
                .font(.headline)

            VStack(spacing: 10) {
                if let nombre = datos.nombreCompleto {
                    datoRow(titulo: "Nombre", valor: nombre, icono: "person.fill")
                }
                if let curp = datos.curp {
                    datoRow(titulo: "CURP", valor: curp, icono: "number")
                }
                if let clave = datos.claveElector {
                    datoRow(titulo: "Clave Elector", valor: clave, icono: "creditcard.fill")
                }
                if let vigencia = datos.vigencia {
                    datoRow(titulo: "Vigencia", valor: vigencia, icono: "calendar")
                }
            }
            .padding(16)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
    }

    private func datoRow(titulo: String, valor: String, icono: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icono)
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 24)

            Text(titulo)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(valor)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }

    // MARK: - Botón Reiniciar

    private var botonReiniciar: some View {
        Button(action: onReiniciar) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.headline)
                Text("Nueva Verificación")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .glassEffect(.regular.tint(.blue.opacity(0.6)).interactive(), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    private func colorConfianza(_ confianza: NivelConfianza) -> Color {
        switch confianza {
        case .alta: return .green
        case .media: return .orange
        case .baja: return .red
        case .fallida: return .red
        }
    }

    private func colorPuntuacion(_ valor: Float) -> Color {
        if valor > 0.75 { return .green }
        if valor > 0.60 { return .orange }
        return .red
    }
}

#Preview {
    ResultadoView(
        resultado: ResultadoVerificacion(
            esCoincidencia: true,
            confianza: .alta,
            puntuacionINEvsCercana: 0.82,
            puntuacionINEvsLejana: 0.78,
            puntuacionCercanavsLejana: 0.95,
            datosPersona: DatosINEFrente(
                nombreCompleto: "JUAN PEREZ GARCIA",
                curp: "PEGJ850101HDFRRL09"
            ),
            mensajeResultado: "Alta coincidencia con la fotografía de la INE"
        ),
        rostroINE: nil,
        selfieCercana: nil,
        selfieLejana: nil,
        onReiniciar: {}
    )
}

//
//  KYCFlowView.swift
//  KYC
//

import SwiftUI

struct KYCFlowView: View {
    @StateObject private var viewModel = KYCFlowViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.estadoActual {
                case .inicio:
                    InicioView(onIniciar: viewModel.iniciarVerificacion)

                case .capturandoFrenteINE:
                    CapturaINEView(
                        tipo: .frente,
                        onCaptura: viewModel.capturarFrenteINE,
                        onRegresar: viewModel.regresarAInicio
                    )

                case .capturandoReversoINE:
                    CapturaINEView(
                        tipo: .reverso,
                        onCaptura: viewModel.capturarReversoINE,
                        onRegresar: viewModel.regresarAFrenteINE
                    )

                case .procesandoINE:
                    ProcesamientoINEView(
                        documento: viewModel.documentoINE,
                        estaProcesando: viewModel.estaProcesando,
                        mensajeProcesamiento: viewModel.mensajeProcesamiento,
                        onContinuar: viewModel.continuarASelfies,
                        onRegresar: viewModel.regresarAReversoINE,
                        onRepetirFrente: viewModel.repetirFrenteINE,
                        onRepetirReverso: viewModel.repetirReversoINE
                    )

                case .livenessCheck(let challenge):
                    LivenessCheckView(
                        challenge: challenge,
                        onCompletado: viewModel.livenessCompletado,
                        onFallido: viewModel.livenessFallido,
                        onRegresar: viewModel.regresarAProcesamientoINE
                    )

                case .capturandoSelfieCercana:
                    CapturaSelfieView(
                        tipo: .cercana,
                        onCaptura: viewModel.capturarSelfieCercana,
                        onRegresar: viewModel.regresarALiveness
                    )

                case .capturandoSelfieLejana:
                    CapturaSelfieView(
                        tipo: .lejana,
                        onCaptura: viewModel.capturarSelfieLejana,
                        onRegresar: viewModel.regresarASelfieCercana
                    )

                case .verificando:
                    VerificandoView(mensaje: viewModel.mensajeProcesamiento)

                case .resultado:
                    ResultadoView(
                        resultado: viewModel.resultadoVerificacion,
                        rostroINE: viewModel.documentoINE.imagenRostro,
                        selfieCercana: viewModel.selfieCercana.imagenRostro,
                        selfieLejana: viewModel.selfieLejana.imagenRostro,
                        onReiniciar: viewModel.reiniciar
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error", isPresented: .init(
                get: { viewModel.mensajeError != nil },
                set: { if !$0 { viewModel.mensajeError = nil } }
            )) {
                Button("OK") { viewModel.mensajeError = nil }
            } message: {
                Text(viewModel.mensajeError ?? "")
            }
        }
    }
}

// MARK: - Vistas auxiliares

struct ProcesamientoINEView: View {
    let documento: DocumentoINE
    let estaProcesando: Bool
    let mensajeProcesamiento: String
    let onContinuar: () -> Void
    let onRegresar: () -> Void
    let onRepetirFrente: () -> Void
    let onRepetirReverso: () -> Void

    // Estado para diálogos de confirmación
    @State private var mostrarDialogoFrente = false
    @State private var mostrarDialogoReverso = false

    var body: some View {
        VStack(spacing: 24) {
            if estaProcesando {
                Spacer()
                ProgressView(mensajeProcesamiento.isEmpty ? "Procesando INE..." : mensajeProcesamiento)
                    .scaleEffect(1.2)
                Spacer()
            } else {
                Text("INE Capturada")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top, 24)

                // Mostrar imágenes capturadas (tappeables para repetir)
                HStack(spacing: 16) {
                    VStack {
                        if let frente = documento.imagenFrente {
                            Image(uiImage: frente)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 120)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                                )
                                .onTapGesture {
                                    mostrarDialogoFrente = true
                                }
                        }
                        HStack(spacing: 4) {
                            Text("Frente")
                            Image(systemName: "arrow.clockwise")
                                .font(.caption2)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    VStack {
                        if let reverso = documento.imagenReverso {
                            Image(uiImage: reverso)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 120)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                                )
                                .onTapGesture {
                                    mostrarDialogoReverso = true
                                }
                        }
                        HStack(spacing: 4) {
                            Text("Reverso")
                            Image(systemName: "arrow.clockwise")
                                .font(.caption2)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .padding()
                // Hint para el usuario
                Text("Toca una imagen para repetir la captura")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                // Datos extraídos por OCR
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Datos del frente
                        if let datos = documento.datosFrente {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Datos del Frente")
                                    .font(.headline)

                                if let nombre = datos.nombreCompleto {
                                    datosRow("Nombre", nombre)
                                }
                                if let curp = datos.curp {
                                    datosRow("CURP", curp)
                                }
                                if let clave = datos.claveElector {
                                    datosRow("Clave Elector", clave)
                                }
                                if let fecha = datos.fechaNacimiento {
                                    datosRow("Fecha Nac.", fecha)
                                }
                                if let sexo = datos.sexo {
                                    datosRow("Sexo", sexo)
                                }
                                if let estado = datos.estado {
                                    datosRow("Estado", estado)
                                }
                                if let vigencia = datos.vigencia {
                                    datosRow("Vigencia", vigencia)
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        }

                        // Datos del reverso
                        if let datosReverso = documento.datosReverso {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Datos del Reverso")
                                    .font(.headline)

                                if let curp = datosReverso.curp {
                                    datosRow("CURP", curp)
                                }
                                if let clave = datosReverso.claveElector {
                                    datosRow("Clave Elector", clave)
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        }

                        // Validación cruzada
                        if let validacion = documento.validacion {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Validación")
                                    .font(.headline)

                                HStack {
                                    Image(systemName: validacion.esValida ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(validacion.esValida ? .green : .red)
                                    Text(validacion.descripcion)
                                        .font(.subheadline)
                                }
                            }
                            .padding()
                            .background(validacion.esValida ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                            .cornerRadius(12)
                        }

                        // Rostro detectado
                        if let rostro = documento.imagenRostro {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Rostro Detectado")
                                    .font(.headline)

                                Image(uiImage: rostro)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 100)
                                    .cornerRadius(8)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Rostro")
                                    .font(.headline)

                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("No se detectó rostro en la INE")
                                        .font(.subheadline)
                                        .foregroundColor(.orange)
                                }
                            }
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer()

                Button(action: onContinuar) {
                    HStack {
                        Image(systemName: "faceid")
                        Text("Continuar a Verificación de Vida")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(documento.imagenRostro != nil ? Color.blue : Color.gray)
                    .cornerRadius(12)
                }
                .disabled(documento.imagenRostro == nil)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Procesando INE")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !estaProcesando {
                    Button(action: onRegresar) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Atrás")
                        }
                    }
                }
            }
        }
        // Diálogo para repetir frente
        .alert("Repetir Frente", isPresented: $mostrarDialogoFrente) {
            Button("Cancelar", role: .cancel) { }
            Button("Repetir") {
                onRepetirFrente()
            }
        } message: {
            Text("¿Quieres volver a capturar el frente de tu INE?")
        }
        // Diálogo para repetir reverso
        .alert("Repetir Reverso", isPresented: $mostrarDialogoReverso) {
            Button("Cancelar", role: .cancel) { }
            Button("Repetir") {
                onRepetirReverso()
            }
        } message: {
            Text("¿Quieres volver a capturar el reverso de tu INE?")
        }
    }

    private func datosRow(_ titulo: String, _ valor: String) -> some View {
        HStack {
            Text(titulo + ":")
                .foregroundColor(.secondary)
            Text(valor)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

struct VerificandoView: View {
    let mensaje: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Verificando identidad...")
                .font(.headline)
                .foregroundColor(.secondary)
            Text(mensaje.isEmpty ? "Comparando rostros..." : mensaje)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

#Preview {
    KYCFlowView()
}

//
//  KYCFlowViewModel.swift
//  KYC
//

import SwiftUI
import Combine

@MainActor
class KYCFlowViewModel: ObservableObject {
    @Published var estadoActual: EstadoFlujo = .inicio
    @Published var documentoINE = DocumentoINE()
    @Published var selfieCercana = Selfie(tipo: .cercana)
    @Published var selfieLejana = Selfie(tipo: .lejana)
    @Published var resultadoVerificacion: ResultadoVerificacion?
    @Published var mensajeError: String?
    @Published var estaProcesando = false
    @Published var mensajeProcesamiento: String = ""

    // Liveness
    @Published var livenessChallenge: LivenessChallenge = .blink
    @Published var livenessPasado = false
    @Published var livenessInstruccion: String = ""
    @Published var livenessProgreso: Float = 0

    // Servicios
    private let ocrService = OCRService()
    private let faceDetectionService = FaceDetectionService()
    private let faceEmbeddingService = FaceEmbeddingService()
    private let livenessService = LivenessDetectionService()

    // MARK: - Navegación del flujo

    func iniciarVerificacion() {
        resetear()
        estadoActual = .capturandoFrenteINE
    }

    // MARK: - Navegación hacia atrás

    func regresarAInicio() {
        resetear()
        estadoActual = .inicio
    }

    func regresarAFrenteINE() {
        documentoINE.imagenFrente = nil
        estadoActual = .capturandoFrenteINE
    }

    func regresarAReversoINE() {
        documentoINE.imagenReverso = nil
        documentoINE.datosFrente = nil
        documentoINE.datosReverso = nil
        documentoINE.validacion = nil
        documentoINE.imagenRostro = nil
        estadoActual = .capturandoReversoINE
    }

    func regresarAProcesamientoINE() {
        livenessPasado = false
        estadoActual = .procesandoINE
    }

    func regresarALiveness() {
        selfieCercana = Selfie(tipo: .cercana)
        estadoActual = .livenessCheck(livenessChallenge)
    }

    func regresarASelfieCercana() {
        selfieLejana = Selfie(tipo: .lejana)
        selfieLejana.livenessVerificado = livenessPasado
        estadoActual = .capturandoSelfieCercana
    }

    func capturarFrenteINE(_ imagen: UIImage) {
        documentoINE.imagenFrente = imagen
        estadoActual = .capturandoReversoINE
    }

    func capturarReversoINE(_ imagen: UIImage) {
        documentoINE.imagenReverso = imagen
        estadoActual = .procesandoINE
        procesarINE()
    }

    func continuarASelfies() {
        // Iniciar con liveness check antes de las selfies
        iniciarLivenessCheck()
    }

    func iniciarLivenessCheck() {
        // Seleccionar un challenge aleatorio
        let challenges: [LivenessChallenge] = [.blink, .smile]
        livenessChallenge = challenges.randomElement() ?? .blink
        livenessPasado = false
        livenessProgreso = 0
        estadoActual = .livenessCheck(livenessChallenge)
    }

    func livenessCompletado() {
        livenessPasado = true
        selfieCercana.livenessVerificado = true
        selfieLejana.livenessVerificado = true
        estadoActual = .capturandoSelfieCercana
    }

    func livenessFallido(_ mensaje: String) {
        mensajeError = mensaje
        // Permitir reintentar
        iniciarLivenessCheck()
    }

    func capturarSelfieCercana(_ imagen: UIImage) {
        selfieCercana.imagen = imagen
        selfieCercana.timestamp = Date()
        estadoActual = .capturandoSelfieLejana
    }

    func capturarSelfieLejana(_ imagen: UIImage) {
        selfieLejana.imagen = imagen
        selfieLejana.timestamp = Date()
        estadoActual = .verificando
        verificarIdentidad()
    }

    func reiniciar() {
        resetear()
        estadoActual = .inicio
    }

    // MARK: - Procesamiento de INE

    private func procesarINE() {
        estaProcesando = true
        mensajeProcesamiento = "Detectando documento..."

        Task {
            do {
                // 0. Detectar y recortar el documento de las imágenes capturadas
                // Esto elimina el fondo y deja solo la tarjeta INE
                var imagenFrenteProcesada: UIImage?
                var imagenReversoProcesada: UIImage?

                if let imagenFrente = documentoINE.imagenFrente {
                    mensajeProcesamiento = "Detectando tarjeta INE (frente)..."
                    if let documentoRecortado = try await faceDetectionService.detectarYRecortarDocumento(en: imagenFrente) {
                        imagenFrenteProcesada = documentoRecortado
                        // Actualizar la imagen almacenada con la versión recortada
                        documentoINE.imagenFrente = documentoRecortado
                        print("ViewModel: Documento frente recortado - \(documentoRecortado.size)")
                    } else {
                        imagenFrenteProcesada = imagenFrente
                        print("ViewModel: No se detectó documento en frente, usando imagen original")
                    }
                }

                if let imagenReverso = documentoINE.imagenReverso {
                    mensajeProcesamiento = "Detectando tarjeta INE (reverso)..."
                    if let documentoRecortado = try await faceDetectionService.detectarYRecortarDocumento(en: imagenReverso) {
                        imagenReversoProcesada = documentoRecortado
                        // Actualizar la imagen almacenada con la versión recortada
                        documentoINE.imagenReverso = documentoRecortado
                        print("ViewModel: Documento reverso recortado - \(documentoRecortado.size)")
                    } else {
                        imagenReversoProcesada = imagenReverso
                        print("ViewModel: No se detectó documento en reverso, usando imagen original")
                    }
                }

                // 1. OCR del frente (usando imagen recortada)
                if let imagenFrente = imagenFrenteProcesada {
                    mensajeProcesamiento = "Analizando frente de INE..."
                    let datosFrente = try await ocrService.extraerDatosFrente(de: imagenFrente)
                    documentoINE.datosFrente = datosFrente
                }

                // 2. OCR del reverso (usando imagen recortada)
                if let imagenReverso = imagenReversoProcesada {
                    mensajeProcesamiento = "Analizando reverso de INE..."
                    let datosReverso = try await ocrService.extraerDatosReverso(de: imagenReverso)
                    documentoINE.datosReverso = datosReverso
                }

                // 3. Validar datos cruzados
                if let frente = documentoINE.datosFrente,
                   let reverso = documentoINE.datosReverso {
                    mensajeProcesamiento = "Validando datos..."
                    let validacion = ValidacionService.compararDatosINE(frente: frente, reverso: reverso)
                    documentoINE.validacion = validacion
                }

                // 4. Detectar y recortar rostro de la INE (usando imagen ya recortada del documento)
                if let imagenFrente = imagenFrenteProcesada {
                    mensajeProcesamiento = "Detectando rostro en INE..."
                    if let rostro = try await faceDetectionService.detectarYRecortarRostroDeINE(de: imagenFrente) {
                        documentoINE.imagenRostro = rostro
                        print("ViewModel: Rostro de INE detectado correctamente")
                    } else {
                        // NO usar fallback - si no hay rostro, no continuar
                        print("ViewModel: ERROR - No se detectó rostro en la INE")
                        mensajeError = "No se detectó el rostro en la fotografía de la INE. Por favor, vuelve a capturar el frente de la INE con mejor iluminación y enfoque."
                        documentoINE.imagenRostro = nil
                    }
                }

                estaProcesando = false

            } catch {
                mensajeError = "Error al procesar INE: \(error.localizedDescription)"
                estaProcesando = false
            }
        }
    }

    // MARK: - Verificación de identidad

    private func verificarIdentidad() {
        estaProcesando = true
        mensajeProcesamiento = "Preparando verificación..."

        Task {
            do {
                // 1. Detectar y recortar rostro de selfie cercana
                mensajeProcesamiento = "Procesando selfie cercana..."
                if let imagenCercana = selfieCercana.imagen {
                    if let rostroCercana = try await faceDetectionService.detectarYRecortarRostro(de: imagenCercana) {
                        selfieCercana.imagenRostro = rostroCercana
                    } else {
                        throw VerificacionError.sinRostroEnSelfie("No se detectó rostro en la selfie cercana")
                    }
                }

                // 2. Detectar y recortar rostro de selfie lejana
                mensajeProcesamiento = "Procesando selfie lejana..."
                if let imagenLejana = selfieLejana.imagen {
                    if let rostroLejana = try await faceDetectionService.detectarYRecortarRostro(de: imagenLejana) {
                        selfieLejana.imagenRostro = rostroLejana
                    } else {
                        throw VerificacionError.sinRostroEnSelfie("No se detectó rostro en la selfie lejana")
                    }
                }

                // 3. Verificar que tenemos rostro de la INE
                guard let rostroINE = documentoINE.imagenRostro else {
                    throw VerificacionError.sinRostroEnINE
                }

                guard let rostroCercana = selfieCercana.imagenRostro,
                      let rostroLejana = selfieLejana.imagenRostro else {
                    throw VerificacionError.sinRostroEnSelfie("Faltan rostros de selfies")
                }

                // 4. Comparar rostros
                mensajeProcesamiento = "Comparando rostros..."
                let resultado = try await faceEmbeddingService.verificarIdentidad(
                    rostroINE: rostroINE,
                    selfieCercana: rostroCercana,
                    selfieLejana: rostroLejana,
                    datosPersona: documentoINE.datosFrente
                )

                resultadoVerificacion = resultado
                estadoActual = .resultado
                estaProcesando = false

            } catch {
                mensajeError = "Error en verificación: \(error.localizedDescription)"
                estaProcesando = false

                // Crear resultado fallido
                resultadoVerificacion = ResultadoVerificacion(
                    esCoincidencia: false,
                    confianza: .fallida,
                    puntuacionINEvsCercana: 0,
                    puntuacionINEvsLejana: 0,
                    puntuacionCercanavsLejana: 0,
                    datosPersona: documentoINE.datosFrente,
                    mensajeResultado: "Error: \(error.localizedDescription)"
                )
                estadoActual = .resultado
            }
        }
    }

    private func resetear() {
        documentoINE = DocumentoINE()
        selfieCercana = Selfie(tipo: .cercana)
        selfieLejana = Selfie(tipo: .lejana)
        resultadoVerificacion = nil
        mensajeError = nil
        estaProcesando = false
        mensajeProcesamiento = ""
        livenessPasado = false
        livenessProgreso = 0
    }
}

// MARK: - Errores

enum VerificacionError: LocalizedError {
    case sinRostroEnINE
    case sinRostroEnSelfie(String)
    case errorComparacion(String)
    case livenessFallido(String)

    var errorDescription: String? {
        switch self {
        case .sinRostroEnINE:
            return "No se detectó rostro en la fotografía de la INE"
        case .sinRostroEnSelfie(let mensaje):
            return mensaje
        case .errorComparacion(let mensaje):
            return mensaje
        case .livenessFallido(let mensaje):
            return "Verificación de vida fallida: \(mensaje)"
        }
    }
}

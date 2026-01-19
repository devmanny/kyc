//
//  LivenessDetectionService.swift
//  KYC
//
//  Servicio de detección de vida (anti-spoofing)
//  Detecta si la persona frente a la cámara es real y no una foto/video
//

import Vision
import UIKit
import AVFoundation

// MARK: - Liveness Challenge Types

enum LivenessChallenge: CaseIterable, Equatable, Sendable {
    case blink          // Parpadear
    case turnLeft       // Girar cabeza a la izquierda
    case turnRight      // Girar cabeza a la derecha
    case smile          // Sonreír

    var instruccion: String {
        switch self {
        case .blink: return "Parpadea"
        case .turnLeft: return "Gira tu cabeza hacia la izquierda"
        case .turnRight: return "Gira tu cabeza hacia la derecha"
        case .smile: return "Sonríe"
        }
    }

    var icono: String {
        switch self {
        case .blink: return "eye"
        case .turnLeft: return "arrow.left"
        case .turnRight: return "arrow.right"
        case .smile: return "face.smiling"
        }
    }
}

// MARK: - Liveness Result

struct LivenessResult {
    let isAlive: Bool
    let confidence: Float
    let completedChallenges: [LivenessChallenge]
    let failureReason: String?

    static let passed = LivenessResult(isAlive: true, confidence: 1.0, completedChallenges: [], failureReason: nil)
    static func failed(_ reason: String) -> LivenessResult {
        LivenessResult(isAlive: false, confidence: 0, completedChallenges: [], failureReason: reason)
    }
}

// MARK: - Face State for Tracking

struct FaceState {
    var leftEyeOpenness: Float = 1.0    // 0 = cerrado, 1 = abierto
    var rightEyeOpenness: Float = 1.0
    var yaw: Float = 0                   // Rotación horizontal (-1 izq, 0 centro, 1 der)
    var pitch: Float = 0                 // Rotación vertical
    var roll: Float = 0                  // Inclinación
    var smileAmount: Float = 0           // 0 = neutral, 1 = sonrisa completa
    var mouthOpenness: Float = 0         // Para detectar boca abierta
    var timestamp: Date = Date()

    // Umbrales ajustados para detección confiable
    var isBlinking: Bool {
        // Con la nueva normalización: 0 = cerrado, 1 = abierto
        // Detectar parpadeo cuando openness < 0.3 en ambos ojos
        leftEyeOpenness < 0.3 && rightEyeOpenness < 0.3
    }

    var isTurnedLeft: Bool {
        yaw < -0.2  // Más permisivo (Vision reporta yaw en radianes)
    }

    var isTurnedRight: Bool {
        yaw > 0.2
    }

    var isSmiling: Bool {
        // Con la nueva normalización basada en curvatura de comisuras
        smileAmount > 0.3
    }
}

// MARK: - Liveness Detection Service

actor LivenessDetectionService {

    // Estado de detección
    private var faceStates: [FaceState] = []
    private var blinkCount = 0
    private var hasLookedLeft = false
    private var hasLookedRight = false
    private var hasSmiled = false
    private var lastBlinkTime: Date?

    // Configuración - valores más permisivos
    private let requiredBlinks = 1  // Solo 1 parpadeo requerido
    private let minTimeBetweenBlinks: TimeInterval = 0.2
    private let maxChallengeTime: TimeInterval = 15.0

    // MARK: - Reset

    func reset() {
        faceStates.removeAll()
        blinkCount = 0
        hasLookedLeft = false
        hasLookedRight = false
        hasSmiled = false
        lastBlinkTime = nil
    }

    // MARK: - Process Frame

    /// Procesa un frame de video y extrae el estado facial
    func processFrame(_ image: UIImage) async throws -> FaceState {
        guard let cgImage = image.cgImage else {
            throw LivenessError.imagenInvalida
        }

        let request = VNDetectFaceLandmarksRequest()

        // Convertir la orientación de UIImage a CGImagePropertyOrientation
        let cgOrientation = cgImageOrientation(from: image.imageOrientation)
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgOrientation, options: [:])

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try handler.perform([request])

                guard let results = request.results, let face = results.first else {
                    continuation.resume(throwing: LivenessError.sinRostro)
                    return
                }

                let state = self.extractFaceState(from: face)
                self.faceStates.append(state)

                // Mantener solo los últimos 30 estados (1 segundo a 30fps)
                if self.faceStates.count > 30 {
                    self.faceStates.removeFirst()
                }

                self.updateChallengeProgress(state)
                continuation.resume(returning: state)
            } catch {
                continuation.resume(throwing: LivenessError.errorProcesamiento(error))
            }
        }
    }

    // MARK: - Extract Face State

    private func extractFaceState(from face: VNFaceObservation) -> FaceState {
        var state = FaceState()

        // Rotación de la cabeza (yaw, pitch, roll)
        if let yaw = face.yaw?.floatValue {
            state.yaw = yaw
        }
        if let pitch = face.pitch?.floatValue {
            state.pitch = pitch
        }
        if let roll = face.roll?.floatValue {
            state.roll = roll
        }

        // Detectar apertura de ojos usando landmarks
        if let landmarks = face.landmarks {
            state.leftEyeOpenness = calculateEyeOpenness(landmarks.leftEye)
            state.rightEyeOpenness = calculateEyeOpenness(landmarks.rightEye)
            state.smileAmount = calculateSmileAmount(landmarks)
        }

        return state
    }

    private func calculateEyeOpenness(_ eye: VNFaceLandmarkRegion2D?) -> Float {
        guard let eye = eye else { return 1.0 }
        let points = eye.normalizedPoints

        // Vision típicamente devuelve 6-8 puntos por ojo
        // Estrategia: calcular la altura vertical promedio del ojo
        // excluyendo los puntos de las esquinas (que no se mueven mucho al parpadear)
        guard points.count >= 6 else { return 1.0 }

        // Ordenar puntos por X para identificar las esquinas
        let sortedByX = points.sorted { $0.x < $1.x }

        // Excluir el punto más a la izquierda y más a la derecha (esquinas)
        let middlePoints = Array(sortedByX.dropFirst().dropLast())
        guard middlePoints.count >= 2 else { return 1.0 }

        // Separar puntos superiores e inferiores
        let avgY = middlePoints.map { $0.y }.reduce(0, +) / CGFloat(middlePoints.count)
        let topPoints = middlePoints.filter { $0.y > avgY }
        let bottomPoints = middlePoints.filter { $0.y <= avgY }

        guard !topPoints.isEmpty && !bottomPoints.isEmpty else { return 1.0 }

        // Calcular la altura vertical promedio entre párpado superior e inferior
        let topAvgY = topPoints.map { $0.y }.reduce(0, +) / CGFloat(topPoints.count)
        let bottomAvgY = bottomPoints.map { $0.y }.reduce(0, +) / CGFloat(bottomPoints.count)
        let verticalDistance = topAvgY - bottomAvgY

        // El ancho del ojo para normalizar
        let width = (sortedByX.last?.x ?? 0) - (sortedByX.first?.x ?? 0)
        guard width > 0 else { return 1.0 }

        // EAR = distancia vertical / ancho
        // Ojo abierto: EAR ~0.2-0.35
        // Ojo cerrado: EAR < 0.15
        let ear = verticalDistance / width

        // Debug
        print("LivenessDetection: EAR=\(ear) (distance=\(verticalDistance), width=\(width))")

        // Normalizar: EAR < 0.12 = cerrado (0), EAR > 0.25 = abierto (1)
        let normalized = (ear - 0.12) / 0.13
        return Float(min(1.0, max(0, normalized)))
    }

    private func calculateSmileAmount(_ landmarks: VNFaceLandmarks2D) -> Float {
        guard let outerLips = landmarks.outerLips else { return 0 }
        let lipPoints = outerLips.normalizedPoints
        guard lipPoints.count >= 6 else { return 0 }

        // Ordenar puntos por X para encontrar las comisuras (izquierda y derecha)
        let sortedByX = lipPoints.sorted { $0.x < $1.x }
        let leftCorner = sortedByX.first!
        let rightCorner = sortedByX.last!

        // Encontrar el punto más bajo de la boca (centro inferior del labio)
        let bottomPoint = lipPoints.min(by: { $0.y < $1.y })!

        // Métrica de sonrisa: qué tan elevadas están las comisuras respecto al centro inferior
        // Al sonreír, las comisuras suben significativamente
        let cornerAvgY = (leftCorner.y + rightCorner.y) / 2
        let cornerElevation = cornerAvgY - bottomPoint.y

        // También medir el ancho de la boca (sonrisas son más anchas)
        let mouthWidth = rightCorner.x - leftCorner.x

        // Calcular el ratio de "curvatura" de la sonrisa
        // Una sonrisa tiene comisuras elevadas Y boca ancha
        // Normalizar la elevación por el ancho para ser independiente del tamaño de la cara
        guard mouthWidth > 0 else { return 0 }

        let smileCurvature = cornerElevation / mouthWidth

        // Debug
        print("LivenessDetection: SmileCurvature=\(smileCurvature) (elevation=\(cornerElevation), width=\(mouthWidth))")

        // Sonrisa neutral: curvature ~0.1-0.2
        // Sonrisa amplia: curvature ~0.3-0.4+
        // Normalizar: 0.15 = 0 (neutral), 0.35 = 1 (sonrisa)
        let normalized = (smileCurvature - 0.15) / 0.20
        return Float(min(1.0, max(0, normalized)))
    }

    // MARK: - Update Challenge Progress

    private func updateChallengeProgress(_ state: FaceState) {
        // Detectar parpadeo
        if state.isBlinking {
            if let lastBlink = lastBlinkTime {
                if state.timestamp.timeIntervalSince(lastBlink) > minTimeBetweenBlinks {
                    blinkCount += 1
                    lastBlinkTime = state.timestamp
                }
            } else {
                blinkCount += 1
                lastBlinkTime = state.timestamp
            }
        }

        // Detectar giro a la izquierda
        if state.isTurnedLeft {
            hasLookedLeft = true
        }

        // Detectar giro a la derecha
        if state.isTurnedRight {
            hasLookedRight = true
        }

        // Detectar sonrisa
        if state.isSmiling {
            hasSmiled = true
        }
    }

    // MARK: - Check Challenge Completion

    func checkChallenge(_ challenge: LivenessChallenge) -> Bool {
        switch challenge {
        case .blink:
            return blinkCount >= requiredBlinks
        case .turnLeft:
            return hasLookedLeft
        case .turnRight:
            return hasLookedRight
        case .smile:
            return hasSmiled
        }
    }

    // MARK: - Run Liveness Check

    /// Ejecuta una verificación de vida con un challenge específico
    func runLivenessCheck(
        challenge: LivenessChallenge,
        imageProvider: @escaping () async -> UIImage?,
        timeout: TimeInterval = 10.0
    ) async -> LivenessResult {
        reset()

        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            guard let image = await imageProvider() else {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                continue
            }

            do {
                let _ = try await processFrame(image)

                if checkChallenge(challenge) {
                    return LivenessResult(
                        isAlive: true,
                        confidence: 0.9,
                        completedChallenges: [challenge],
                        failureReason: nil
                    )
                }
            } catch {
                print("LivenessDetection: Error procesando frame - \(error)")
            }

            try? await Task.sleep(nanoseconds: 33_000_000) // ~30fps
        }

        return LivenessResult.failed("No se completó el desafío de '\(challenge.instruccion)' a tiempo")
    }

    // MARK: - Quick Liveness Check (Passive)

    /// Verificación pasiva de vida analizando movimiento natural
    func quickLivenessCheck(frames: [UIImage]) async -> LivenessResult {
        guard frames.count >= 5 else {
            return LivenessResult.failed("Insuficientes frames para análisis")
        }

        reset()

        // Procesar todos los frames
        var validStates: [FaceState] = []
        for frame in frames {
            do {
                let state = try await processFrame(frame)
                validStates.append(state)
            } catch {
                continue
            }
        }

        guard validStates.count >= 3 else {
            return LivenessResult.failed("No se detectó rostro en suficientes frames")
        }

        // Verificar que hay variación natural (no es una foto estática)
        let yawVariance = calculateVariance(validStates.map { CGFloat($0.yaw) })
        let pitchVariance = calculateVariance(validStates.map { CGFloat($0.pitch) })
        let eyeVariance = calculateVariance(validStates.map { CGFloat($0.leftEyeOpenness) })

        let totalVariance = yawVariance + pitchVariance + eyeVariance

        // Una persona real tiene micro-movimientos naturales
        // Una foto tiene varianza ~0
        let isNaturalMovement = totalVariance > 0.001

        if isNaturalMovement {
            return LivenessResult(
                isAlive: true,
                confidence: min(1.0, Float(totalVariance * 100)),
                completedChallenges: [],
                failureReason: nil
            )
        } else {
            return LivenessResult.failed("No se detectó movimiento natural - posible foto o video")
        }
    }

    private func calculateVariance(_ values: [CGFloat]) -> CGFloat {
        guard values.count > 1 else { return 0 }

        let mean = values.reduce(0, +) / CGFloat(values.count)
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        return squaredDiffs.reduce(0, +) / CGFloat(values.count)
    }

    /// Convierte UIImage.Orientation a CGImagePropertyOrientation para Vision
    private func cgImageOrientation(from uiOrientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch uiOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

// MARK: - Errors

enum LivenessError: LocalizedError {
    case imagenInvalida
    case sinRostro
    case errorProcesamiento(Error)
    case timeout

    var errorDescription: String? {
        switch self {
        case .imagenInvalida:
            return "La imagen no es válida"
        case .sinRostro:
            return "No se detectó rostro en la imagen"
        case .errorProcesamiento(let error):
            return "Error al procesar: \(error.localizedDescription)"
        case .timeout:
            return "Se agotó el tiempo para completar la verificación"
        }
    }
}

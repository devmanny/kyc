//
//  FaceEmbeddingService.swift
//  KYC
//
//  Servicio de comparación facial
//  Usa ArcFace (Core ML) como método primario para máxima precisión
//  Fallback a landmarks geométricos si el modelo no está disponible
//

import Vision
import UIKit
import Accelerate

actor FaceEmbeddingService {

    // MARK: - ArcFace Service

    /// Servicio ArcFace para comparación de alta precisión
    private let arcFaceService = ArcFaceService()

    // MARK: - Tipos

    /// Embedding facial basado en landmarks normalizados
    struct FacialEmbedding: Sendable {
        let landmarks: [String: CGPoint]      // Landmarks normalizados
        let proportions: [String: CGFloat]    // Proporciones faciales
        let angles: [String: CGFloat]         // Ángulos entre landmarks

        /// Calcula la similitud con otro embedding (0.0 a 1.0)
        func similitud(con otro: FacialEmbedding) -> Float {
            var scores: [Float] = []

            // 1. Comparar proporciones faciales (40% del peso)
            let proporcionScore = compararDiccionarios(proportions, otro.proportions)
            scores.append(proporcionScore * 0.4)

            // 2. Comparar ángulos faciales (30% del peso)
            let anguloScore = compararDiccionarios(angles, otro.angles)
            scores.append(anguloScore * 0.3)

            // 3. Comparar posiciones relativas de landmarks (30% del peso)
            let landmarkScore = compararLandmarks(landmarks, otro.landmarks)
            scores.append(landmarkScore * 0.3)

            return scores.reduce(0, +)
        }

        private func compararDiccionarios(_ d1: [String: CGFloat], _ d2: [String: CGFloat]) -> Float {
            var totalDiff: CGFloat = 0
            var count: CGFloat = 0

            for (key, value1) in d1 {
                if let value2 = d2[key] {
                    let maxVal = max(abs(value1), abs(value2), 0.001)
                    let diff = abs(value1 - value2) / maxVal
                    totalDiff += min(diff, 1.0)
                    count += 1
                }
            }

            guard count > 0 else { return 0 }
            let avgDiff = totalDiff / count
            return Float(max(0, 1.0 - avgDiff))
        }

        private func compararLandmarks(_ l1: [String: CGPoint], _ l2: [String: CGPoint]) -> Float {
            var totalDist: CGFloat = 0
            var count: CGFloat = 0

            for (key, point1) in l1 {
                if let point2 = l2[key] {
                    let dist = hypot(point1.x - point2.x, point1.y - point2.y)
                    totalDist += min(dist, 0.5) // Cap at 0.5 para outliers
                    count += 1
                }
            }

            guard count > 0 else { return 0 }
            let avgDist = totalDist / count
            // Distancia promedio de 0.0 = 1.0 similitud, 0.2+ = 0.0 similitud
            return Float(max(0, 1.0 - (avgDist / 0.2)))
        }
    }

    // MARK: - Extracción de Embedding

    /// Genera un embedding facial basado en landmarks biométricos
    func generarEmbedding(de imagen: UIImage) async throws -> FacialEmbedding {
        guard let cgImage = imagen.cgImage else {
            throw EmbeddingError.imagenInvalida
        }

        let request = VNDetectFaceLandmarksRequest()
        // IMPORTANTE: Usar la orientación correcta de la imagen para que Vision detecte rostros
        let cgOrientation = cgImageOrientation(from: imagen.imageOrientation)
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgOrientation, options: [:])

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try handler.perform([request])

                guard let results = request.results, let face = results.first else {
                    continuation.resume(throwing: EmbeddingError.sinRostro)
                    return
                }

                guard let landmarks = face.landmarks else {
                    continuation.resume(throwing: EmbeddingError.sinLandmarks)
                    return
                }

                let embedding = self.extraerEmbedding(de: landmarks, boundingBox: face.boundingBox)
                continuation.resume(returning: embedding)
            } catch {
                continuation.resume(throwing: EmbeddingError.errorProcesamiento(error))
            }
        }
    }

    /// Extrae características biométricas de los landmarks
    private func extraerEmbedding(de landmarks: VNFaceLandmarks2D, boundingBox: CGRect) -> FacialEmbedding {
        var landmarkPoints: [String: CGPoint] = [:]
        var proportions: [String: CGFloat] = [:]
        var angles: [String: CGFloat] = [:]

        // Extraer puntos clave y normalizarlos al bounding box
        if let leftEye = landmarks.leftEye {
            landmarkPoints["leftEyeCenter"] = centroide(de: leftEye, en: boundingBox)
        }
        if let rightEye = landmarks.rightEye {
            landmarkPoints["rightEyeCenter"] = centroide(de: rightEye, en: boundingBox)
        }
        if let nose = landmarks.nose {
            landmarkPoints["noseCenter"] = centroide(de: nose, en: boundingBox)
            if let points = nose.normalizedPoints.first {
                landmarkPoints["noseTip"] = normalizar(points, en: boundingBox)
            }
        }
        if let noseCrest = landmarks.noseCrest {
            landmarkPoints["noseCrest"] = centroide(de: noseCrest, en: boundingBox)
        }
        if let outerLips = landmarks.outerLips {
            landmarkPoints["mouthCenter"] = centroide(de: outerLips, en: boundingBox)
            let points = outerLips.normalizedPoints
            if points.count >= 2 {
                landmarkPoints["mouthLeft"] = normalizar(points[0], en: boundingBox)
                landmarkPoints["mouthRight"] = normalizar(points[points.count / 2], en: boundingBox)
            }
        }
        if let leftEyebrow = landmarks.leftEyebrow {
            landmarkPoints["leftEyebrowCenter"] = centroide(de: leftEyebrow, en: boundingBox)
        }
        if let rightEyebrow = landmarks.rightEyebrow {
            landmarkPoints["rightEyebrowCenter"] = centroide(de: rightEyebrow, en: boundingBox)
        }
        if let faceContour = landmarks.faceContour {
            let points = faceContour.normalizedPoints
            if points.count >= 3 {
                landmarkPoints["chin"] = normalizar(points[points.count / 2], en: boundingBox)
                landmarkPoints["jawLeft"] = normalizar(points[0], en: boundingBox)
                landmarkPoints["jawRight"] = normalizar(points[points.count - 1], en: boundingBox)
            }
        }

        // Calcular proporciones faciales biométricas
        if let leftEye = landmarkPoints["leftEyeCenter"],
           let rightEye = landmarkPoints["rightEyeCenter"] {
            let interocularDist = hypot(rightEye.x - leftEye.x, rightEye.y - leftEye.y)
            proportions["interocularDistance"] = interocularDist

            if let noseCenter = landmarkPoints["noseCenter"] {
                let leftEyeToNose = hypot(noseCenter.x - leftEye.x, noseCenter.y - leftEye.y)
                let rightEyeToNose = hypot(noseCenter.x - rightEye.x, noseCenter.y - rightEye.y)
                proportions["leftEyeToNoseRatio"] = leftEyeToNose / max(interocularDist, 0.001)
                proportions["rightEyeToNoseRatio"] = rightEyeToNose / max(interocularDist, 0.001)
                proportions["eyeNoseSymmetry"] = min(leftEyeToNose, rightEyeToNose) / max(leftEyeToNose, rightEyeToNose, 0.001)
            }

            if let mouth = landmarkPoints["mouthCenter"] {
                let eyeMidpoint = CGPoint(x: (leftEye.x + rightEye.x) / 2, y: (leftEye.y + rightEye.y) / 2)
                let eyeToMouth = hypot(mouth.x - eyeMidpoint.x, mouth.y - eyeMidpoint.y)
                proportions["eyeToMouthRatio"] = eyeToMouth / max(interocularDist, 0.001)
            }

            if let chin = landmarkPoints["chin"] {
                let eyeMidpoint = CGPoint(x: (leftEye.x + rightEye.x) / 2, y: (leftEye.y + rightEye.y) / 2)
                let faceHeight = hypot(chin.x - eyeMidpoint.x, chin.y - eyeMidpoint.y)
                proportions["faceHeightRatio"] = faceHeight / max(interocularDist, 0.001)
            }

            if let mouthLeft = landmarkPoints["mouthLeft"],
               let mouthRight = landmarkPoints["mouthRight"] {
                let mouthWidth = hypot(mouthRight.x - mouthLeft.x, mouthRight.y - mouthLeft.y)
                proportions["mouthWidthRatio"] = mouthWidth / max(interocularDist, 0.001)
            }

            if let jawLeft = landmarkPoints["jawLeft"],
               let jawRight = landmarkPoints["jawRight"] {
                let jawWidth = hypot(jawRight.x - jawLeft.x, jawRight.y - jawLeft.y)
                proportions["jawWidthRatio"] = jawWidth / max(interocularDist, 0.001)
            }
        }

        // Calcular ángulos faciales
        if let leftEye = landmarkPoints["leftEyeCenter"],
           let rightEye = landmarkPoints["rightEyeCenter"],
           let nose = landmarkPoints["noseCenter"] {
            // Ángulo del triángulo ojos-nariz
            angles["eyeNoseAngle"] = anguloEntre(leftEye, nose, rightEye)
        }

        if let leftEye = landmarkPoints["leftEyeCenter"],
           let rightEye = landmarkPoints["rightEyeCenter"],
           let mouth = landmarkPoints["mouthCenter"] {
            // Ángulo del triángulo ojos-boca
            angles["eyeMouthAngle"] = anguloEntre(leftEye, mouth, rightEye)
        }

        if let nose = landmarkPoints["noseCenter"],
           let mouth = landmarkPoints["mouthCenter"],
           let chin = landmarkPoints["chin"] {
            // Ángulo nariz-boca-mentón
            angles["noseMouthChinAngle"] = anguloEntre(nose, mouth, chin)
        }

        return FacialEmbedding(landmarks: landmarkPoints, proportions: proportions, angles: angles)
    }

    // MARK: - Helpers Geométricos

    private func centroide(de region: VNFaceLandmarkRegion2D, en boundingBox: CGRect) -> CGPoint {
        let points = region.normalizedPoints
        guard !points.isEmpty else { return .zero }

        let sumX = points.reduce(0) { $0 + $1.x }
        let sumY = points.reduce(0) { $0 + $1.y }
        let center = CGPoint(x: sumX / CGFloat(points.count), y: sumY / CGFloat(points.count))

        return normalizar(center, en: boundingBox)
    }

    private func normalizar(_ point: CGPoint, en boundingBox: CGRect) -> CGPoint {
        // Normalizar al bounding box del rostro para invarianza de posición/escala
        return CGPoint(
            x: (point.x - boundingBox.origin.x) / boundingBox.width,
            y: (point.y - boundingBox.origin.y) / boundingBox.height
        )
    }

    private func anguloEntre(_ p1: CGPoint, _ vertex: CGPoint, _ p2: CGPoint) -> CGFloat {
        let v1 = CGPoint(x: p1.x - vertex.x, y: p1.y - vertex.y)
        let v2 = CGPoint(x: p2.x - vertex.x, y: p2.y - vertex.y)

        let dot = v1.x * v2.x + v1.y * v2.y
        let cross = v1.x * v2.y - v1.y * v2.x

        return atan2(cross, dot)
    }

    // MARK: - Comparación de Rostros

    /// Compara dos imágenes de rostros y retorna similitud entre 0.0 y 1.0
    /// Usa ArcFace (deep learning) si está disponible, landmarks como fallback
    func compararRostros(_ imagen1: UIImage, _ imagen2: UIImage) async throws -> Float {
        // Intentar usar ArcFace primero (mucho más preciso)
        if await arcFaceService.modeloDisponible {
            do {
                let similitud = try await arcFaceService.compararRostros(imagen1, imagen2)
                print("FaceEmbedding: Usando ArcFace - similitud: \(String(format: "%.2f", similitud * 100))%")
                return similitud
            } catch {
                print("FaceEmbedding: Error en ArcFace, usando fallback - \(error.localizedDescription)")
            }
        }

        // Fallback a landmarks geométricos
        print("FaceEmbedding: Usando landmarks geométricos (fallback)")
        let embedding1 = try await generarEmbedding(de: imagen1)
        let embedding2 = try await generarEmbedding(de: imagen2)
        return embedding1.similitud(con: embedding2)
    }

    // MARK: - Verificación Completa

    func verificarIdentidad(
        rostroINE: UIImage,
        selfieCercana: UIImage,
        selfieLejana: UIImage,
        datosPersona: DatosINEFrente?
    ) async throws -> ResultadoVerificacion {

        // Verificar si ArcFace está disponible
        let usandoArcFace = await arcFaceService.modeloDisponible

        if usandoArcFace {
            print("FaceEmbedding: ✓ Usando ArcFace (deep learning) para verificación de alta precisión")
            return try await verificarConArcFace(
                rostroINE: rostroINE,
                selfieCercana: selfieCercana,
                selfieLejana: selfieLejana,
                datosPersona: datosPersona
            )
        } else {
            print("FaceEmbedding: ⚠️ ArcFace no disponible, usando landmarks geométricos (menos preciso)")
            return try await verificarConLandmarks(
                rostroINE: rostroINE,
                selfieCercana: selfieCercana,
                selfieLejana: selfieLejana,
                datosPersona: datosPersona
            )
        }
    }

    /// Verificación usando ArcFace (deep learning) - Alta precisión
    private func verificarConArcFace(
        rostroINE: UIImage,
        selfieCercana: UIImage,
        selfieLejana: UIImage,
        datosPersona: DatosINEFrente?
    ) async throws -> ResultadoVerificacion {

        // Comparar rostros con ArcFace
        let simINEvsCercana = try await arcFaceService.compararRostros(rostroINE, selfieCercana)
        let simINEvsLejana = try await arcFaceService.compararRostros(rostroINE, selfieLejana)
        let simCercanavsLejana = try await arcFaceService.compararRostros(selfieCercana, selfieLejana)

        print("FaceEmbedding [ArcFace]: INE vs Cercana: \(String(format: "%.2f", simINEvsCercana * 100))%")
        print("FaceEmbedding [ArcFace]: INE vs Lejana: \(String(format: "%.2f", simINEvsLejana * 100))%")
        print("FaceEmbedding [ArcFace]: Cercana vs Lejana: \(String(format: "%.2f", simCercanavsLejana * 100))%")

        // ArcFace usa umbrales más estrictos (típicamente 0.4-0.5 para match)
        return ResultadoVerificacion.determinarArcFace(
            ineVsCercana: simINEvsCercana,
            ineVsLejana: simINEvsLejana,
            cercanaVsLejana: simCercanavsLejana,
            datosPersona: datosPersona
        )
    }

    /// Verificación usando landmarks geométricos - Fallback
    private func verificarConLandmarks(
        rostroINE: UIImage,
        selfieCercana: UIImage,
        selfieLejana: UIImage,
        datosPersona: DatosINEFrente?
    ) async throws -> ResultadoVerificacion {

        // Generar embeddings faciales con landmarks
        let embeddingINE = try await generarEmbedding(de: rostroINE)
        let embeddingCercana = try await generarEmbedding(de: selfieCercana)
        let embeddingLejana = try await generarEmbedding(de: selfieLejana)

        // Calcular similitudes
        let simINEvsCercana = embeddingINE.similitud(con: embeddingCercana)
        let simINEvsLejana = embeddingINE.similitud(con: embeddingLejana)
        let simCercanavsLejana = embeddingCercana.similitud(con: embeddingLejana)

        print("FaceEmbedding [Landmarks]: INE vs Cercana: \(String(format: "%.2f", simINEvsCercana * 100))%")
        print("FaceEmbedding [Landmarks]: INE vs Lejana: \(String(format: "%.2f", simINEvsLejana * 100))%")
        print("FaceEmbedding [Landmarks]: Cercana vs Lejana: \(String(format: "%.2f", simCercanavsLejana * 100))%")

        return ResultadoVerificacion.determinar(
            ineVsCercana: simINEvsCercana,
            ineVsLejana: simINEvsLejana,
            cercanaVsLejana: simCercanavsLejana,
            datosPersona: datosPersona
        )
    }

    // MARK: - Helpers

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

// MARK: - Errores

enum EmbeddingError: LocalizedError {
    case imagenInvalida
    case sinRostro
    case sinLandmarks
    case errorProcesamiento(Error)

    var errorDescription: String? {
        switch self {
        case .imagenInvalida:
            return "La imagen proporcionada no es válida"
        case .sinRostro:
            return "No se detectó ningún rostro en la imagen"
        case .sinLandmarks:
            return "No se pudieron extraer características faciales"
        case .errorProcesamiento(let error):
            return "Error al procesar: \(error.localizedDescription)"
        }
    }
}

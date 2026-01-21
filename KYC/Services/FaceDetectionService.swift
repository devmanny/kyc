//
//  FaceDetectionService.swift
//  KYC
//

import Vision
import UIKit

actor FaceDetectionService {

    // MARK: - Detección de rostro en foto de INE

    /// Detecta el rostro en una foto de INE.
    /// Usa detección de landmarks para evitar falsos positivos.
    func detectarRostroEnINE(en imagen: UIImage) async throws -> CGRect? {
        // Normalizar orientación primero para consistencia con el recorte
        let imagenNormalizada = normalizarOrientacion(imagen)

        guard let cgImage = imagenNormalizada.cgImage else {
            throw FaceDetectionError.imagenInvalida
        }

        print("FaceDetection INE: Procesando imagen de \(cgImage.width)x\(cgImage.height)")

        // Usar detección de landmarks - más precisa y evita falsos positivos
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try handler.perform([request])

                guard let results = request.results, !results.isEmpty else {
                    print("FaceDetection: No se encontraron rostros en la imagen de INE")
                    continuation.resume(returning: nil)
                    return
                }

                print("FaceDetection: Se encontraron \(results.count) candidatos a rostro")

                // Filtrar ESTRICTAMENTE - debe tener landmarks reales
                let rostrosValidos = results.filter { rostro in
                    let box = rostro.boundingBox
                    let area = box.width * box.height

                    // 1. DEBE tener landmarks detectados (ojos, nariz, boca)
                    guard let landmarks = rostro.landmarks else {
                        print("FaceDetection: Descartado - sin landmarks")
                        return false
                    }

                    // 2. Verificar que tiene los landmarks esenciales de un rostro real
                    let tieneOjoIzq = landmarks.leftEye != nil
                    let tieneOjoDer = landmarks.rightEye != nil
                    let tieneNariz = landmarks.nose != nil
                    let tieneBoca = landmarks.innerLips != nil || landmarks.outerLips != nil

                    let landmarksEncontrados = [tieneOjoIzq, tieneOjoDer, tieneNariz, tieneBoca].filter { $0 }.count

                    print("FaceDetection: Landmarks - ojoIzq:\(tieneOjoIzq) ojoDer:\(tieneOjoDer) nariz:\(tieneNariz) boca:\(tieneBoca)")

                    // Debe tener al menos 3 de los 4 landmarks principales
                    guard landmarksEncontrados >= 3 else {
                        print("FaceDetection: Descartado - solo \(landmarksEncontrados) landmarks (mínimo 3)")
                        return false
                    }

                    // 3. Confianza alta
                    guard rostro.confidence > 0.7 else {
                        print("FaceDetection: Descartado por baja confianza: \(rostro.confidence)")
                        return false
                    }

                    // 4. Tamaño razonable para foto de INE (el rostro ocupa ~5-30% de la tarjeta)
                    guard area > 0.01 && area < 0.4 else {
                        print("FaceDetection: Descartado por tamaño irrazonable: \(area)")
                        return false
                    }

                    // 5. Proporción aproximadamente cuadrada (rostros no son muy alargados)
                    let aspectRatio = box.width / box.height
                    guard aspectRatio > 0.5 && aspectRatio < 2.0 else {
                        print("FaceDetection: Descartado por proporción extraña: \(aspectRatio)")
                        return false
                    }

                    print("FaceDetection: ✓ Rostro válido - área:\(area), confianza:\(rostro.confidence), landmarks:\(landmarksEncontrados)")
                    return true
                }

                if rostrosValidos.isEmpty {
                    print("FaceDetection: Ningún rostro pasó las validaciones estrictas")
                    continuation.resume(returning: nil)
                    return
                }

                // IMPORTANTE: En INE la foto principal está en la mitad IZQUIERDA
                // Filtrar rostros que estén en la mitad izquierda (x < 0.5)
                // También considerar rostros centrados que se extienden hacia la izquierda
                let rostrosEnIzquierda = rostrosValidos.filter { rostro in
                    let box = rostro.boundingBox
                    // El centro del rostro debe estar en el 60% izquierdo de la imagen
                    // Usamos 0.6 para dar un poco de margen por si la foto está ligeramente descentrada
                    let centroX = box.midX
                    let estaEnIzquierda = centroX < 0.6
                    print("FaceDetection: Rostro en x=\(centroX) - \(estaEnIzquierda ? "IZQUIERDA ✓" : "DERECHA (miniatura)")")
                    return estaEnIzquierda
                }

                // Si hay rostros en la izquierda, usar esos; si no, el rostro no es válido
                let candidatos: [VNFaceObservation]
                if !rostrosEnIzquierda.isEmpty {
                    candidatos = rostrosEnIzquierda
                    print("FaceDetection: Usando \(candidatos.count) rostro(s) de la mitad izquierda")
                } else {
                    // No hay rostros válidos en la parte izquierda
                    print("FaceDetection: ⚠️ No se encontró rostro en la parte izquierda de la INE")
                    print("FaceDetection: Solo se encontraron rostros en la parte derecha (posiblemente la miniatura)")
                    continuation.resume(returning: nil)
                    return
                }

                // De los candidatos, tomar el más grande (la foto principal es más grande que la miniatura)
                let rostroMejor = candidatos.max { a, b in
                    let areaA = a.boundingBox.width * a.boundingBox.height
                    let areaB = b.boundingBox.width * b.boundingBox.height
                    return areaA < areaB
                }

                if let rostro = rostroMejor {
                    print("FaceDetection: Rostro FINAL seleccionado - box: \(rostro.boundingBox), área: \(rostro.boundingBox.width * rostro.boundingBox.height)")
                }

                continuation.resume(returning: rostroMejor?.boundingBox)
            } catch {
                print("FaceDetection: Error - \(error)")
                continuation.resume(throwing: FaceDetectionError.errorDeteccion(error))
            }
        }
    }

    private func contarLandmarks(_ landmarks: VNFaceLandmarks2D?) -> Int {
        guard let lm = landmarks else { return 0 }
        var count = 0
        if lm.leftEye != nil { count += 1 }
        if lm.rightEye != nil { count += 1 }
        if lm.nose != nil { count += 1 }
        if lm.innerLips != nil || lm.outerLips != nil { count += 1 }
        if lm.leftEyebrow != nil { count += 1 }
        if lm.rightEyebrow != nil { count += 1 }
        if lm.faceContour != nil { count += 1 }
        return count
    }

    // MARK: - Detección de rostro en selfie

    func detectarRostro(en imagen: UIImage) async throws -> CGRect? {
        // Normalizar orientación primero para consistencia con el recorte
        let imagenNormalizada = normalizarOrientacion(imagen)

        guard let cgImage = imagenNormalizada.cgImage else {
            throw FaceDetectionError.imagenInvalida
        }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try handler.perform([request])

                guard let results = request.results, !results.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                // Para selfies, tomamos el rostro más grande
                let rostroMasGrande = results.max {
                    $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
                }

                continuation.resume(returning: rostroMasGrande?.boundingBox)
            } catch {
                continuation.resume(throwing: FaceDetectionError.errorDeteccion(error))
            }
        }
    }

    // MARK: - Normalizar orientación de imagen

    /// Convierte la imagen a orientación .up para que las coordenadas de Vision coincidan con el CGImage
    private func normalizarOrientacion(_ imagen: UIImage) -> UIImage {
        guard imagen.imageOrientation != .up else { return imagen }

        UIGraphicsBeginImageContextWithOptions(imagen.size, false, imagen.scale)
        imagen.draw(in: CGRect(origin: .zero, size: imagen.size))
        let imagenNormalizada = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return imagenNormalizada ?? imagen
    }

    // MARK: - Recortar rostro

    func recortarRostro(de imagen: UIImage, boundingBox: CGRect, margen: CGFloat = 0.4) -> UIImage? {
        // Primero normalizar la orientación para que las coordenadas coincidan
        let imagenNormalizada = normalizarOrientacion(imagen)

        guard let cgImage = imagenNormalizada.cgImage else { return nil }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        print("FaceDetection: Imagen size: \(width)x\(height), boundingBox: \(boundingBox)")

        // Convertir boundingBox normalizado a coordenadas de píxeles
        // Vision usa coordenadas con origen en esquina inferior izquierda
        var rect = CGRect(
            x: boundingBox.origin.x * width,
            y: (1 - boundingBox.origin.y - boundingBox.height) * height,
            width: boundingBox.width * width,
            height: boundingBox.height * height
        )

        print("FaceDetection: Rect inicial: \(rect)")

        // Agregar margen generoso para incluir contexto
        let margenX = rect.width * margen
        let margenY = rect.height * margen

        rect = rect.insetBy(dx: -margenX, dy: -margenY)

        // Asegurar que el rectángulo esté dentro de los límites de la imagen
        rect = rect.intersection(CGRect(x: 0, y: 0, width: width, height: height))

        print("FaceDetection: Rect final con margen: \(rect)")

        guard !rect.isEmpty, rect.width > 10, rect.height > 10,
              let croppedCGImage = cgImage.cropping(to: rect) else {
            print("FaceDetection: No se pudo recortar - rect inválido")
            return nil
        }

        return UIImage(cgImage: croppedCGImage, scale: imagenNormalizada.scale, orientation: .up)
    }

    // MARK: - Detectar y recortar en un solo paso

    func detectarYRecortarRostroDeINE(de imagen: UIImage) async throws -> UIImage? {
        guard let boundingBox = try await detectarRostroEnINE(en: imagen) else {
            print("FaceDetection: No se pudo detectar rostro en INE")
            return nil
        }

        let rostroRecortado = recortarRostro(de: imagen, boundingBox: boundingBox, margen: 0.5)
        print("FaceDetection: Rostro recortado de INE: \(rostroRecortado != nil ? "OK" : "FALLÓ")")
        return rostroRecortado
    }

    func detectarYRecortarRostro(de imagen: UIImage) async throws -> UIImage? {
        guard let boundingBox = try await detectarRostro(en: imagen) else {
            return nil
        }

        return recortarRostro(de: imagen, boundingBox: boundingBox, margen: 0.3)
    }

    // MARK: - Validación para selfie

    func validarRostroParaSelfie(en imagen: UIImage) async throws -> (valido: Bool, mensaje: String) {
        guard let cgImage = imagen.cgImage else {
            throw FaceDetectionError.imagenInvalida
        }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientacionCGImage(de: imagen), options: [:])

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try handler.perform([request])

                guard let results = request.results else {
                    continuation.resume(returning: (false, "No se pudo analizar la imagen"))
                    return
                }

                if results.isEmpty {
                    continuation.resume(returning: (false, "No se detectó ningún rostro"))
                    return
                }

                if results.count > 1 {
                    continuation.resume(returning: (false, "Se detectaron múltiples rostros. Solo debe aparecer una persona."))
                    return
                }

                let rostro = results[0]
                let box = rostro.boundingBox

                let area = box.width * box.height
                if area < 0.05 {
                    continuation.resume(returning: (false, "Acércate más a la cámara"))
                    return
                }

                let centroRostroX = box.midX
                let centroRostroY = box.midY

                if centroRostroX < 0.25 || centroRostroX > 0.75 {
                    continuation.resume(returning: (false, "Centra tu rostro horizontalmente"))
                    return
                }

                if centroRostroY < 0.25 || centroRostroY > 0.75 {
                    continuation.resume(returning: (false, "Centra tu rostro verticalmente"))
                    return
                }

                continuation.resume(returning: (true, "Rostro detectado correctamente"))
            } catch {
                continuation.resume(throwing: FaceDetectionError.errorDeteccion(error))
            }
        }
    }

    // MARK: - Detección de Documento (INE/ID Card)

    /// Detecta y recorta un documento/tarjeta de la imagen
    /// Usa VNDetectDocumentSegmentationRequest para detectar los bordes del documento
    func detectarYRecortarDocumento(en imagen: UIImage) async throws -> UIImage? {
        let imagenNormalizada = normalizarOrientacion(imagen)

        guard let cgImage = imagenNormalizada.cgImage else {
            throw FaceDetectionError.imagenInvalida
        }

        print("DocumentDetection: Procesando imagen de \(cgImage.width)x\(cgImage.height)")

        // Usar VNDetectDocumentSegmentationRequest para detectar documentos
        let request = VNDetectDocumentSegmentationRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try handler.perform([request])

                guard let result = request.results?.first else {
                    print("DocumentDetection: No se detectó documento, intentando con rectángulos...")
                    // Fallback: intentar detectar rectángulos
                    Task {
                        let rectResult = try? await self.detectarRectanguloDocumento(en: imagenNormalizada)
                        continuation.resume(returning: rectResult ?? imagenNormalizada)
                    }
                    return
                }

                // Obtener el boundingBox del documento detectado
                let boundingBox = result.boundingBox
                print("DocumentDetection: Documento detectado - boundingBox: \(boundingBox)")

                // Convertir boundingBox normalizado a coordenadas de píxeles
                let width = CGFloat(cgImage.width)
                let height = CGFloat(cgImage.height)

                // Vision usa coordenadas con origen en esquina inferior izquierda
                let rectX = boundingBox.origin.x * width
                let rectY = (1 - boundingBox.origin.y - boundingBox.height) * height
                let rectWidth = boundingBox.width * width
                let rectHeight = boundingBox.height * height

                // Agregar un pequeño margen
                let margen: CGFloat = 10
                let cropRect = CGRect(
                    x: max(0, rectX - margen),
                    y: max(0, rectY - margen),
                    width: min(width - rectX + margen, rectWidth + margen * 2),
                    height: min(height - rectY + margen, rectHeight + margen * 2)
                )

                print("DocumentDetection: cropRect = \(cropRect)")

                guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
                    print("DocumentDetection: Error al recortar, devolviendo original")
                    continuation.resume(returning: imagenNormalizada)
                    return
                }

                let croppedImage = UIImage(cgImage: croppedCGImage, scale: imagenNormalizada.scale, orientation: .up)
                print("DocumentDetection: Documento recortado exitosamente: \(croppedCGImage.width)x\(croppedCGImage.height)")
                continuation.resume(returning: croppedImage)

            } catch {
                print("DocumentDetection: Error - \(error)")
                continuation.resume(returning: imagenNormalizada)
            }
        }
    }

    /// Fallback: Detecta rectángulos en la imagen (para documentos)
    private func detectarRectanguloDocumento(en imagen: UIImage) async throws -> UIImage? {
        guard let cgImage = imagen.cgImage else { return nil }

        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.5  // INE tiene proporción ~1.586:1
        request.maximumAspectRatio = 2.0
        request.minimumSize = 0.2  // El documento debe ocupar al menos 20% de la imagen
        request.minimumConfidence = 0.6

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try handler.perform([request])

                guard let result = request.results?.first else {
                    print("RectangleDetection: No se detectó rectángulo")
                    continuation.resume(returning: nil)
                    return
                }

                let boundingBox = result.boundingBox
                print("RectangleDetection: Rectángulo detectado - boundingBox: \(boundingBox)")

                let width = CGFloat(cgImage.width)
                let height = CGFloat(cgImage.height)

                let rectX = boundingBox.origin.x * width
                let rectY = (1 - boundingBox.origin.y - boundingBox.height) * height
                let rectWidth = boundingBox.width * width
                let rectHeight = boundingBox.height * height

                let margen: CGFloat = 15
                let cropRect = CGRect(
                    x: max(0, rectX - margen),
                    y: max(0, rectY - margen),
                    width: min(width - rectX + margen, rectWidth + margen * 2),
                    height: min(height - rectY + margen, rectHeight + margen * 2)
                )

                guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
                    continuation.resume(returning: nil)
                    return
                }

                let croppedImage = UIImage(cgImage: croppedCGImage, scale: imagen.scale, orientation: .up)
                print("RectangleDetection: Rectángulo recortado: \(croppedCGImage.width)x\(croppedCGImage.height)")
                continuation.resume(returning: croppedImage)

            } catch {
                print("RectangleDetection: Error - \(error)")
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Helpers

    private func orientacionCGImage(de imagen: UIImage) -> CGImagePropertyOrientation {
        switch imagen.imageOrientation {
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

enum FaceDetectionError: Error, LocalizedError {
    case imagenInvalida
    case errorDeteccion(Error)
    case sinRostro

    var errorDescription: String? {
        switch self {
        case .imagenInvalida:
            return "La imagen no es válida"
        case .errorDeteccion(let error):
            return "Error al detectar rostro: \(error.localizedDescription)"
        case .sinRostro:
            return "No se detectó ningún rostro en la imagen"
        }
    }
}

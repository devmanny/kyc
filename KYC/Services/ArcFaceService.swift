//
//  ArcFaceService.swift
//  KYC
//
//  Servicio de reconocimiento facial usando modelo ArcFace/MobileFaceNet con Core ML
//  Genera embeddings de 512 dimensiones para comparación precisa de rostros
//

import Vision
import UIKit
import CoreML
import Accelerate

actor ArcFaceService {

    // MARK: - Propiedades

    /// Modelo Core ML para generar embeddings faciales
    /// IMPORTANTE: Debes agregar el archivo MobileFaceNet.mlmodelc al proyecto
    private var model: MLModel?

    /// Tamaño de entrada del modelo (típicamente 112x112 para ArcFace/MobileFaceNet)
    private let inputSize: CGSize = CGSize(width: 112, height: 112)

    /// Dimensión del embedding (512 para ArcFace, 128 para FaceNet)
    private let embeddingDimension = 512

    // MARK: - Inicialización

    init() {
        Task {
            await cargarModelo()
        }
    }

    private func cargarModelo() {
        // Intentar cargar el modelo MobileFaceNet
        do {
            // Buscar el modelo en el bundle (puede ser .mlmodelc o .mlpackage compilado)
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine // Usar Neural Engine para máximo rendimiento

            // Intentar diferentes extensiones
            if let modelURL = Bundle.main.url(forResource: "MobileFaceNet", withExtension: "mlmodelc") {
                model = try MLModel(contentsOf: modelURL, configuration: config)
                print("ArcFace: ✓ Modelo MobileFaceNet.mlmodelc cargado")
            } else if let modelURL = Bundle.main.url(forResource: "MobileFaceNet", withExtension: "mlpackage") {
                // mlpackage se compila automáticamente por Xcode
                let compiledURL = try MLModel.compileModel(at: modelURL)
                model = try MLModel(contentsOf: compiledURL, configuration: config)
                print("ArcFace: ✓ Modelo MobileFaceNet.mlpackage cargado")
            } else {
                print("ArcFace: ⚠️ Modelo MobileFaceNet no encontrado en el bundle")
                print("ArcFace: Usando algoritmo de landmarks como fallback")
            }
        } catch {
            print("ArcFace: Error al cargar modelo - \(error.localizedDescription)")
        }
    }

    // MARK: - API Pública

    /// Verifica si el modelo está disponible
    var modeloDisponible: Bool {
        model != nil
    }

    /// Genera un embedding facial de 512 dimensiones
    func generarEmbedding(de imagen: UIImage) async throws -> [Float] {
        guard let model = model else {
            throw ArcFaceError.modeloNoDisponible
        }

        // 1. Detectar y alinear rostro
        guard let rostroAlineado = try await detectarYAlinearRostro(en: imagen) else {
            throw ArcFaceError.sinRostro
        }

        // 2. Preprocesar para el modelo
        guard let inputBuffer = preprocesarImagen(rostroAlineado) else {
            throw ArcFaceError.errorPreprocesamiento
        }

        // 3. Ejecutar inferencia
        let embedding = try await ejecutarInferencia(input: inputBuffer)

        return embedding
    }

    /// Compara dos embeddings y retorna similitud coseno (-1 a 1, típicamente 0.3-1.0 para caras)
    func compararEmbeddings(_ embedding1: [Float], _ embedding2: [Float]) -> Float {
        guard embedding1.count == embedding2.count, !embedding1.isEmpty else {
            return 0
        }

        // Calcular similitud coseno
        var dotProduct: Float = 0
        var norm1: Float = 0
        var norm2: Float = 0

        vDSP_dotpr(embedding1, 1, embedding2, 1, &dotProduct, vDSP_Length(embedding1.count))
        vDSP_dotpr(embedding1, 1, embedding1, 1, &norm1, vDSP_Length(embedding1.count))
        vDSP_dotpr(embedding2, 1, embedding2, 1, &norm2, vDSP_Length(embedding2.count))

        let normProduct = sqrt(norm1) * sqrt(norm2)
        guard normProduct > 0 else { return 0 }

        let similarity = dotProduct / normProduct
        return similarity
    }

    /// Compara dos imágenes de rostros y retorna similitud (0.0 a 1.0 normalizada)
    func compararRostros(_ imagen1: UIImage, _ imagen2: UIImage) async throws -> Float {
        let embedding1 = try await generarEmbedding(de: imagen1)
        let embedding2 = try await generarEmbedding(de: imagen2)

        let similitudCoseno = compararEmbeddings(embedding1, embedding2)

        // Normalizar de rango coseno (-1 a 1) a (0 a 1)
        // Para rostros, típicamente el coseno está entre 0.2 y 1.0
        // Usamos umbral de 0.2 como mínimo y escalamos
        let similitudNormalizada = max(0, (similitudCoseno - 0.2)) / 0.8

        return min(1.0, similitudNormalizada)
    }

    // MARK: - Procesamiento de Imagen

    /// Detecta el rostro y lo alinea usando los landmarks de los ojos
    private func detectarYAlinearRostro(en imagen: UIImage) async throws -> UIImage? {
        guard let cgImage = imagen.cgImage else {
            throw ArcFaceError.imagenInvalida
        }

        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgImageOrientation(from: imagen.imageOrientation), options: [:])

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try handler.perform([request])

                guard let face = request.results?.first,
                      let landmarks = face.landmarks else {
                    continuation.resume(returning: nil)
                    return
                }

                // Obtener puntos de los ojos para alineación
                guard let leftEye = landmarks.leftEye,
                      let rightEye = landmarks.rightEye else {
                    // Sin landmarks de ojos, solo recortar
                    let rostroRecortado = self.recortarRostro(cgImage: cgImage, boundingBox: face.boundingBox)
                    continuation.resume(returning: rostroRecortado)
                    return
                }

                // Calcular centros de ojos
                let leftEyeCenter = self.centroide(de: leftEye.normalizedPoints)
                let rightEyeCenter = self.centroide(de: rightEye.normalizedPoints)

                // Alinear y recortar
                let rostroAlineado = self.alinearYRecortarRostro(
                    cgImage: cgImage,
                    boundingBox: face.boundingBox,
                    leftEye: leftEyeCenter,
                    rightEye: rightEyeCenter
                )

                continuation.resume(returning: rostroAlineado)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Alinea el rostro para que los ojos estén horizontales
    private func alinearYRecortarRostro(
        cgImage: CGImage,
        boundingBox: CGRect,
        leftEye: CGPoint,
        rightEye: CGPoint
    ) -> UIImage? {
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        // Convertir bounding box a coordenadas de imagen
        let faceRect = CGRect(
            x: boundingBox.origin.x * imageWidth,
            y: (1 - boundingBox.origin.y - boundingBox.height) * imageHeight,
            width: boundingBox.width * imageWidth,
            height: boundingBox.height * imageHeight
        )

        // Convertir posiciones de ojos a coordenadas absolutas
        let leftEyeAbs = CGPoint(
            x: faceRect.origin.x + leftEye.x * faceRect.width,
            y: faceRect.origin.y + (1 - leftEye.y) * faceRect.height
        )
        let rightEyeAbs = CGPoint(
            x: faceRect.origin.x + rightEye.x * faceRect.width,
            y: faceRect.origin.y + (1 - rightEye.y) * faceRect.height
        )

        // Calcular ángulo de rotación
        let dY = rightEyeAbs.y - leftEyeAbs.y
        let dX = rightEyeAbs.x - leftEyeAbs.x
        let angle = atan2(dY, dX)

        // Expandir el rect para incluir más contexto facial
        let expandedRect = faceRect.insetBy(dx: -faceRect.width * 0.2, dy: -faceRect.height * 0.2)
        let safeRect = expandedRect.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

        guard !safeRect.isEmpty else {
            return recortarRostro(cgImage: cgImage, boundingBox: boundingBox)
        }

        // Crear contexto para rotación y recorte
        let outputSize = inputSize
        UIGraphicsBeginImageContextWithOptions(outputSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        // Transformar: mover al centro, rotar, escalar
        context.translateBy(x: outputSize.width / 2, y: outputSize.height / 2)
        context.rotate(by: -angle)

        let scale = min(outputSize.width / safeRect.width, outputSize.height / safeRect.height)
        context.scaleBy(x: scale, y: scale)

        // Dibujar imagen centrada
        let drawRect = CGRect(
            x: -safeRect.midX,
            y: -safeRect.midY,
            width: imageWidth,
            height: imageHeight
        )

        if let uiImage = UIImage(cgImage: cgImage).cgImage {
            context.draw(uiImage, in: drawRect)
        }

        return UIGraphicsGetImageFromCurrentImageContext()
    }

    /// Recorta el rostro sin alineación (fallback)
    private func recortarRostro(cgImage: CGImage, boundingBox: CGRect) -> UIImage? {
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        var faceRect = CGRect(
            x: boundingBox.origin.x * imageWidth,
            y: (1 - boundingBox.origin.y - boundingBox.height) * imageHeight,
            width: boundingBox.width * imageWidth,
            height: boundingBox.height * imageHeight
        )

        // Expandir para incluir contexto
        faceRect = faceRect.insetBy(dx: -faceRect.width * 0.2, dy: -faceRect.height * 0.2)
        faceRect = faceRect.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

        guard !faceRect.isEmpty,
              let croppedCG = cgImage.cropping(to: faceRect) else {
            return nil
        }

        // Redimensionar a tamaño de entrada del modelo
        UIGraphicsBeginImageContextWithOptions(inputSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        UIImage(cgImage: croppedCG).draw(in: CGRect(origin: .zero, size: inputSize))
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    /// Preprocesa la imagen para el modelo Core ML
    private func preprocesarImagen(_ imagen: UIImage) -> MLMultiArray? {
        guard let cgImage = imagen.cgImage else { return nil }

        // Crear MLMultiArray con formato [1, 3, 112, 112] (batch, channels, height, width)
        guard let array = try? MLMultiArray(shape: [1, 3, 112, 112], dataType: .float32) else {
            return nil
        }

        // Obtener píxeles de la imagen
        let width = Int(inputSize.width)
        let height = Int(inputSize.height)
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width

        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Normalizar píxeles y llenar el array
        // Normalización típica para modelos de face recognition: (pixel - 127.5) / 128.0
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * bytesPerPixel
                let r = Float(pixelData[offset]) / 255.0 * 2.0 - 1.0     // -1 a 1
                let g = Float(pixelData[offset + 1]) / 255.0 * 2.0 - 1.0
                let b = Float(pixelData[offset + 2]) / 255.0 * 2.0 - 1.0

                // Formato NCHW (batch, channel, height, width)
                let idx = y * width + x
                array[[0, 0, y, x] as [NSNumber]] = NSNumber(value: r)
                array[[0, 1, y, x] as [NSNumber]] = NSNumber(value: g)
                array[[0, 2, y, x] as [NSNumber]] = NSNumber(value: b)
            }
        }

        return array
    }

    /// Ejecuta inferencia en el modelo Core ML
    private func ejecutarInferencia(input: MLMultiArray) async throws -> [Float] {
        guard let model = model else {
            throw ArcFaceError.modeloNoDisponible
        }

        // Crear el input provider
        // El nombre del input es "image" para nuestro modelo MobileFaceNet
        let inputFeature = try MLDictionaryFeatureProvider(dictionary: ["image": input])

        // Ejecutar predicción
        let output = try await model.prediction(from: inputFeature)

        // Obtener el embedding del output
        // Nombres conocidos de salida para MobileFaceNet
        let outputNames = ["var_854", "output", "embedding", "fc1", "pre_fc1", "516"]

        for name in outputNames {
            if let embeddingArray = output.featureValue(for: name)?.multiArrayValue {
                print("ArcFace: Embedding extraído de '\(name)' con \(embeddingArray.count) dimensiones")
                return multiArrayToFloatArray(embeddingArray)
            }
        }

        // Si no encontramos por nombre, tomar el primer output disponible
        for name in output.featureNames {
            if let embeddingArray = output.featureValue(for: name)?.multiArrayValue {
                print("ArcFace: Embedding extraído de '\(name)' (fallback)")
                return multiArrayToFloatArray(embeddingArray)
            }
        }

        throw ArcFaceError.errorInferencia
    }

    // MARK: - Helpers

    private func multiArrayToFloatArray(_ array: MLMultiArray) -> [Float] {
        let count = array.count
        var result = [Float](repeating: 0, count: count)

        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: count)
        for i in 0..<count {
            result[i] = ptr[i]
        }

        // Normalizar el embedding (L2 normalization)
        var norm: Float = 0
        vDSP_dotpr(result, 1, result, 1, &norm, vDSP_Length(count))
        norm = sqrt(norm)

        if norm > 0 {
            var scale = 1.0 / norm
            vDSP_vsmul(result, 1, &scale, &result, 1, vDSP_Length(count))
        }

        return result
    }

    private func centroide(de points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sumX = points.reduce(0) { $0 + $1.x }
        let sumY = points.reduce(0) { $0 + $1.y }
        return CGPoint(x: sumX / CGFloat(points.count), y: sumY / CGFloat(points.count))
    }

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

enum ArcFaceError: LocalizedError {
    case modeloNoDisponible
    case imagenInvalida
    case sinRostro
    case errorPreprocesamiento
    case errorInferencia

    var errorDescription: String? {
        switch self {
        case .modeloNoDisponible:
            return "El modelo de reconocimiento facial no está disponible. Agrega MobileFaceNet.mlmodelc al proyecto."
        case .imagenInvalida:
            return "La imagen proporcionada no es válida"
        case .sinRostro:
            return "No se detectó ningún rostro en la imagen"
        case .errorPreprocesamiento:
            return "Error al preparar la imagen para el modelo"
        case .errorInferencia:
            return "Error al ejecutar el modelo de reconocimiento facial"
        }
    }
}

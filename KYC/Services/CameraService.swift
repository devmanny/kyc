//
//  CameraService.swift
//  KYC
//

@preconcurrency import AVFoundation
import UIKit
import Combine

enum CameraError: Error {
    case noAccesoPermitido
    case camaraNoDisponible
    case errorConfiguracion
    case errorCaptura
}

enum TipoCamara {
    case trasera
    case frontal
}

enum LenteCamara: String, CaseIterable, Identifiable {
    case granAngular = "Gran Angular"
    case ultraWide = "Ultra Wide"
    case telefoto = "Telefoto"

    var id: String { rawValue }

    var icono: String {
        switch self {
        case .granAngular: return "camera"
        case .ultraWide: return "camera.filters"
        case .telefoto: return "plus.magnifyingglass"
        }
    }

    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .granAngular: return .builtInWideAngleCamera
        case .ultraWide: return .builtInUltraWideCamera
        case .telefoto: return .builtInTelephotoCamera
        }
    }
}

enum ModoEnfoque: String, CaseIterable, Identifiable {
    case automatico = "Automático"
    case continuo = "Continuo"
    case bloqueado = "Bloqueado"

    var id: String { rawValue }

    var icono: String {
        switch self {
        case .automatico: return "viewfinder"
        case .continuo: return "viewfinder.circle"
        case .bloqueado: return "lock.fill"
        }
    }
}

@MainActor
class CameraService: NSObject, ObservableObject {
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var fotoCapturada: UIImage?
    @Published var error: CameraError?
    @Published var estaListo = false
    @Published var estaEnfocando = false

    // Opciones de cámara configurables
    @Published var lenteSeleccionado: LenteCamara = .ultraWide
    @Published var modoEnfoque: ModoEnfoque = .continuo
    @Published var flashActivado = false
    @Published var lentesDisponibles: [LenteCamara] = []

    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var currentDevice: AVCaptureDevice?
    private var currentCamera: TipoCamara = .trasera
    private var capturaCompletion: ((UIImage?) -> Void)?
    private var focusObservation: NSKeyValueObservation?

    // MARK: - Permisos

    func solicitarPermisos() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Configuración

    /// Detecta qué lentes están disponibles en el dispositivo
    func detectarLentesDisponibles() {
        let position: AVCaptureDevice.Position = .back
        var disponibles: [LenteCamara] = []

        for lente in LenteCamara.allCases {
            if AVCaptureDevice.default(lente.deviceType, for: .video, position: position) != nil {
                disponibles.append(lente)
            }
        }

        lentesDisponibles = disponibles

        // Si el lente seleccionado no está disponible, usar el primero disponible
        if !disponibles.contains(lenteSeleccionado), let primero = disponibles.first {
            lenteSeleccionado = primero
        }

        print("CameraService: Lentes disponibles: \(disponibles.map { $0.rawValue }), seleccionado: \(lenteSeleccionado.rawValue)")
    }

    func configurarCamara(tipo: TipoCamara) async throws {
        guard await solicitarPermisos() else {
            error = .noAccesoPermitido
            throw CameraError.noAccesoPermitido
        }

        currentCamera = tipo
        captureSession?.stopRunning()

        // Detectar lentes disponibles
        if tipo == .trasera {
            detectarLentesDisponibles()
        }

        let session = AVCaptureSession()
        session.sessionPreset = .photo // Mejor calidad para fotos

        // Seleccionar cámara según lente elegido
        let position: AVCaptureDevice.Position = tipo == .trasera ? .back : .front
        let deviceType: AVCaptureDevice.DeviceType = tipo == .trasera ? lenteSeleccionado.deviceType : .builtInWideAngleCamera

        guard let device = AVCaptureDevice.default(deviceType, for: .video, position: position) else {
            // Fallback a gran angular si el lente seleccionado no está disponible
            guard let fallbackDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
                error = .camaraNoDisponible
                throw CameraError.camaraNoDisponible
            }
            try await configurarDispositivo(fallbackDevice, session: session)
            return
        }

        try await configurarDispositivo(device, session: session)
    }

    private func configurarDispositivo(_ device: AVCaptureDevice, session: AVCaptureSession) async throws {
        // Configurar enfoque según modo seleccionado
        do {
            try device.lockForConfiguration()

            // Aplicar modo de enfoque seleccionado
            aplicarModoEnfoque(a: device)

            // Exposición continua
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }

            // Activar linterna si flash está activado
            if device.hasTorch && flashActivado {
                device.torchMode = .on
            } else if device.hasTorch {
                device.torchMode = .off
            }

            device.unlockForConfiguration()
        } catch {
            print("Error configurando cámara: \(error)")
        }

        currentDevice = device

        // Observar estado de enfoque
        focusObservation?.invalidate()
        focusObservation = device.observe(\.isAdjustingFocus, options: [.new]) { _, change in
            let isAdjusting = change.newValue ?? false
            Task { @MainActor [weak self] in
                self?.estaEnfocando = isAdjusting
            }
        }

        // Input
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            error = .errorConfiguracion
            throw CameraError.errorConfiguracion
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        // Output
        let output = AVCapturePhotoOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        photoOutput = output
        captureSession = session

        // Preview layer
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill

        await MainActor.run {
            self.previewLayer = layer
            self.estaListo = true
        }
    }

    // MARK: - Control

    func iniciarCaptura() {
        guard let session = captureSession, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    func detenerCaptura() {
        guard let session = captureSession, session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }

    func capturarFoto() async -> UIImage? {
        guard let photoOutput = photoOutput else { return nil }

        // Esperar a que el enfoque se estabilice (máximo 1.5 segundos)
        var esperaEnfoque = 0
        while estaEnfocando && esperaEnfoque < 15 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            esperaEnfoque += 1
        }

        // Pequeña pausa adicional para asegurar estabilidad
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        return await withCheckedContinuation { continuation in
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off

            self.capturaCompletion = { imagen in
                continuation.resume(returning: imagen)
            }

            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func cambiarCamara(a tipo: TipoCamara) async throws {
        detenerCaptura()
        try await configurarCamara(tipo: tipo)
        iniciarCaptura()
    }

    /// Enfoca en un punto específico usando coordenadas del preview layer
    func enfocarEn(puntoEnPreview: CGPoint) {
        guard let device = currentDevice,
              let layer = previewLayer else { return }

        // Convertir coordenadas de la vista a coordenadas del dispositivo de captura
        let puntoDispositivo = layer.captureDevicePointConverted(fromLayerPoint: puntoEnPreview)

        print("CameraService: Tap en preview: \(puntoEnPreview) -> dispositivo: \(puntoDispositivo)")

        do {
            try device.lockForConfiguration()

            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = puntoDispositivo
                device.focusMode = .autoFocus
                print("CameraService: Enfocando en punto \(puntoDispositivo)")
            }

            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = puntoDispositivo
                device.exposureMode = .autoExpose
            }

            device.unlockForConfiguration()
        } catch {
            print("Error al enfocar: \(error)")
        }
    }

    /// Aplica el modo de enfoque seleccionado
    private func aplicarModoEnfoque(a device: AVCaptureDevice) {
        switch modoEnfoque {
        case .automatico:
            if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            }
        case .continuo:
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
        case .bloqueado:
            if device.isFocusModeSupported(.locked) {
                device.focusMode = .locked
            }
        }
    }

    /// Cambia el modo de enfoque en vivo
    func cambiarModoEnfoque(_ modo: ModoEnfoque) {
        modoEnfoque = modo
        guard let device = currentDevice else { return }

        do {
            try device.lockForConfiguration()
            aplicarModoEnfoque(a: device)
            device.unlockForConfiguration()
            print("CameraService: Modo enfoque cambiado a \(modo.rawValue)")
        } catch {
            print("Error al cambiar modo enfoque: \(error)")
        }
    }

    /// Cambia el lente de la cámara
    func cambiarLente(_ lente: LenteCamara) async throws {
        lenteSeleccionado = lente
        detenerCaptura()
        try await configurarCamara(tipo: currentCamera)
        iniciarCaptura()
        print("CameraService: Lente cambiado a \(lente.rawValue)")
    }

    /// Activa o desactiva el flash/linterna
    func toggleFlash() {
        flashActivado.toggle()
        guard let device = currentDevice, device.hasTorch else { return }

        do {
            try device.lockForConfiguration()
            device.torchMode = flashActivado ? .on : .off
            device.unlockForConfiguration()
            print("CameraService: Flash \(flashActivado ? "activado" : "desactivado")")
        } catch {
            print("Error al cambiar flash: \(error)")
        }
    }

    /// Re-activa el enfoque continuo
    func activarEnfoqueContinuo() {
        guard let device = currentDevice else { return }

        do {
            try device.lockForConfiguration()

            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }

            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }

            device.unlockForConfiguration()
        } catch {
            print("Error al activar enfoque continuo: \(error)")
        }
    }

    /// Fuerza un re-enfoque
    func forzarEnfoque() {
        guard let device = currentDevice else { return }

        do {
            try device.lockForConfiguration()

            // Cambiar a autoFocus dispara un nuevo ciclo de enfoque
            if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            }

            device.unlockForConfiguration()
            print("CameraService: Enfoque forzado")
        } catch {
            print("Error al forzar enfoque: \(error)")
        }
    }

    /// Captura foto y la recorta al área visible del preview (lo que el usuario vio)
    func capturarFotoVisibleEnPreview(previewSize: CGSize) async -> UIImage? {
        guard let fotoOriginal = await capturarFoto() else { return nil }

        // Validar que previewSize sea válido
        guard previewSize.width > 0 && previewSize.height > 0 else {
            print("CameraService: previewSize inválido (\(previewSize)), devolviendo imagen original")
            return fotoOriginal
        }

        // PASO 1: Normalizar la orientación (redibujar la imagen con orientación .up)
        // Esto simplifica enormemente el recorte porque no tenemos que convertir coordenadas
        let foto = normalizarOrientacion(fotoOriginal)

        guard let cgImage = foto.cgImage else { return fotoOriginal }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        print("CameraService: Imagen normalizada=\(imageSize), preview=\(previewSize)")

        let imageAspect = imageSize.width / imageSize.height
        let previewAspect = previewSize.width / previewSize.height

        // PASO 2: Calcular el área visible con aspectFill
        var cropRect: CGRect

        if imageAspect > previewAspect {
            // La imagen es más ancha que el preview - se recortan los lados
            let visibleWidth = imageSize.height * previewAspect
            let offsetX = (imageSize.width - visibleWidth) / 2
            cropRect = CGRect(x: offsetX, y: 0, width: visibleWidth, height: imageSize.height)
        } else {
            // La imagen es más alta que el preview - se recorta arriba/abajo
            let visibleHeight = imageSize.width / previewAspect
            let offsetY = (imageSize.height - visibleHeight) / 2
            cropRect = CGRect(x: 0, y: offsetY, width: imageSize.width, height: visibleHeight)
        }

        print("CameraService: cropRect = \(cropRect)")

        // PASO 3: Recortar
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            print("CameraService: Error al recortar, devolviendo imagen original")
            return foto
        }

        print("CameraService: Foto recortada de \(imageSize) a \(croppedCGImage.width)x\(croppedCGImage.height)")
        return UIImage(cgImage: croppedCGImage, scale: foto.scale, orientation: .up)
    }

    /// Normaliza la orientación de una imagen redibujándola con orientación .up
    private func normalizarOrientacion(_ imagen: UIImage) -> UIImage {
        guard imagen.imageOrientation != .up else { return imagen }

        UIGraphicsBeginImageContextWithOptions(imagen.size, false, imagen.scale)
        imagen.draw(in: CGRect(origin: .zero, size: imagen.size))
        let imagenNormalizada = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return imagenNormalizada ?? imagen
    }

    /// Captura foto y la recorta al área visible del preview con un rect específico
    func capturarFotoRecortada(previewBounds: CGRect, cropRect: CGRect) async -> UIImage? {
        guard let foto = await capturarFoto(),
              let layer = previewLayer else { return nil }

        return recortarFotoAAreaVisible(
            foto: foto,
            previewBounds: previewBounds,
            cropRect: cropRect,
            videoGravity: layer.videoGravity
        )
    }

    /// Recorta la foto al área visible considerando el videoGravity del preview layer
    private func recortarFotoAAreaVisible(
        foto: UIImage,
        previewBounds: CGRect,
        cropRect: CGRect,
        videoGravity: AVLayerVideoGravity
    ) -> UIImage? {
        guard let cgImage = foto.cgImage else { return nil }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let previewSize = previewBounds.size

        // Calcular la transformación según el videoGravity (resizeAspectFill)
        let imageAspect = imageSize.width / imageSize.height
        let previewAspect = previewSize.width / previewSize.height

        var visibleRect: CGRect

        if videoGravity == .resizeAspectFill {
            // En AspectFill, la imagen se escala para llenar el preview y se recorta
            if imageAspect > previewAspect {
                // La imagen es más ancha - se recortan los lados
                let visibleWidth = imageSize.height * previewAspect
                let offsetX = (imageSize.width - visibleWidth) / 2
                visibleRect = CGRect(x: offsetX, y: 0, width: visibleWidth, height: imageSize.height)
            } else {
                // La imagen es más alta - se recorta arriba/abajo
                let visibleHeight = imageSize.width / previewAspect
                let offsetY = (imageSize.height - visibleHeight) / 2
                visibleRect = CGRect(x: 0, y: offsetY, width: imageSize.width, height: visibleHeight)
            }
        } else {
            // Para otros modos, usar la imagen completa
            visibleRect = CGRect(origin: .zero, size: imageSize)
        }

        // Ahora calcular el cropRect relativo al área visible
        let scaleX = visibleRect.width / previewSize.width
        let scaleY = visibleRect.height / previewSize.height

        let finalCropRect = CGRect(
            x: visibleRect.origin.x + (cropRect.origin.x * scaleX),
            y: visibleRect.origin.y + (cropRect.origin.y * scaleY),
            width: cropRect.width * scaleX,
            height: cropRect.height * scaleY
        )

        // Asegurar que el rect está dentro de los límites de la imagen
        let clampedRect = finalCropRect.intersection(CGRect(origin: .zero, size: imageSize))

        guard !clampedRect.isEmpty,
              let croppedCGImage = cgImage.cropping(to: clampedRect) else {
            print("CameraService: Error al recortar, devolviendo imagen original")
            return foto
        }

        print("CameraService: Foto recortada de \(imageSize) a \(clampedRect.size)")
        return UIImage(cgImage: croppedCGImage, scale: foto.scale, orientation: foto.imageOrientation)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let imagen = UIImage(data: data) else {
            Task { @MainActor in
                self.capturaCompletion?(nil)
                self.capturaCompletion = nil
            }
            return
        }

        Task { @MainActor in
            // Corregir orientación si es cámara frontal
            let imagenCorregida: UIImage
            if self.currentCamera == .frontal {
                imagenCorregida = imagen.withHorizontallyFlippedOrientation()
            } else {
                imagenCorregida = imagen
            }

            self.fotoCapturada = imagenCorregida
            self.capturaCompletion?(imagenCorregida)
            self.capturaCompletion = nil
        }
    }
}

// MARK: - UIImage Extension

extension UIImage {
    nonisolated func withHorizontallyFlippedOrientation() -> UIImage {
        guard let cgImage = self.cgImage else { return self }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .leftMirrored)
    }
}

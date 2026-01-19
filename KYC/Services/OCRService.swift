//
//  OCRService.swift
//  KYC
//

import Vision
import UIKit

actor OCRService {

    // MARK: - Extracción de texto completo

    func extraerTexto(de imagen: UIImage) async throws -> String {
        guard let cgImage = imagen.cgImage else {
            throw OCRError.imagenInvalida
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["es-MX", "es", "en"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try handler.perform([request])

                guard let observations = request.results else {
                    continuation.resume(returning: "")
                    return
                }

                let texto = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                continuation.resume(returning: texto)
            } catch {
                continuation.resume(throwing: OCRError.errorProcesamiento(error))
            }
        }
    }

    // MARK: - Extracción de datos del frente de INE

    func extraerDatosFrente(de imagen: UIImage) async throws -> DatosINEFrente {
        let textoCompleto = try await extraerTexto(de: imagen)
        let lineas = textoCompleto.components(separatedBy: "\n")

        var datos = DatosINEFrente()

        // Buscar CURP (18 caracteres alfanuméricos con formato específico)
        if let curp = extraerCURP(de: textoCompleto) {
            datos.curp = curp
            datos.fechaNacimiento = extraerFechaNacimientoDeCURP(curp)
            datos.sexo = extraerSexoDeCURP(curp)
            datos.estado = extraerEstadoDeCURP(curp)
        }

        // Buscar clave de elector
        if let clave = extraerClaveElector(de: textoCompleto) {
            datos.claveElector = clave
        }

        // Buscar sección
        if let seccion = extraerSeccion(de: textoCompleto) {
            datos.seccion = seccion
        }

        // Buscar vigencia
        if let vigencia = extraerVigencia(de: textoCompleto) {
            datos.vigencia = vigencia
        }

        // Buscar nombre (generalmente en las primeras líneas, después de ciertos marcadores)
        datos.nombreCompleto = extraerNombre(de: lineas)

        // Buscar domicilio
        datos.domicilio = extraerDomicilio(de: lineas)

        return datos
    }

    // MARK: - Extracción de datos del reverso de INE

    func extraerDatosReverso(de imagen: UIImage) async throws -> DatosINEReverso {
        let textoCompleto = try await extraerTexto(de: imagen)

        var datos = DatosINEReverso()

        // El reverso también tiene CURP y clave de elector
        if let curp = extraerCURP(de: textoCompleto) {
            datos.curp = curp
        }

        if let clave = extraerClaveElector(de: textoCompleto) {
            datos.claveElector = clave
        }

        // Número de emisión (si es visible)
        if let emision = extraerNumeroEmision(de: textoCompleto) {
            datos.numeroEmision = emision
        }

        return datos
    }

    // MARK: - Patrones de extracción

    private func extraerCURP(de texto: String) -> String? {
        // Patrón CURP: 4 letras + 6 números + 1 letra + 5 letras + 2 alfanuméricos
        // Ejemplo: GARC850101HDFRRL09
        let patron = "[A-Z]{4}[0-9]{6}[HM][A-Z]{5}[A-Z0-9]{2}"

        guard let regex = try? NSRegularExpression(pattern: patron, options: []) else {
            return nil
        }

        let textoLimpio = texto.uppercased().replacingOccurrences(of: " ", with: "")
        let rango = NSRange(textoLimpio.startIndex..., in: textoLimpio)

        if let match = regex.firstMatch(in: textoLimpio, options: [], range: rango) {
            if let range = Range(match.range, in: textoLimpio) {
                return String(textoLimpio[range])
            }
        }

        return nil
    }

    private func extraerClaveElector(de texto: String) -> String? {
        // Clave de elector: 18 caracteres alfanuméricos
        // Patrón típico: letras + números
        let patron = "[A-Z]{6}[0-9]{8}[A-Z][0-9]{3}"

        guard let regex = try? NSRegularExpression(pattern: patron, options: []) else {
            return nil
        }

        let textoLimpio = texto.uppercased().replacingOccurrences(of: " ", with: "")
        let rango = NSRange(textoLimpio.startIndex..., in: textoLimpio)

        if let match = regex.firstMatch(in: textoLimpio, options: [], range: rango) {
            if let range = Range(match.range, in: textoLimpio) {
                return String(textoLimpio[range])
            }
        }

        return nil
    }

    private func extraerSeccion(de texto: String) -> String? {
        // Buscar "SECCIÓN" o "SECCION" seguido de 4 dígitos
        let patrones = ["SECCI[OÓ]N\\s*([0-9]{4})", "SEC\\s*([0-9]{4})"]

        for patron in patrones {
            guard let regex = try? NSRegularExpression(pattern: patron, options: .caseInsensitive) else {
                continue
            }

            let rango = NSRange(texto.startIndex..., in: texto)
            if let match = regex.firstMatch(in: texto, options: [], range: rango) {
                if match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: texto) {
                    return String(texto[range])
                }
            }
        }

        return nil
    }

    private func extraerVigencia(de texto: String) -> String? {
        // Buscar "VIGENCIA" seguido de 4 dígitos (año)
        let patron = "VIGENCIA\\s*([0-9]{4})"

        guard let regex = try? NSRegularExpression(pattern: patron, options: .caseInsensitive) else {
            return nil
        }

        let rango = NSRange(texto.startIndex..., in: texto)
        if let match = regex.firstMatch(in: texto, options: [], range: rango) {
            if match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: texto) {
                return String(texto[range])
            }
        }

        return nil
    }

    private func extraerNombre(de lineas: [String]) -> String? {
        // El nombre generalmente está en las primeras líneas
        // Buscar líneas que parezcan nombres (solo letras y espacios, sin números)
        for linea in lineas.prefix(10) {
            let lineaLimpia = linea.trimmingCharacters(in: .whitespacesAndNewlines)

            // Ignorar líneas muy cortas o que contengan palabras clave
            if lineaLimpia.count < 5 { continue }
            if lineaLimpia.contains("INSTITUTO") { continue }
            if lineaLimpia.contains("ELECTORAL") { continue }
            if lineaLimpia.contains("CREDENCIAL") { continue }
            if lineaLimpia.contains("VOTAR") { continue }
            if lineaLimpia.contains("NOMBRE") { continue }
            if lineaLimpia.contains("DOMICILIO") { continue }

            // Verificar que sea principalmente letras
            let soloLetras = lineaLimpia.unicodeScalars.filter { CharacterSet.letters.contains($0) || $0 == " " }
            if soloLetras.count > lineaLimpia.count * 70 / 100 && lineaLimpia.count > 8 {
                // Parece un nombre
                return lineaLimpia.uppercased()
            }
        }

        return nil
    }

    private func extraerDomicilio(de lineas: [String]) -> String? {
        // El domicilio suele estar después de "DOMICILIO" o en ciertas líneas
        var encontroDomicilio = false
        var partesDomicilio: [String] = []

        for linea in lineas {
            let lineaLimpia = linea.trimmingCharacters(in: .whitespacesAndNewlines)

            if lineaLimpia.uppercased().contains("DOMICILIO") {
                encontroDomicilio = true
                continue
            }

            if encontroDomicilio && !lineaLimpia.isEmpty {
                // Terminar si encontramos otra sección
                if lineaLimpia.uppercased().contains("CLAVE") ||
                   lineaLimpia.uppercased().contains("CURP") ||
                   lineaLimpia.uppercased().contains("SECCI") {
                    break
                }

                partesDomicilio.append(lineaLimpia)

                // Máximo 3 líneas de domicilio
                if partesDomicilio.count >= 3 {
                    break
                }
            }
        }

        if partesDomicilio.isEmpty {
            return nil
        }

        return partesDomicilio.joined(separator: ", ")
    }

    private func extraerNumeroEmision(de texto: String) -> String? {
        // El número de emisión suele ser un número de 2 dígitos
        let patron = "EMISI[OÓ]N\\s*([0-9]{2})"

        guard let regex = try? NSRegularExpression(pattern: patron, options: .caseInsensitive) else {
            return nil
        }

        let rango = NSRange(texto.startIndex..., in: texto)
        if let match = regex.firstMatch(in: texto, options: [], range: rango) {
            if match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: texto) {
                return String(texto[range])
            }
        }

        return nil
    }

    // MARK: - Extracción desde CURP

    private func extraerFechaNacimientoDeCURP(_ curp: String) -> String? {
        guard curp.count == 18 else { return nil }

        let index4 = curp.index(curp.startIndex, offsetBy: 4)
        let index10 = curp.index(curp.startIndex, offsetBy: 10)
        let fechaStr = String(curp[index4..<index10])

        // Formato: AAMMDD
        guard fechaStr.count == 6,
              let aa = Int(fechaStr.prefix(2)),
              let mm = Int(fechaStr.dropFirst(2).prefix(2)),
              let dd = Int(fechaStr.suffix(2)) else {
            return nil
        }

        // Determinar siglo (asumimos 1900s para > 25, 2000s para <= 25)
        let anio = aa > 25 ? 1900 + aa : 2000 + aa

        return String(format: "%02d/%02d/%04d", dd, mm, anio)
    }

    private func extraerSexoDeCURP(_ curp: String) -> String? {
        guard curp.count == 18 else { return nil }

        let index10 = curp.index(curp.startIndex, offsetBy: 10)
        let sexoChar = curp[index10]

        switch sexoChar {
        case "H": return "Hombre"
        case "M": return "Mujer"
        default: return nil
        }
    }

    private func extraerEstadoDeCURP(_ curp: String) -> String? {
        guard curp.count == 18 else { return nil }

        let index11 = curp.index(curp.startIndex, offsetBy: 11)
        let index13 = curp.index(curp.startIndex, offsetBy: 13)
        let estadoCodigo = String(curp[index11..<index13])

        let estados: [String: String] = [
            "AS": "Aguascalientes", "BC": "Baja California", "BS": "Baja California Sur",
            "CC": "Campeche", "CL": "Coahuila", "CM": "Colima", "CS": "Chiapas",
            "CH": "Chihuahua", "DF": "Ciudad de México", "DG": "Durango",
            "GT": "Guanajuato", "GR": "Guerrero", "HG": "Hidalgo", "JC": "Jalisco",
            "MC": "México", "MN": "Michoacán", "MS": "Morelos", "NT": "Nayarit",
            "NL": "Nuevo León", "OC": "Oaxaca", "PL": "Puebla", "QT": "Querétaro",
            "QR": "Quintana Roo", "SP": "San Luis Potosí", "SL": "Sinaloa",
            "SR": "Sonora", "TC": "Tabasco", "TS": "Tamaulipas", "TL": "Tlaxcala",
            "VZ": "Veracruz", "YN": "Yucatán", "ZS": "Zacatecas", "NE": "Nacido en el Extranjero"
        ]

        return estados[estadoCodigo]
    }
}

// MARK: - Errores

enum OCRError: Error {
    case imagenInvalida
    case errorProcesamiento(Error)
    case sinResultados
}

// MARK: - Validación

struct ValidacionService {

    static func validarFormatoCURP(_ curp: String) -> Bool {
        let patron = "^[A-Z]{4}[0-9]{6}[HM][A-Z]{5}[A-Z0-9]{2}$"
        guard let regex = try? NSRegularExpression(pattern: patron) else { return false }
        let rango = NSRange(curp.startIndex..., in: curp)
        return regex.firstMatch(in: curp, options: [], range: rango) != nil
    }

    static func validarFormatoClaveElector(_ clave: String) -> Bool {
        // 18 caracteres alfanuméricos
        let patron = "^[A-Z]{6}[0-9]{8}[A-Z][0-9]{3}$"
        guard let regex = try? NSRegularExpression(pattern: patron) else { return false }
        let rango = NSRange(clave.startIndex..., in: clave)
        return regex.firstMatch(in: clave, options: [], range: rango) != nil
    }

    static func compararDatosINE(frente: DatosINEFrente, reverso: DatosINEReverso) -> ResultadoValidacionINE {
        var curpCoincide = true
        var claveCoincide = true

        // Comparar CURP si ambos tienen
        if let curpFrente = frente.curp, let curpReverso = reverso.curp {
            curpCoincide = curpFrente == curpReverso
        }

        // Comparar clave de elector si ambos tienen
        if let claveFrente = frente.claveElector, let claveReverso = reverso.claveElector {
            claveCoincide = claveFrente == claveReverso
        }

        let esValida = curpCoincide && claveCoincide

        var mensajeError: String?
        if !esValida {
            var errores: [String] = []
            if !curpCoincide { errores.append("CURP no coincide entre frente y reverso") }
            if !claveCoincide { errores.append("Clave de elector no coincide entre frente y reverso") }
            mensajeError = errores.joined(separator: ". ")
        }

        return ResultadoValidacionINE(
            curpCoincide: curpCoincide,
            claveElectorCoincide: claveCoincide,
            esValida: esValida,
            mensajeError: mensajeError
        )
    }
}

//
//  DatosINE.swift
//  KYC
//

import Foundation

struct DatosINEFrente: Equatable, Sendable {
    var nombreCompleto: String?
    var domicilio: String?
    var curp: String?
    var claveElector: String?
    var fechaNacimiento: String?
    var sexo: String?
    var estado: String?
    var seccion: String?
    var vigencia: String?

    nonisolated init(
        nombreCompleto: String? = nil,
        domicilio: String? = nil,
        curp: String? = nil,
        claveElector: String? = nil,
        fechaNacimiento: String? = nil,
        sexo: String? = nil,
        estado: String? = nil,
        seccion: String? = nil,
        vigencia: String? = nil
    ) {
        self.nombreCompleto = nombreCompleto
        self.domicilio = domicilio
        self.curp = curp
        self.claveElector = claveElector
        self.fechaNacimiento = fechaNacimiento
        self.sexo = sexo
        self.estado = estado
        self.seccion = seccion
        self.vigencia = vigencia
    }
}

struct DatosINEReverso: Equatable, Sendable {
    var curp: String?
    var claveElector: String?
    var numeroEmision: String?

    nonisolated init(
        curp: String? = nil,
        claveElector: String? = nil,
        numeroEmision: String? = nil
    ) {
        self.curp = curp
        self.claveElector = claveElector
        self.numeroEmision = numeroEmision
    }
}

struct ResultadoValidacionINE: Equatable, Sendable {
    var curpCoincide: Bool
    var claveElectorCoincide: Bool
    var esValida: Bool
    var mensajeError: String?

    var descripcion: String {
        if esValida {
            return "Los datos del frente y reverso coinciden"
        } else {
            var errores: [String] = []
            if !curpCoincide {
                errores.append("CURP no coincide")
            }
            if !claveElectorCoincide {
                errores.append("Clave de elector no coincide")
            }
            return errores.joined(separator: ", ")
        }
    }
}

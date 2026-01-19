//
//  ResultadoVerificacion.swift
//  KYC
//

import Foundation

enum NivelConfianza: String, Sendable {
    case alta = "Alta"
    case media = "Media"
    case baja = "Baja"
    case fallida = "Fallida"
}

struct ResultadoVerificacion: Sendable {
    var esCoincidencia: Bool
    var confianza: NivelConfianza
    var puntuacionINEvsCercana: Float
    var puntuacionINEvsLejana: Float
    var puntuacionCercanavsLejana: Float
    var datosPersona: DatosINEFrente?
    var mensajeResultado: String

    var puntuacionPromedio: Float {
        (puntuacionINEvsCercana + puntuacionINEvsLejana) / 2.0
    }

    nonisolated static func determinar(
        ineVsCercana: Float,
        ineVsLejana: Float,
        cercanaVsLejana: Float,
        datosPersona: DatosINEFrente?
    ) -> ResultadoVerificacion {
        let promedioINE = (ineVsCercana + ineVsLejana) / 2.0

        // Las selfies entre sí deben ser muy similares (misma persona, mismo momento)
        let selfiesConsistentes = cercanaVsLejana > 0.70

        let (esMatch, confianza, mensaje): (Bool, NivelConfianza, String)

        if !selfiesConsistentes {
            esMatch = false
            confianza = .fallida
            mensaje = "Las selfies no parecen ser de la misma persona"
        } else if promedioINE > 0.75 {
            esMatch = true
            confianza = .alta
            mensaje = "Alta coincidencia con la fotografía de la INE"
        } else if promedioINE > 0.60 {
            esMatch = true
            confianza = .media
            mensaje = "Coincidencia moderada con la fotografía de la INE"
        } else if promedioINE > 0.50 {
            esMatch = false
            confianza = .baja
            mensaje = "Baja coincidencia - posible que no sea la misma persona"
        } else {
            esMatch = false
            confianza = .fallida
            mensaje = "No hay coincidencia con la fotografía de la INE"
        }

        return ResultadoVerificacion(
            esCoincidencia: esMatch,
            confianza: confianza,
            puntuacionINEvsCercana: ineVsCercana,
            puntuacionINEvsLejana: ineVsLejana,
            puntuacionCercanavsLejana: cercanaVsLejana,
            datosPersona: datosPersona,
            mensajeResultado: mensaje
        )
    }
}

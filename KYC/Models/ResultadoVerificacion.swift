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
        // Convertir a porcentajes (solo las comparaciones INE vs selfies)
        let porcINEvsCercana = ineVsCercana * 100
        let porcINEvsLejana = ineVsLejana * 100

        // Si CUALQUIER puntuación INE es menor a 60%, es fallida (roja)
        let algunaRoja = porcINEvsCercana < 60 || porcINEvsLejana < 60

        let promedioINE = (porcINEvsCercana + porcINEvsLejana) / 2.0

        let (esMatch, confianza, mensaje): (Bool, NivelConfianza, String)

        if algunaRoja {
            // Cualquier puntuación < 60%: Roja - Fallida
            esMatch = false
            confianza = .fallida
            mensaje = "No hay coincidencia suficiente entre las imágenes"
        } else if promedioINE >= 70 {
            // 70-100%: Verde - Alta confianza
            esMatch = true
            confianza = .alta
            mensaje = "Alta coincidencia con la fotografía de la INE"
        } else {
            // 60-69%: Amarilla - Media confianza
            esMatch = true
            confianza = .media
            mensaje = "Coincidencia moderada con la fotografía de la INE"
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

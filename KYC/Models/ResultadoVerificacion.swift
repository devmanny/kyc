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

    /// Determina el resultado usando umbrales optimizados para ArcFace (deep learning)
    /// ArcFace es mucho más discriminativo, por lo que los umbrales son diferentes
    nonisolated static func determinarArcFace(
        ineVsCercana: Float,
        ineVsLejana: Float,
        cercanaVsLejana: Float,
        datosPersona: DatosINEFrente?
    ) -> ResultadoVerificacion {
        // Para ArcFace, las similitudes ya están normalizadas 0-1
        // Umbrales más estrictos porque ArcFace es más discriminativo
        let porcINEvsCercana = ineVsCercana * 100
        let porcINEvsLejana = ineVsLejana * 100
        let porcSelfies = cercanaVsLejana * 100

        // Las dos selfies deben ser muy similares (misma persona, misma sesión)
        // Si las selfies no coinciden entre sí, algo está mal
        let selfiesCoinciden = porcSelfies >= 70

        // Umbrales para ArcFace:
        // < 50%: Definitivamente no es la misma persona (ROJO)
        // 50-65%: Posible match pero baja confianza (AMARILLO)
        // >= 65%: Alta confianza de match (VERDE)
        let algunaRoja = porcINEvsCercana < 50 || porcINEvsLejana < 50
        let promedioINE = (porcINEvsCercana + porcINEvsLejana) / 2.0

        let (esMatch, confianza, mensaje): (Bool, NivelConfianza, String)

        if !selfiesCoinciden {
            // Las selfies no coinciden entre sí - algo está mal
            esMatch = false
            confianza = .fallida
            mensaje = "Las selfies no parecen ser de la misma persona. Por favor, repite la verificación."
        } else if algunaRoja {
            // Alguna comparación con INE está por debajo del umbral mínimo
            esMatch = false
            confianza = .fallida
            mensaje = "El rostro de las selfies no coincide con la fotografía de la INE"
        } else if promedioINE >= 65 {
            // Alta coincidencia
            esMatch = true
            confianza = .alta
            mensaje = "Alta coincidencia verificada con la fotografía de la INE"
        } else {
            // Coincidencia moderada (50-65%)
            esMatch = true
            confianza = .media
            mensaje = "Coincidencia moderada con la fotografía de la INE. Se recomienda verificación adicional."
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

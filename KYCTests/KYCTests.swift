//
//  KYCTests.swift
//  KYCTests
//
//  Tests para servicios críticos de KYC
//

import Testing
import UIKit
@testable import KYC

// MARK: - Validación Service Tests

struct ValidacionServiceTests {

    @Test func validarFormatoCURP_valido() {
        // CURP válido: 4 letras + 6 números + H/M + 2 letras estado + 3 consonantes + 2 alfanuméricos
        let curpValido = "GARC850101HDFRRL09"
        #expect(ValidacionService.validarFormatoCURP(curpValido) == true)
    }

    @Test func validarFormatoCURP_invalido_longitudIncorrecta() {
        let curpCorto = "GARC850101"
        #expect(ValidacionService.validarFormatoCURP(curpCorto) == false)
    }

    @Test func validarFormatoCURP_invalido_formatoIncorrecto() {
        let curpInvalido = "12345678901234567A"
        #expect(ValidacionService.validarFormatoCURP(curpInvalido) == false)
    }

    @Test func validarFormatoCURP_invalido_sexoIncorrecto() {
        // X en lugar de H/M en posición 10
        let curpInvalido = "GARC850101XDFRRL09"
        #expect(ValidacionService.validarFormatoCURP(curpInvalido) == false)
    }

    @Test func validarFormatoClaveElector_valido() {
        // Clave de elector: 6 letras + 8 números + 1 letra + 3 números
        let claveValida = "GRCRRL85010100H100"
        #expect(ValidacionService.validarFormatoClaveElector(claveValida) == true)
    }

    @Test func validarFormatoClaveElector_invalido() {
        let claveInvalida = "123456789012345678"
        #expect(ValidacionService.validarFormatoClaveElector(claveInvalida) == false)
    }

    @Test func compararDatosINE_coinciden() {
        let frente = DatosINEFrente(
            nombreCompleto: "JUAN GARCIA RODRIGUEZ",
            curp: "GARC850101HDFRRL09",
            claveElector: "GRCRRL85010100H100"
        )
        let reverso = DatosINEReverso(
            curp: "GARC850101HDFRRL09",
            claveElector: "GRCRRL85010100H100"
        )

        let resultado = ValidacionService.compararDatosINE(frente: frente, reverso: reverso)

        #expect(resultado.esValida == true)
        #expect(resultado.curpCoincide == true)
        #expect(resultado.claveElectorCoincide == true)
        #expect(resultado.mensajeError == nil)
    }

    @Test func compararDatosINE_curpNoCoincide() {
        let frente = DatosINEFrente(
            curp: "GARC850101HDFRRL09",
            claveElector: "GRCRRL85010100H100"
        )
        let reverso = DatosINEReverso(
            curp: "OTRO850101HDFRRL09",  // CURP diferente
            claveElector: "GRCRRL85010100H100"
        )

        let resultado = ValidacionService.compararDatosINE(frente: frente, reverso: reverso)

        #expect(resultado.esValida == false)
        #expect(resultado.curpCoincide == false)
        #expect(resultado.claveElectorCoincide == true)
    }

    @Test func compararDatosINE_claveNoCoincide() {
        let frente = DatosINEFrente(
            curp: "GARC850101HDFRRL09",
            claveElector: "GRCRRL85010100H100"
        )
        let reverso = DatosINEReverso(
            curp: "GARC850101HDFRRL09",
            claveElector: "OTRACL85010100H100"  // Clave diferente
        )

        let resultado = ValidacionService.compararDatosINE(frente: frente, reverso: reverso)

        #expect(resultado.esValida == false)
        #expect(resultado.curpCoincide == true)
        #expect(resultado.claveElectorCoincide == false)
    }
}

// MARK: - Datos INE Tests

struct DatosINETests {

    @Test func datosINEFrente_inicializacionVacia() {
        let datos = DatosINEFrente()

        #expect(datos.nombreCompleto == nil)
        #expect(datos.curp == nil)
        #expect(datos.claveElector == nil)
        #expect(datos.fechaNacimiento == nil)
    }

    @Test func datosINEFrente_inicializacionConValores() {
        let datos = DatosINEFrente(
            nombreCompleto: "JUAN PEREZ",
            curp: "PEGJ850101HDFRRL09",
            claveElector: "GRCRRL85010100H100",
            fechaNacimiento: "01/01/1985",
            sexo: "Hombre",
            estado: "Ciudad de México"
        )

        #expect(datos.nombreCompleto == "JUAN PEREZ")
        #expect(datos.curp == "PEGJ850101HDFRRL09")
        #expect(datos.sexo == "Hombre")
    }

    @Test func resultadoValidacionINE_descripcion_valida() {
        let resultado = ResultadoValidacionINE(
            curpCoincide: true,
            claveElectorCoincide: true,
            esValida: true,
            mensajeError: nil
        )

        #expect(resultado.descripcion == "Los datos del frente y reverso coinciden")
    }

    @Test func resultadoValidacionINE_descripcion_curpNoCoincide() {
        let resultado = ResultadoValidacionINE(
            curpCoincide: false,
            claveElectorCoincide: true,
            esValida: false,
            mensajeError: nil
        )

        #expect(resultado.descripcion.contains("CURP no coincide"))
    }
}

// MARK: - Resultado Verificacion Tests

struct ResultadoVerificacionTests {

    @Test func determinar_altaConfianza() {
        let resultado = ResultadoVerificacion.determinar(
            ineVsCercana: 0.85,
            ineVsLejana: 0.82,
            cercanaVsLejana: 0.95,
            datosPersona: nil
        )

        #expect(resultado.esCoincidencia == true)
        #expect(resultado.confianza == .alta)
    }

    @Test func determinar_mediaConfianza() {
        let resultado = ResultadoVerificacion.determinar(
            ineVsCercana: 0.68,
            ineVsLejana: 0.65,
            cercanaVsLejana: 0.90,
            datosPersona: nil
        )

        #expect(resultado.esCoincidencia == true)
        #expect(resultado.confianza == .media)
    }

    @Test func determinar_bajaConfianza() {
        let resultado = ResultadoVerificacion.determinar(
            ineVsCercana: 0.55,
            ineVsLejana: 0.52,
            cercanaVsLejana: 0.85,
            datosPersona: nil
        )

        #expect(resultado.esCoincidencia == false)
        #expect(resultado.confianza == .baja)
    }

    @Test func determinar_fallida_selfiesInconsistentes() {
        let resultado = ResultadoVerificacion.determinar(
            ineVsCercana: 0.80,
            ineVsLejana: 0.78,
            cercanaVsLejana: 0.40,  // Selfies no consistentes
            datosPersona: nil
        )

        #expect(resultado.esCoincidencia == false)
        #expect(resultado.confianza == .fallida)
        #expect(resultado.mensajeResultado.contains("selfies"))
    }

    @Test func determinar_fallida_noCoincidencia() {
        let resultado = ResultadoVerificacion.determinar(
            ineVsCercana: 0.30,
            ineVsLejana: 0.25,
            cercanaVsLejana: 0.90,
            datosPersona: nil
        )

        #expect(resultado.esCoincidencia == false)
        #expect(resultado.confianza == .fallida)
    }

    @Test func puntuacionPromedio_calculaCorrectamente() {
        let resultado = ResultadoVerificacion(
            esCoincidencia: true,
            confianza: .alta,
            puntuacionINEvsCercana: 0.80,
            puntuacionINEvsLejana: 0.70,
            puntuacionCercanavsLejana: 0.90,
            datosPersona: nil,
            mensajeResultado: "Test"
        )

        #expect(resultado.puntuacionPromedio == 0.75)
    }
}

// MARK: - Glass Effect Style Tests

struct GlassEffectStyleTests {

    @Test func regular_noTieneTint() {
        let style = GlassEffectStyle.regular

        #expect(style.tintColor == nil)
        #expect(style.isInteractive == false)
    }

    @Test func tint_agregaColor() {
        let style = GlassEffectStyle.regular.tint(.blue)

        #expect(style.tintColor == .blue)
    }

    @Test func interactive_activaInteractividad() {
        let style = GlassEffectStyle.regular.interactive()

        #expect(style.isInteractive == true)
    }

    @Test func chainedModifiers_funcionan() {
        let style = GlassEffectStyle.regular
            .tint(.red.opacity(0.5))
            .interactive()

        #expect(style.tintColor != nil)
        #expect(style.isInteractive == true)
    }
}

// MARK: - Liveness Challenge Tests

struct LivenessChallengeTests {

    @Test func blink_tieneInstruccionCorrecta() {
        let challenge = LivenessChallenge.blink
        #expect(challenge.instruccion == "Parpadea dos veces")
    }

    @Test func turnLeft_tieneIconoCorrecto() {
        let challenge = LivenessChallenge.turnLeft
        #expect(challenge.icono == "arrow.left")
    }

    @Test func allCases_tieneTodasLasOpciones() {
        let casos = LivenessChallenge.allCases
        #expect(casos.count == 4)
        #expect(casos.contains(.blink))
        #expect(casos.contains(.turnLeft))
        #expect(casos.contains(.turnRight))
        #expect(casos.contains(.smile))
    }
}

// MARK: - Face State Tests

struct FaceStateTests {

    @Test func isBlinking_cuandoOjosCerrados() {
        var state = FaceState()
        state.leftEyeOpenness = 0.1
        state.rightEyeOpenness = 0.2

        #expect(state.isBlinking == true)
    }

    @Test func isBlinking_cuandoOjosAbiertos() {
        var state = FaceState()
        state.leftEyeOpenness = 0.9
        state.rightEyeOpenness = 0.85

        #expect(state.isBlinking == false)
    }

    @Test func isTurnedLeft_cuandoYawNegativo() {
        var state = FaceState()
        state.yaw = -0.5

        #expect(state.isTurnedLeft == true)
        #expect(state.isTurnedRight == false)
    }

    @Test func isTurnedRight_cuandoYawPositivo() {
        var state = FaceState()
        state.yaw = 0.5

        #expect(state.isTurnedLeft == false)
        #expect(state.isTurnedRight == true)
    }

    @Test func isSmiling_cuandoSmileAmountAlto() {
        var state = FaceState()
        state.smileAmount = 0.7

        #expect(state.isSmiling == true)
    }
}

// MARK: - Liveness Result Tests

struct LivenessResultTests {

    @Test func passed_esAlive() {
        let result = LivenessResult.passed

        #expect(result.isAlive == true)
        #expect(result.confidence == 1.0)
        #expect(result.failureReason == nil)
    }

    @Test func failed_noEsAlive() {
        let result = LivenessResult.failed("Timeout")

        #expect(result.isAlive == false)
        #expect(result.confidence == 0)
        #expect(result.failureReason == "Timeout")
    }
}

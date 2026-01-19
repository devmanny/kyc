//
//  EstadoFlujo.swift
//  KYC
//

import Foundation

enum EstadoFlujo: Equatable {
    case inicio
    case capturandoFrenteINE
    case capturandoReversoINE
    case procesandoINE
    case livenessCheck(LivenessChallenge)  // Challenge de liveness antes de selfies
    case capturandoSelfieCercana
    case capturandoSelfieLejana
    case verificando
    case resultado
}

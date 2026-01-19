//
//  Selfie.swift
//  KYC
//

import UIKit

enum TipoSelfie {
    case cercana
    case lejana
}

struct Selfie {
    var imagen: UIImage?
    var imagenRostro: UIImage?
    var tipo: TipoSelfie
    var timestamp: Date = Date()
    var livenessVerificado: Bool = false
}

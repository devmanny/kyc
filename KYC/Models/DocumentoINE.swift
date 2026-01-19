//
//  DocumentoINE.swift
//  KYC
//

import UIKit

struct DocumentoINE {
    var imagenFrente: UIImage?
    var imagenReverso: UIImage?
    var imagenRostro: UIImage?
    var datosFrente: DatosINEFrente?
    var datosReverso: DatosINEReverso?
    var validacion: ResultadoValidacionINE?
    // embeddingRostro eliminado - los embeddings se generan on-demand en FaceEmbeddingService
}

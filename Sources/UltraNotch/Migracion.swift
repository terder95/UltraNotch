import Foundation

// MARK: - Migración desde "Isla" (el nombre anterior de UltraNotch)
//
// Antes la app se llamaba Isla (bundle com.mexicomakers.islamm, datos en
// ~/Library/Application Support/IslaMM). La primera vez que abre UltraNotch copia
// esos ajustes y datos al lugar nuevo, sin pisar nada que ya exista, y deja una
// marca para no repetirlo. Los nombres viejos aparecen aquí a propósito.

enum MigracionDesdeIsla {
    /// Dominio de ajustes de la versión anterior.
    static let dominioViejo = "com.mexicomakers.islamm"
    /// Carpeta de datos de la versión anterior (en Application Support).
    static let carpetaVieja = "IslaMM"
    /// Marca en los ajustes nuevos: ya se migró (o no había nada que migrar).
    static let marca = "migracionDesdeIslaHecha"

    /// Archivos de la sesión anterior que no tiene caso copiar.
    private static func esTemporal(_ nombre: String) -> Bool {
        nombre.hasPrefix("cierre-limpio") || nombre.hasPrefix("inicio-") || nombre.hasSuffix(".sock")
    }

    static func correrSiHaceFalta() {
        // Solo como app instalada (con bundle); nunca en los modos sin interfaz.
        guard let dominioNuevo = Bundle.main.bundleIdentifier, dominioNuevo != dominioViejo else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: marca) else { return }

        migrarAjustes(dominioNuevo: dominioNuevo, defaults: defaults)
        migrarCarpeta()

        defaults.set(true, forKey: marca)
    }

    /// Copia cada ajuste viejo que no exista ya en el dominio nuevo.
    private static func migrarAjustes(dominioNuevo: String, defaults: UserDefaults) {
        guard let viejos = defaults.persistentDomain(forName: dominioViejo), !viejos.isEmpty else { return }
        let actuales = defaults.persistentDomain(forName: dominioNuevo) ?? [:]
        var copiados = 0
        for (clave, valor) in viejos where actuales[clave] == nil && !clave.hasPrefix("NS") {
            defaults.set(valor, forKey: clave)
            copiados += 1
        }
        if copiados > 0 {
            NSLog("UltraNotch: copié \(copiados) ajustes de la versión anterior (Isla).")
        }
    }

    /// Copia ~/Library/Application Support/IslaMM → .../UltraNotch (sin pisar lo que ya exista).
    private static func migrarCarpeta() {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let vieja = base.appendingPathComponent(carpetaVieja, isDirectory: true)
        let nueva = AppPaths.support
        guard fileManager.fileExists(atPath: vieja.path),
              let nombres = try? fileManager.contentsOfDirectory(atPath: vieja.path) else { return }

        for nombre in nombres where !esTemporal(nombre) {
            let destino = nueva.appendingPathComponent(nombre)
            guard !fileManager.fileExists(atPath: destino.path) else { continue }
            do {
                try fileManager.copyItem(at: vieja.appendingPathComponent(nombre), to: destino)
            } catch {
                NSLog("UltraNotch: no pude copiar \(nombre) de la versión anterior: \(error.localizedDescription)")
            }
        }

        // El estante guarda rutas completas a los archivos que soltaste ("Soltados"): que
        // apunten a la carpeta nueva (vienen como "Application Support" o "Application%20Support").
        let estante = nueva.appendingPathComponent("estante.json")
        if var texto = try? String(contentsOf: estante, encoding: .utf8) {
            let original = texto
            texto = texto
                .replacingOccurrences(of: "Support/\(carpetaVieja)/",
                                      with: "Support/\(nueva.lastPathComponent)/")
                .replacingOccurrences(of: "Support\\/\(carpetaVieja)\\/",
                                      with: "Support\\/\(nueva.lastPathComponent)\\/")
            if texto != original {
                try? texto.write(to: estante, atomically: true, encoding: .utf8)
            }
        }
    }
}

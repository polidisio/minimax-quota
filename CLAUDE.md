# MiniMax Quota Menu Bar App — Proyecto

## Objetivo

App de menú bar para macOS que monitorea y muestra el % de quota restante de MiniMax en tiempo real.

## Comando para consultar quota

```bash
mmx quota show --output json
```

**Output relevante** — modelo `MiniMax-M*`:
```json
{
  "model_remains": [
    {
      "model_name": "MiniMax-M*",
      "current_interval_total_count": 1500,
      "current_interval_usage_count": 293
    }
  ]
}
```

**Cálculo:** `pctRemaining = 100 - (usage / total * 100)`

## Stack

- **Swift 5.9+** con **AppKit** (100% nativo, sin dependencias externas)
- Xcode project generado con `xcodebuild`

## Requisitos de la app

1. **No aparece en el Dock** — `LSUIElement = true` en Info.plist
2. **Menú bar**: `80% ↓` con color dinámico
   - 🟢 Verde: >50% restante
   - 🟡 Amarillo: 20-50% restante
   - 🔴 Rojo: <20% restante
3. **Tooltip**: `MiniMax M2: 293/1500 requests (19.5% usado)`
4. **Refresco automático cada 5 minutos**
5. **Menú al click**:
   - `📊 293 / 1500 requests`
   - `📋 Copiar % al clipboard`
   - `🌐 Abrir dashboard MiniMax` → `https://platform.minimax.io/usage`
   - `🔄 Actualizar ahora`
   - `❌ Salir`
6. **Log**: `~/.hermes/logs/minimax-quota.log`
   - Formato: `[2026-05-26 18:30:00] 293/1500 | 80.5% remaining | ✓`

## Gestión de errores

- `mmx` puede estar en `/opt/homebrew/bin/mmx` o `/usr/local/bin/mmx`
- Timeout 10 segundos
- Si falla → mostrar `⚠️ Error` en el menú bar

## Estructura del proyecto

```
MiniMaxQuota/
├── Sources/
│   ├── main.swift              # NSApplication.shared.run()
│   ├── AppDelegate.swift       # NSApplicationDelegate
│   ├── StatusBarController.swift  # Menú bar
│   ├── QuotaService.swift      # Parseo mmx + lógica
│   └── Logger.swift            # Logging
├── Resources/
│   └── Info.plist             # LSUIElement = true
└── MiniMaxQuota.xcodeproj/
```

## Build

```bash
xcodebuild -project MiniMaxQuota.xcodeproj -scheme MiniMaxQuota -configuration Release build
```

Output: `build/Release/MiniMaxQuota.app`

## NO incluir en commit

- API keys, tokens, credenciales
- Archivos de cache (`*.xcuserdatad`, `DerivedData`)
- Archivos `.env`

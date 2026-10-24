# SepCheck

Native macOS-App (SwiftUI, macOS 14+) zur Druckdaten-Kontrolle: PDF öffnen, CMYK-Auszüge
und Sonderfarben einzeln ansehen, Gesamtfarbauftrag messen und Überschreitungen markieren.

## Architektur
- Separation übernimmt **Ghostscript** (`tiffsep`-Device) als externer Prozess – berücksichtigt Überdrucken wie ein RIP.
  Gesucht in `/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin`, `/usr/bin`.
- `Sources/SepCheck/Ghostscript.swift` – Rendern, TIFF-Auszüge laden (invertiert: 255 = 100 % Farbe),
  Sonderfarben-CMYK aus `%%SeparationColor`-Ausgabe (`-dPrintSpotCMYK`), Gesamtfarbauftrag, RGB-Komposit (multiplikativ).
- `DocumentModel.swift` – Zustand (`@MainActor ObservableObject`): Seite, dpi, sichtbare Kanäle, TAC-Limit, Hover-Werte.
- `ContentView.swift` – Seitenleiste (Kanäle, Steuerung) + Arbeitsfläche (Zoom, Hover-Messung).
- `SepCheckApp.swift` – App-Einstieg, Menüs/Tastenkürzel, Öffnen aus dem Finder über `AppDelegate`.

## Bauen
- `swift build` zum Testen (ohne `.lproj`, also englisch), `./build-app.sh` erzeugt das signierte (ad hoc) `SepCheck.app` inkl. Icon.
- Icons: `Resources/icon-1024.png` (ab 128 px), `Resources/icon-small.png` (bis 64 px).
- Keine Sandbox (wird für den Ghostscript-Aufruf gebraucht).

## Konventionen
- Kommentare auf Deutsch.
- UI-Texte: englische Schlüssel im Code (`Text("…")`, außerhalb von SwiftUI `String(localized:)`),
  deutsche Übersetzung in `Resources/de.lproj/Localizable.strings` – neue Texte immer dort mitpflegen.
- README.md englisch, README.de.md deutsch – beide aktuell halten.

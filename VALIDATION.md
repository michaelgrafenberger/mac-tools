# Prüfstand · 18. November 2026

## Erfolgreich geprüft

- Alle fünf Apps als eigenständige App-Bundles für Apple Silicon gebaut, lokal ad hoc signiert und mit `codesign --verify --strict` geprüft.
- Alle fünf Apps zusätzlich für Intel (`x86_64`) kompiliert. Diese Builds wurden nicht auf einem Intel-Mac ausgeführt.
- Deklariertes Mindestziel macOS 13. Der verwendete Mac läuft auf macOS 26.4.1; Compiler: Apple Swift 6.3.3 im Swift-5-Sprachmodus.
- 480 ausführbare Logikprüfungen: Badge-Zahlen und Untergrenzen, Text- und Punkt-Badges, Parsing von `lsappinfo`, Geschwindigkeitsformatierung, Einheitenwechsel, 64-Bit-Zähler, tatsächliche Messintervalle, Sleep-/Reset-Fälle sowie nicht überlappende Layouts auf primären und versetzten/hochformatigen Displays.
- 30 zusätzliche RAM-Prüfungen: Speicherformatierung und -aufteilung, Helfer-Gruppierung, Live-Speicher- und Prozessmessung, absteigende Sortierung, Ausschluss eigener/fremder Prozesse sowie Ablehnung veralteter Prozesskennungen. SIGTERM und SIGKILL ausschließlich an eigens gestarteten sleep-Kindprozessen geprüft; keine persönlichen Apps beendet.
- Die „MAC TOOLS / 01–04“-Sammlungsmarke wurde aus allen App-Oberflächen entfernt.
- Live-Lesen der Kernel-Netzwerkzähler: fünf unterstützte aktive Interfaces in dieser Umgebung verfügbar. Keine künstlichen Downloads oder Uploads erzeugt.
- Native Integration: eigens erzeugten Dock-Badge `99+` mit eindeutigem PID-Bezug gelesen. Test-App und ihre eigenen Fenster anschließend beendet.
- Tatsächliche SwiftUI-Oberflächen aller fünf Apps in Light und Dark gerendert und visuell geprüft. Screenshots enthalten markierte Beispieldaten.
- Grid-Vorschau interaktiv geprüft: Layoutwechsel, Zurücksetzen alter Zuordnungen bei Layoutwechsel, gezielte Klick-Zuordnung zweier Fenster, gemeinsame Einstellungen, ausblendbares Menübar-Icon und Beenden über das gemeinsame Menü. Das Hilfsfenster blieb bei ausgeblendetem Icon erreichbar. Die Test-App wurde beendet.
- Shell-Skripte auf Syntax geprüft. Build-Skripte installieren nichts, ersetzen keine existierende Installation und beenden keine anderen Apps.

## Noch nicht praktisch geprüft

- **Grid: Bewegung und Wiederherstellung fremder Fenster.** Der native Test überspringt diesen Schritt, weil keine bereits bestehende Bedienungshilfen-Freigabe vorhanden ist. Es wurde keine neue Freigabe angefordert oder erteilt. Die API-Implementierung ist kompiliert; ihre Wirkung auf verschiedene Ziel-Apps, Mindestgrößen, Monitorwechsel und Spaces bleibt zu testen.
- Grid: Drag-and-drop-Zuordnung ist implementiert; im interaktiven Test wurde die alternative Klick-Zuordnung geprüft.
- Fokus: tatsächliche Unschärfe und Abdunklung auf mehreren Monitoren/Spaces, der private WindowServer-Pfad und das öffentliche Fallback. Die Render-Vorschau aktiviert keinen Fokus-Effekt.
- Fokus: persönliche „Fokus an“/„Fokus aus“-Kurzbefehle und ihre Wirkung auf einen schon zuvor aktiven macOS-Fokus. Die Tests starten keine persönlichen Kurzbefehle.
- RAM: reguläres Beenden einer echten GUI-App mit ungespeicherten Dokumenten und der native Bestätigungsdialog für erzwungenes Beenden. Die Signalpfade sind an eigenen Testprozessen geprüft.
- Autostart und Systemfreigaben in einer frischen Benutzerumgebung.
- Netzwerkwerte gegenüber einer unabhängigen Referenzmessung, verschiedene physische Adapter sowie reale Sleep-/Wake-Zyklen. Die Sampler-Logik für diese Fälle ist separat geprüft.
- Ältere macOS-Versionen, Intel-Laufzeit und vollständige VoiceOver-Bedienung.
- Developer-ID-Signierung, Hardened Runtime, Notarisierung, Gatekeeper-Verhalten nach echtem Internetdownload, Update-Kanal und öffentliche Veröffentlichung.

## Entwicklungsumgebung

Direkte AppKit-Starts aus einer eingeschränkten Shell-Sandbox konnten sich nicht beim grafischen macOS-System registrieren. Die anschließenden nativen UI- und Screenshot-Prüfungen liefen deshalb in der normalen grafischen Sitzung. Dies war eine Umgebungsbeschränkung; die erfolgreichen Vorschau-Starts verwenden dieselben gebauten App-Bundles.

Die Build-Bundles verwenden eigene neue Bundle-IDs. Die ursprünglich gelieferten ZIPs und vorhandenen Installationen wurden nicht verändert. Die App-Builds und Archive liegen unter Downloads/Mac-Tools-0.3.0. Die Quellcode-Sammlung wird unter github.com/michaelgrafenberger/mac-tools bereitgestellt; es gibt noch keinen stabilen oder notarisierten App-Release. Die Landingpage tools.gholding.at wurde über Lovable veröffentlicht. Die Veröffentlichung des Quellcodes unter MIT wurde am 18. November 2026 ausdrücklich freigegeben.

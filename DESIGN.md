# Gemeinsame Designsprache

## Richtung

Ruhig, präzise und nativ. Warme neutrale Flächen und ein gedämpftes Salbeigrün verbinden die fünf Apps. Die Gestaltung nimmt die Ruhe der Quest-Referenz auf, nutzt im Produkt jedoch native Mac-Schrift und vertraute Bedienelemente.

`Mac Tools` ist ein vorläufiger Sammlungsname. Die einzelnen Produkte heißen Fokus, Offen, Grid, NetSpeed und RAM. In den App-Oberflächen stehen die Produktnamen ohne zusätzliche Sammlungsmarke oder Produktnummer.

## Grundlagen

| Element | Festlegung |
| --- | --- |
| Panelbreite | 372 pt |
| Außenabstand | 24 pt |
| Große Abstände | 22 pt |
| Abstand innerhalb einer Fläche | 16 pt |
| Flächenradius | 15 pt, kontinuierlich |
| Buttonradius | 10 pt |
| Titel | SF System, 29 pt, Medium, −1 pt Laufweite |
| Fließtext | SF System, 11–12 pt |
| Abschnittslabel | 9 pt, Semibold, 1,5 pt Laufweite |
| Zahlen | Ziffern mit fester Breite; große Werte leicht gewichtet |
| Animation | Kurz, 150 ms; keine dauernden dekorativen Bewegungen |

| Farbrolle | Hell | Dunkel |
| --- | --- | --- |
| Hintergrund | `#F5F4F0` | `#202320` |
| Fläche | `#FCFBF8` | `#292D29` |
| Text | `#252C28` | `#EEF0E9` |
| Sekundärtext | `#72796F` | `#A7AEA3` |
| Linie | `#DFE2D9` | `#3D443B` |
| Akzent | `#526B59` | `#B0C8A7` |
| Akzentfläche | `#E5EADD` | `#354330` |

## Gemeinsame Anatomie

1. Ein knapper Status ohne zusätzliche Sammlungsmarke oder Produktnummer.
2. Produktname, ein kurzer Nutzen-Satz und ein einfaches Symbol.
3. Die Hauptfunktion: Fokusaktion, Badge-Übersicht, Fensterlayout, Netzwerkwerte oder Speicherübersicht.
4. Nur die unmittelbar hilfreichen Optionen.
5. Ein ruhiger Abschluss mit Tastenkürzel, Einstellungen und Beenden-Menü.

Einstellungen ersetzen den Funktionsbereich, statt das Panel weiter zu verlängern. Icons und Tastenkürzel-Einstellungen bleiben in jeder App gleich. Warnungen benennen ein konkretes Problem und werden ausschließlich im betroffenen Zustand gezeigt.

## Interaktion und Ton

- Eindeutige Verben: „Fokus starten“, „Fenster anordnen“, „Zuordnung entfernen“.
- Status beschreibt die tatsächlich verfügbare Information. Kein „Alles erledigt“ allein aufgrund fehlender Dock-Badges.
- Akzentfarbe lenkt zu einer wichtigen Aktion. Keine bunten Verläufe, Badge-Warnfarben oder dekorativen Diagramme.
- Systemschrift und native Schalter, Slider und Auswahlfelder. SF Symbols innerhalb der Apps, eigene Vektorgeometrie für die App-Icons.
- Light und Dark verwenden dieselbe Hierarchie. Icons dürfen nicht die einzige Erklärung einer wichtigen Aktion sein.
- Bedienungshilfenbeschriftungen für Icon-Buttons und Zuordnungsfelder; Fensterzuordnung funktioniert auch per Klick statt Drag-and-drop.
- Dauerhafte Sichtbarkeit ist eine Nutzerentscheidung. Eine Aktion benötigt keinen permanenten Menübar-Platz.

Die Komponenten werden von allen fünf Apps direkt aus demselben Swift-Code gebaut. Eine Änderung an einem Token oder gemeinsamen Baustein gilt dadurch für die gesamte Sammlung.

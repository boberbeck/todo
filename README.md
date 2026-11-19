# Tagwerk

Tagwerk ist der Arbeitsname einer schlanken Mac-App für Tagesplanung, Fokus und Zeiterfassung. Später bucht sie die Zeiten direkt in SAP Business ByDesign und als Worklog in ManageEngine.

Der vollständige Plan steht im Dokument „Plan: Eigene Todo-App für den Mac“.

## Stand: Phase 1 (Grundgerüst)

| Bereich | Was geht |
| --- | --- |
| Heute | Aufgaben des Tages mit erfasster und geplanter Zeit. Erledigtes bleibt abgehakt stehen. Reihenfolge per Drag-and-drop. Warnung, wenn mehr geplant ist als Zeit da ist. |
| Eingang | Noch nicht eingeplante Todos. Per Pfeil oder Drag-and-drop in den Tag holen. |
| Fokus | Eine Aufgabe groß mit Timer, Arbeitsart, PSP-Element und dem Feld „Bearbeitung“. Daneben die Done-Liste, unten die Fokuszeit des Tages. |
| Kunden | Lokale Todos pro Kunde, Farbe, Stunden im laufenden Monat. Diese Todos verlassen die App nie. |
| Rückblick | Stunden der Woche je Tag und je Kunde. |
| Menüleiste | Laufende Zeit, Stoppen, Erledigt, eine andere Aufgabe starten. |

Außerdem:

- Es läuft immer höchstens ein Timer. Ein neuer Start beendet den laufenden.
- Offene Aufgaben von gestern rutschen automatisch auf heute.
- Eine Zeitangabe am Ende des Titels wird zur Schätzung, z. B. „Angebot schreiben 1h30“ oder „Logs prüfen 45m“.

Noch nicht enthalten:

| Phase | Inhalt |
| --- | --- |
| 2 | Kalender und Tagesplanung als Ritual |
| 3 | SAP ByDesign und ManageEngine mit Tagesabschluss |
| 4 | Wochenrückblick, Wochenziele, Leerlauf-Erkennung |
| 5 | Outlook |

## Starten

Voraussetzungen: macOS 14 oder neuer und Xcode 15.3 oder neuer.

1. Repository klonen und den Branch auschecken.
2. `open Package.swift` ausführen. Xcode öffnet das Paket. Das Schema „Tagwerk“ wählen und mit ⌘R starten.
3. Alternativ im Terminal: `swift run Tagwerk`.
4. Tests laufen mit `swift test`.

Die App läuft vorerst als Swift-Paket, noch ohne signiertes App-Bundle. Für den Kalenderzugriff in Phase 2 kommt ein Xcode-Projekt mit Bundle-ID und Berechtigungstexten dazu.

## Daten

Alle Daten liegen lokal in `~/Library/Application Support/Tagwerk/tagwerk.sqlite`. Time Machine sichert die Datei mit. Die App nutzt die SQLite-Bibliothek von macOS und braucht keine Fremdpakete.

## Tastenkürzel

| Kürzel | Aktion |
| --- | --- |
| ⌘N | Neue Aufgabe |
| ⌘T | Timer der Fokus-Aufgabe starten oder stoppen |
| ⌘↩ | Fokus-Aufgabe erledigt |
| ⌘1 bis ⌘4 | Heute, Fokus, Kunden, Rückblick |
| Doppelklick auf eine Aufgabe | im Fokus öffnen |

## Aufbau

| Pfad | Inhalt |
| --- | --- |
| `Sources/TagwerkCore` | Datenmodell, Zeitlogik, Tagesplan-Regeln, SQLite-Speicher. Ohne Oberfläche und unter Linux testbar. |
| `Sources/TagwerkApp` | SwiftUI-Oberfläche, nur macOS |
| `Tests/TagwerkCoreTests` | Tests für die Kernlogik |

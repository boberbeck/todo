<p align="center"><img src="docs/logo.png" width="128" alt="Tagwerk-Logo"></p>

# Tagwerk

Tagwerk ist der Arbeitsname einer schlanken Mac-App für Tagesplanung, Fokus und Zeiterfassung. Später bucht sie die Zeiten direkt in SAP Business ByDesign und als Worklog in ManageEngine.

Der vollständige Plan steht im Dokument „Plan: Eigene Todo-App für den Mac“.

## Stand: Phase 4 plus SAP-Abgleich und Claude-Anbindung

Aufbau: dunkel und ruhig, oben die Leiste mit Start, Plan, Kalender, Fokus, Kunden und Rückblick.

| Bereich | Was geht |
| --- | --- |
| Start | Großes Datum, Stunden heute und diese Woche. Links die Aufgaben von heute (neue oben oder unten einfügen, per Ziehen sortieren), darunter die Erledigt-Liste und der Eingang. Rechts der Tageskalender, an der Kante breiter ziehbar; die Lupen machen die Stunden höher. |
| Plan | Woche planen: links der Eingang, daneben eine Spalte je Tag mit geplanter und freier Zeit. Aufgaben zieht man zwischen den Tagen hin und her. |
| Kalender | Die Woche mit Terminen, Zeitblöcken und erfasster Zeit in Kundenfarben, Stunden je Tag und gegen das Wochenziel. Doppelklick oder „Zeit nachtragen“ erfasst Arbeit nachträglich. |
| Tag planen | Geführte Planung beim ersten Öffnen am Tag: Übriges von gestern, Eingang, schätzen, in freie Lücken legen. |
| Tag abschließen | Zeiten je Aufgabe gerundet prüfen und anpassen. Worklogs gehen an ManageEngine. SAP-Zeilen überträgst du mit Kopier-Knöpfen oder als Excel-Liste und hakst sie ab; nichts wird doppelt gebucht. |
| ManageEngine | Eigene offene Tickets landen im Eingang (Konto → Kunde). Zugang in den Einstellungen, der API-Schlüssel liegt im Schlüsselbund. |
| Fokus | Vollbild mit einer Aufgabe, großem Timer, Erledigt und Nächste. Arbeitsart, PSP-Element und Bearbeitung klappen unten auf. Dazu Musik: eine Playlist aus der Musik-App startet mit dem Timer und hält mit ihm an. |
| Kunden | Kennzahlen und eine Karte je Kunde mit Stunden dieser Woche und im Monat. Im Kunden: lokale Todos, PSP-Elemente, ManageEngine-Konto. |
| Rückblick | Stunden gegen das Wochenziel, Tagesdurchschnitt, Anteil Kundenarbeit, Stunden je Tag und je Kunde, Verlauf der letzten Wochen, Wochenziele, Export als CSV. |
| Leerlauf | Läuft der Timer und kommt länger keine Eingabe, fragt Tagwerk nach der Rückkehr: Zeit behalten, Pause abziehen oder einer anderen Aufgabe geben. |
| Schnell erfassen | ⌃⌥ Leertaste öffnet von überall ein kleines Fenster für neue Aufgaben. |
| Mails | Mails aus Outlook (oder .eml-Dateien) in den Eingang ziehen; Betreff und Absender werden übernommen. |
| Sicherung | Täglich eine Kopie der Datenbank, die letzten 14 bleiben. |
| SAP-Abgleich | Die Aufgabenliste aus ByDesign (Excel-Export oder kopierte Tabelle) wird zu PSP-Elementen bei den Kunden. Neue kommen dazu, geänderte Bezeichnungen werden übernommen, verschwundene auf Wunsch deaktiviert. |
| Claude | Ein MCP-Server liegt in der App. Claude Desktop und Claude Code können damit Aufgaben, Timer, Zeiten und den Stand des Tagesabschlusses lesen und ändern. Gebucht wird weiter nur in Tagwerk. |
| Menüleiste | Laufende Zeit, Stoppen, Erledigt, eine andere Aufgabe starten. |

Außerdem:

- Es läuft immer höchstens ein Timer. Ein neuer Start beendet den laufenden.
- Offene Aufgaben von gestern rutschen automatisch auf heute.
- Eine Zeitangabe am Ende des Titels wird zur Schätzung, z. B. „Angebot schreiben 1h30“ oder „Logs prüfen 45m“.

Noch nicht enthalten:

| Phase | Inhalt |
| --- | --- |
| 5 | Outlook |

## Starten

Voraussetzungen: macOS 14 oder neuer und Xcode 15.3 oder neuer.

1. Repository klonen und den Branch auschecken.
2. `open Package.swift` ausführen. Xcode öffnet das Paket. Das Schema „Tagwerk“ wählen und mit ⌘R starten.
3. Alternativ im Terminal: `swift run Tagwerk`.
4. Als App zum Doppelklicken: `scripts/make-app.sh` baut `build/Tagwerk.app`. Die kannst du in den Programme-Ordner ziehen.
5. Tests laufen mit `swift test`.
6. Zum Ausprobieren ohne eigene Daten: `swift run Tagwerk -TagwerkDemo YES` startet mit Beispieldaten. Die werden nicht gespeichert.

Screenshots aller Bildschirme liegen unter `docs/screenshots`. Die CI erzeugt sie neu, wenn eine Commit-Nachricht `[screenshots]` enthält.

Für den Kalenderzugriff am besten `scripts/make-app.sh` nutzen und `build/Tagwerk.app` starten. macOS fragt dann einmal nach dem Zugriff auf die Kalender. In den Einstellungen (⌘,) legst du Arbeitszeit, Kalender und Zeitblöcke fest. Ist dein Exchange-Konto im macOS-Kalender eingerichtet, erscheinen dort auch die Outlook-Termine.

## Abgleich mit SAP ByDesign

Ohne API-Zugriff auf SAP holt Tagwerk die Projektaufgaben über die Tabelle, die du in ByDesign ohnehin siehst:

1. In ByDesign die Liste deiner Aufgaben öffnen (Spalten Kategorie und Aufgabennummer, z. B. `CPSO8643-12`).
2. Am besten auch Aufgabenname, Projekt und Kunde einblenden.
3. Nach Excel exportieren und die Datei in Tagwerk unter Kunden › SAP-Abgleich hineinziehen, oder die Zeilen kopieren und „Aus Zwischenablage einfügen“ wählen.
4. Jedem Projekt einmal den Kunden zuordnen. Beim nächsten Abgleich merkt Tagwerk sich das über die schon bekannten Aufgaben.

Gelesen werden `.xlsx`, Excel-XML (`.xls`), CSV und HTML-Tabellen. In SAP ändert sich dabei nichts.

## Claude anbinden (MCP)

`scripts/make-app.sh` legt den MCP-Server `tagwerk-mcp` neben die App: `Tagwerk.app/Contents/MacOS/tagwerk-mcp`.

- **Claude Desktop:** Einstellungen › Claude › „In Claude Desktop eintragen“, danach Claude Desktop neu starten. Von Hand geht es über `~/Library/Application Support/Claude/claude_desktop_config.json`:

  ```json
  {
    "mcpServers": {
      "tagwerk": { "command": "/Applications/Tagwerk.app/Contents/MacOS/tagwerk-mcp" }
    }
  }
  ```

- **Claude Code:** `claude mcp add --scope user tagwerk -- /Applications/Tagwerk.app/Contents/MacOS/tagwerk-mcp`

Werkzeuge: `tagesuebersicht`, `aufgaben`, `aufgabe_anlegen`, `aufgabe_aendern`, `timer_starten`, `timer_stoppen`, `zeitauswertung`, `tagesabschluss`, `kunden`, `wochenziele`, `wochenziel_anlegen`. Der Server arbeitet direkt auf der Datenbank; die geöffnete App lädt Änderungen innerhalb einer Sekunde nach. Nach SAP oder ManageEngine bucht Claude nicht. Mit der Umgebungsvariable `TAGWERK_DB` lässt sich eine andere Datenbank angeben, z. B. zum Ausprobieren.

## Daten

Alle Daten liegen lokal in `~/Library/Application Support/Tagwerk/tagwerk.sqlite`. Time Machine sichert die Datei mit. Die App nutzt die SQLite-Bibliothek von macOS und braucht keine Fremdpakete.

## Tastenkürzel

| Kürzel | Aktion |
| --- | --- |
| ⌘N | Neue Aufgabe (auf Start) |
| ⌘T | Timer der Fokus-Aufgabe starten oder stoppen |
| ⌘↩ | Fokus-Aufgabe erledigt |
| ⌘1 bis ⌘6 | Start, Plan, Kalender, Fokus, Kunden, Rückblick |
| ⌘0 | Tag planen |
| ⌘9 | Tag abschließen |
| Esc | Fokus verlassen |
| ⌃⌥ Leertaste | Schnell erfassen, auch wenn Tagwerk im Hintergrund ist |
| Doppelklick auf eine Aufgabe | im Fokus öffnen |

## Musik im Fokus

Unter Einstellungen › Fokus (oder im Fokus über das Notensymbol) wählst du eine Playlist aus der Musik-App. Sie startet, sobald du im Fokus den Timer startest, und hält an, wenn du ihn stoppst. Tagwerk steuert dafür die Musik-App per AppleScript; macOS fragt beim ersten Mal, ob Tagwerk das darf (Systemeinstellungen › Datenschutz & Sicherheit › Automation).

## Aufbau

| Pfad | Inhalt |
| --- | --- |
| `Sources/TagwerkCore` | Datenmodell, Zeitlogik, Tagesplan-Regeln, SQLite-Speicher. Ohne Oberfläche und unter Linux testbar. |
| `Sources/TagwerkApp` | SwiftUI-Oberfläche, nur macOS |
| `Sources/TagwerkMCP` | MCP-Server (JSON-RPC über stdin/stdout) und die Werkzeuge für Claude |
| `Sources/tagwerk-mcp` | Startprogramm des MCP-Servers |
| `Support` | Info.plist und App-Symbol (`AppIcon.svg` ist die Vorlage) |
| `Tests/TagwerkCoreTests` | Tests für die Kernlogik |
| `Tests/TagwerkMCPTests` | Tests für den MCP-Server |

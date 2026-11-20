<p align="center"><img src="docs/logo.png" width="128" alt="Tagwerk-Logo"></p>

# Tagwerk

Tagwerk ist der Arbeitsname einer schlanken Mac-App für Tagesplanung, Fokus und Zeiterfassung. Später bucht sie die Zeiten direkt in SAP Business ByDesign und als Worklog in ManageEngine.

Der vollständige Plan steht im Dokument „Plan: Eigene Todo-App für den Mac“.

## Stand: Phase 4 plus SAP-Abgleich und Claude-Anbindung

Aufbau: dunkel und ruhig, oben die Leiste mit Start, Plan, Kalender, Fokus, Kunden und Rückblick.

| Bereich | Was geht |
| --- | --- |
| Start | Großes Datum, Stunden heute und diese Woche. Links die Aufgaben von heute (neue oben oder unten einfügen, per Ziehen sortieren), darunter die Erledigt-Liste und der Eingang. Rechts der Tageskalender, an der Kante breiter ziehbar; die Lupen machen die Stunden höher. |
| Unteraufgaben | Beim Darüberfahren über eine Aufgabe das Listen-Symbol neben ▶, Rechtsklick › „Unteraufgabe hinzufügen“ oder im Fokus „Unteraufgaben“; geht in Start, Eingang, Woche und bei den Kunden. Claude legt sie über MCP mit `unteraufgabe_von` an. Jede Unteraufgabe hat ihren eigenen Timer und kann ein eigenes Ticket haben; Kunde, SAP-Aufgabe und Ticket erbt sie sonst von der Aufgabe darüber. Im Tagesabschluss steht sie als eigene Zeile („Aufgabe: Unteraufgabe“). |
| Zeit nachtragen | Vergessen, den Timer zu starten? Auf Start „Nachtragen“, ⌥⌘T, Rechtsklick auf eine Aufgabe › „Zeit nachtragen …“ oder im Fokus „Vergessen zu starten?“. Dort startet der Timer auch rückwirkend („läuft schon seit 15 Minuten“ oder „seit dem letzten Eintrag“), ohne sich mit erfassten Zeiten zu überschneiden. |
| Ticket zuordnen | Jede eigene Aufgabe oder Unteraufgabe lässt sich einem Ticket zuordnen (Rechtsklick › „Ticket zuordnen“ oder der Ticket-Knopf im Fokus). Gesucht wird nach Nummer oder Betreff, auf Wunsch direkt in ManageEngine über alle Techniker (auch Tickets von Kollegen). Die Zeit geht dann zusätzlich als Worklog an das Ticket. |
| Ziele | Lange Ziele über Wochen, z. B. „AZ-305 bestehen“: Zieldatum, Stundenziel, Fortschrittsbalken und das nötige Tempo („≈ 4 h pro Woche nötig“). Aufgaben ordnest du per Rechtsklick › Ziel zu, ziehst sie auf ein Ziel oder legst sie direkt im Ziel an; ihre Zeit (auch die der Unteraufgaben) zählt mit. Die aktiven Ziele stehen auch auf Start und im Rückblick. ⌘6 öffnet die Ziele, der Rückblick ist jetzt ⌘7. |
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
| SAP-Abgleich | Die Aufgabenliste aus ByDesign (deutsch oder englisch) wird zu PSP-Elementen bei den Kunden, je Aufgabe und Tätigkeit (Activity) ein Eintrag. Neue kommen dazu, geänderte Bezeichnungen werden übernommen, verschwundene auf Wunsch deaktiviert. |
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

## Herunterladen (ohne selbst zu bauen)

GitHub baut die App bei jedem Push und legt sie unter **Releases › „Tagwerk – aktueller Stand“** ab.

1. `Tagwerk.zip` herunterladen und entpacken.
2. `Tagwerk.app` in den Ordner Programme ziehen (eine ältere Fassung ersetzen).
3. Beim ersten Öffnen blockt macOS die App, weil sie nicht von Apple beglaubigt ist: Systemeinstellungen › Datenschutz & Sicherheit › „Dennoch öffnen“. Alternativ im Terminal: `xattr -dr com.apple.quarantine /Applications/Tagwerk.app`
4. Fragt macOS nach dem Schlüsselbund, „Immer erlauben“ wählen. Damit das und die Kalender-Freigabe auch nach Updates bleiben, einmal die feste Signatur einrichten (siehe „Signieren“).

Daten und Einstellungen bleiben beim Ersetzen der App erhalten; sie liegen nicht in der App.

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

Ohne API-Zugriff auf SAP holt Tagwerk die Projektaufgaben (z. B. `CPSO8643-12`) auf einem von drei Wegen; alle unter Kunden › SAP-Abgleich:

1. **Direkt aus ByDesign:** „ByDesign öffnen“ öffnet ByDesign in einem Tagwerk-Fenster. Anmelden wie im Browser, die Liste deiner Aufgaben öffnen, „Aufgaben holen“. Tagwerk liest die Tabelle von der Seite, bei langen Listen weiterblättern und erneut holen. Die Anmeldung bleibt wie in Safari als Cookie auf dem Mac; ein Passwort speichert Tagwerk nicht. Die Adresse steht in Einstellungen › Buchung.
   Mit Benutzer und Passwort in Einstellungen › Buchung meldet Tagwerk sich selbst an (das Passwort liegt im Schlüsselbund). Ist die Liste einmal mit „Diese Liste merken“ gemerkt, holt Tagwerk sie auf Wunsch einmal am Tag beim Start automatisch und übernimmt neue Aufgaben in schon bekannten Projekten; neue Projekte warten im SAP-Abgleich auf einen Kunden.
2. **Bildschirmfoto:** Liste fotografieren (⇧⌘4) und ins Abgleich-Fenster ziehen oder einfügen; Tagwerk liest die Nummern per Texterkennung.
3. **Excel-Export oder kopierte Tabelle**, falls ByDesign einen Export anbietet (`.xlsx`, Excel-XML, CSV, HTML).

Tagwerk liest die Seite so, wie man sie sieht: Text auf gleicher Höhe ist eine Zeile, die Spalten kommen aus den Überschriften (deutsch wie „Aufgabennummer“, „Tätigkeit“ oder englisch wie „Task ID“, „Work Package Task“, „Activity“). Hat eine Aufgabe mehrere Activities, wird jede ein eigener Eintrag; die gewählte Tätigkeit landet in der SAP-Buchung (Spalte „Leistung“ der Übertragungsliste, Kopier-Knopf „Tätigkeit“ im Tagesabschluss). Klappt das Lesen nicht, sichert „Seite sichern“ im ByDesign-Fenster, was Tagwerk sieht (Datei in Downloads, vor dem Weitergeben ansehen).

Danach jedem Projekt einmal den Kunden zuordnen. Beim nächsten Abgleich merkt Tagwerk sich das über die schon bekannten Aufgaben. In SAP ändert sich dabei nichts.

Termine aus dem Kalender werden per Rechtsklick oder Doppelklick › „Als Zeit erfassen …“ zur erfassten Zeit, mit Kunde, PSP-Element und Arbeitsart; Tagwerk merkt sich die Auswahl je Termintitel. Im Tagesabschluss ist der Worklog im Ticket freiwillig („Ohne Worklog“), die Buchung in SAP nicht.

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

## Signieren (einmal einrichten, damit Freigaben bleiben)

macOS merkt sich die Freigaben für Kalender, Schlüsselbund (ManageEngine-Schlüssel) und Musik anhand der Signatur der App. Ohne festes Zertifikat ist jede neue Fassung für macOS eine andere App, und die Freigaben gehen verloren. Einmal auf dem eigenen Mac im Repository ausführen:

```
scripts/signatur-einrichten.sh
```

Das Skript erzeugt ein selbst signiertes Zertifikat „Tagwerk Lokal“, legt es in deinen Schlüsselbund (dann signiert auch `scripts/make-app.sh` damit) und hinterlegt es bei GitHub als Secret `TAGWERK_SIGNING_P12` mit Passwort `TAGWERK_SIGNING_PASSWORD`. Mit der GitHub-CLI (`gh`) geht das automatisch, sonst führt das Skript durch die zwei Einträge auf der GitHub-Seite. Ab dem nächsten Build sind die Downloads damit signiert; danach einmal Kalender und Schlüsselbund freigeben („Immer erlauben“), dann bleibt es so.

Ohne Zertifikat signiert der Build ad hoc. Den API-Schlüssel liest Tagwerk erst, wenn es wirklich mit ManageEngine spricht, und nur einmal pro Start.

## Weg zum iPhone (vorbereitet)

Eine iPhone-Fassung gibt es noch nicht, der Umstieg ist aber vorbereitet:

- **Der Kern läuft auf dem iPhone.** `TagwerkCore` (Datenmodell, Zeitlogik, Datenbank, SAP-Import, ManageEngine) hängt nur an Foundation und SQLite; die CI baut ihn bei jedem Push zusätzlich für iOS.
- **Die Datenbank merkt sich Änderungen.** Jede Zeile hat `modified_at`, Gelöschtes landet in `deleted_record`; `SQLiteStore.changes(since:)` liefert, was sich seit einem Zeitpunkt geändert hat. Trigger erfassen auch Änderungen des MCP-Servers. Alle Einträge haben UUIDs, damit Geräte ohne Zusammenstöße zusammenführen können.

Noch zu tun, sobald es losgeht:

1. Entscheidung zum Abgleich: iCloud (CloudKit, braucht das Apple-Entwicklerkonto, 99 € im Jahr) oder der Mac als Server für eine Web-App im WLAN oder per Tailscale (ohne Konto).
2. Abgleich auf Basis von `changes(since:)` bauen (letzte Änderung gewinnt, Löschungen zuerst).
3. iPhone-App-Ziel anlegen: Heute, Timer, Schnell erfassen, Fokus mit Musik (dort über MediaPlayer statt AppleScript), Eingang. SAP-Abgleich, Tagesabschluss und ManageEngine bleiben auf dem Mac.
4. Mit Konto: Signatur und TestFlight in der CI.

## Daten

Alle Daten liegen lokal in `~/Library/Application Support/Tagwerk/tagwerk.sqlite`. Time Machine sichert die Datei mit. Die App nutzt die SQLite-Bibliothek von macOS und braucht keine Fremdpakete.

## Tastenkürzel

| Kürzel | Aktion |
| --- | --- |
| ⌘N | Neue Aufgabe (auf Start) |
| ⌘T | Timer der Fokus-Aufgabe starten oder stoppen |
| ⌘↩ | Fokus-Aufgabe erledigt |
| ⌘1 bis ⌘7 | Start, Plan, Kalender, Fokus, Kunden, Ziele, Rückblick |
| ⌥⌘T | Zeit nachtragen |
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

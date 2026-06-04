# Claude Usage Tray für Windows

Diese kleine App zeigt unten rechts in Windows an, wie viel Claude-Pro/Max-
Nutzung schon verbraucht ist.

Das Tray-Icon zeigt eine Ampel:

- Gruen mit Haken: alles okay
- Orange mit Ausrufezeichen: ab 70 Prozent
- Rot mit Ausrufezeichen: ab 90 Prozent

Die genauen Werte stehen im Rechtsklick-Menue des Icons.

## Installation für normale Nutzer

Es gibt zwei Wege, die App zu installieren. **Weg A** wird empfohlen, da er Windows Smart App Control automatisch umgeht und am einfachsten ist.

### Weg A: Automatische Installation (Empfohlen)

1. Öffne die **PowerShell** in Windows (einfach im Startmenü nach `powershell` suchen).
2. Kopiere folgenden Befehl, füge ihn ein und drücke Enter:
   ```powershell
   irm https://raw.githubusercontent.com/LSX-Apps/CC-Nutzung-Releases/main/install.ps1 | iex
   ```
3. Der Setup-Assistent öffnet sich direkt und blockfrei im Vordergrund.

### Weg B: Manuelle Installation über ZIP-Archiv

1. ZIP-Datei von GitHub Releases herunterladen.
2. **WICHTIG für Smart App Control:** Da Skripte aus dem Internet von Windows standardmäßig blockiert werden, mache vor dem Entpacken einen Rechtsklick auf die heruntergeladene ZIP-Datei -> **Eigenschaften** -> Ganz unten bei Sicherheit den Haken bei **Zulassen** (bzw. **Unblock**) setzen -> **Übernehmen** / **OK** klicken.
3. Die ZIP-Datei entpacken.
4. Die Verknüpfung **`ClaudeUsageTray-Setup.lnk`** per Doppelklick starten (dies öffnet das Setup ohne CMD-Fenster).
5. Im Assistenten Schritt für Schritt durchgehen:
   - Claude Code installieren
   - Login starten
   - Tray installieren

Nach der Installation ist das Icon unten rechts in der Windows-Taskleiste.
Manchmal steckt es zuerst im kleinen Pfeil-Menue.

## Was ist Claude Code und warum braucht die App das?

Claude selbst laeuft normalerweise im Browser oder in der Desktop-App. Die
Nutzungsdaten, die diese Tray-App braucht, sind aber nicht als normale
oeffentliche API verfuegbar.

Claude Code ist das Terminal-Programm von Anthropic. Wenn man sich dort einmal
anmeldet, legt es lokal eine Login-Datei an. Diese App nutzt diese lokale
Login-Datei, um die Usage-Werte abzufragen.

Claude Code muss danach nicht dauerhaft offen bleiben.

## Manuelle Installation ohne Assistent

```powershell
powershell -ExecutionPolicy Bypass -File .\install-ccusage-windows.ps1
```

## Test

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\ClaudeUsageTray\ccusage-poll.ps1" -VerboseOutput
```

Die Ausgabe-Datei liegt hier:

```text
%USERPROFILE%\.claude\cc-usage.json
```

## Deinstallation

```powershell
powershell -ExecutionPolicy Bypass -File .\install-ccusage-windows.ps1 -Uninstall
```

## Updates

Im Tray-Menü gibt es **Update prüfen**. 

Das ist standardmäßig so vorkonfiguriert, dass die App im öffentlichen GitHub-Repository `LSX-Apps/CC-Nutzung-Releases` nach neuen Releases sucht. Du musst also nichts weiter einstellen.

Für das Erstellen und Veröffentlichen neuer Releases siehe [RELEASE-HOWTO.md](RELEASE-HOWTO.md).


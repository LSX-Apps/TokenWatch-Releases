# Updates veröffentlichen

Die App aktualisiert sich automatisch über zwei Dateien auf GitHub:

1. eine ZIP-Datei mit der neuen Version (hochgeladen als GitHub Release)
2. eine kleine JSON-Datei, das Manifest (`release/ccusage-manifest.json` in diesem Repository)

Das Manifest sagt der App: "Es gibt Version X, lade diese ZIP von URL Y herunter, und der SHA256-Hash muss Z sein."

## Ablauf bei einer neuen Version

Wenn du eine neue Version veröffentlichen möchtest, folgst du diesen Schritten:

### 1. Version erhöhen & Release lokal bauen
Führe das Build-Skript in PowerShell aus und übergib die neue Versionsnummer (z. B. `0.2.1`):

```powershell
.\build-release.ps1 -Version "0.2.1"
```

Dieses Skript erledigt alles automatisch:
* Es erstellt das ZIP-Archiv `release/ClaudeUsageTray-0.2.1.zip`.
* Es berechnet den SHA256-Hash der ZIP-Datei.
* Es generiert ein neues Manifest `release/ccusage-manifest.json` mit der neuen Version, dem berechneten Hash und der passenden Download-URL auf GitHub Releases.

### 2. Änderungen im Releases-Repository pushen
Da der lokale Ordner `release` als eigenständiges Git-Repository verknüpft ist, musst du dort einfach nur das Manifest committen und pushen:

```powershell
cd release
git add ccusage-manifest.json
git commit -m "Update manifest to v0.2.1"
git push origin main
cd ..
```

*(Wichtig: Das Manifest muss im `main`-Branch des öffentlichen Repositories `CC-Nutzung-Releases` liegen, damit die installierten Clients darauf zugreifen können.)*

### 3. GitHub Release im öffentlichen Repository erstellen
1. Gehe in deinem öffentlichen GitHub-Repository **CC-Nutzung-Releases** auf **Releases** und klicke auf **Draft a new release**.
2. Benenne das Tag und den Titel des Releases als `v0.2.1` (passend zu der in Schritt 1 angegebenen Version).
3. Lade die in Schritt 1 erzeugte Datei `release/ClaudeUsageTray-0.2.1.zip` als Asset für das Release hoch.
4. Veröffentliche das Release.

Sobald das Release online ist und das Manifest im `main`-Branch des öffentlichen Repositories liegt, können installierte Versionen der App das Update finden.

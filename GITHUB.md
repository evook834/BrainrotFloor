# Git-Workflow für dieses Projekt

Kurze Anleitung, wie du mit Git arbeitest – ohne Fachjargon.

---

## Grundidee

- **Repository (Repo)**: Der Ordner mit dem Projekt und seiner kompletten Versionsgeschichte.
- **Branch (Zweig)**: Eine eigene Linie von Änderungen. `main` ist meist die „offizielle“ Version.
- **Commit**: Ein abgeschlossener Schnappschuss deiner Änderungen mit einer kurzen Beschreibung.

---

## Typischer Ablauf

### 1. Aktuellen Stand holen

```bash
git pull
```

Lädt die neuesten Änderungen vom Server (z. B. GitHub) und fügt sie in deinen lokalen Ordner ein.

---

### 2. Eigene Änderungen vorbereiten

```bash
git status
```

Zeigt, welche Dateien du geändert, neu angelegt oder gelöscht hast.

```bash
git add <Datei>
# oder alle:  git add .
```

Markiert Dateien für den nächsten Commit („staging“). Nur diese Änderungen kommen in den Commit.

```bash
git commit -m "Kurze Beschreibung der Änderung"
```

Speichert die markierten Änderungen als einen Commit mit deiner Nachricht. Noch nur lokal, nicht auf dem Server.

---

### 3. Änderungen hochladen

```bash
git push
```

Schickt deine lokalen Commits zum Server (z. B. auf den Branch `main`). Danach sehen andere deine Änderungen.

---

## Mit Branches arbeiten (z. B. für Features)

```bash
git branch
```

Listet Branches auf; der aktuelle ist mit `*` markiert.

```bash
git checkout -b name-des-branches
```

Legt einen neuen Branch an und wechselt sofort dorthin. Du arbeitest dann in dieser Linie.

```bash
git checkout main
```

Wechselt zurück zum Branch `main`.

```bash
git merge name-des-branches
```

Führt die Änderungen aus `name-des-branches` in den aktuellen Branch (z. B. `main`) ein. Danach kannst du den Feature-Branch löschen oder behalten.

---

## Nützliche Zusatzbefehle

| Befehl | Bedeutung |
|--------|-----------|
| `git log --oneline` | Zeigt die letzten Commits kurz an. |
| `git diff` | Zeigt ungespeicherte Änderungen in den Dateien. |
| `git diff --staged` | Zeigt Änderungen, die schon für den nächsten Commit markiert sind. |
| `git restore <Datei>` | Verwirft Änderungen an einer Datei (zurück zum letzten Commit). |
| `git clone <URL>` | Projekt zum ersten Mal auf den Rechner kopieren. |

---

## Kurz-Checkliste vor dem Push

1. `git pull` – Stand aktualisieren  
2. Änderungen machen  
3. `git add` und `git commit -m "…"`  
4. `git push`

Wenn du auf einem eigenen Branch arbeitest: Nach dem Push oft einen **Pull Request** (PR) auf GitHub öffnen, damit jemand die Änderungen prüfen und in `main` übernehmen kann.

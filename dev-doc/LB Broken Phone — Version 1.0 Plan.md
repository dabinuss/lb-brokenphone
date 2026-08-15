# LB Broken Phone — Version 1.0 Plan

## Ziel

Eine kleine eigenständige FiveM-Resource, die bei LB Phone ein beschädigtes Smartphone-Display simuliert.

Keine Änderung an Dateien innerhalb von `lb-phone`.

Die Mod soll:

- drei Schadensstufen besitzen,
- den Schaden pro konkretem Smartphone speichern,
- das beschädigte Display über LB Phone darstellen,
- beim Öffnen und Schließen des Phones visuell mit der Phone-Bewegung synchronisiert wirken,
- bei mittlerem und schwerem Schaden Touch-Aussetzer simulieren,
- das Display vollständig reparieren können,
- durch andere Mods über einfache Exports angesprochen werden können,
- über echte Test-Commands vollständig testbar sein.

---

# 1. Schadensstufen

```text
1 = Light
2 = Medium
3 = Severe
```

Zusätzlich intern:

```text
0 = Intact
```

### Light

- wenige Risse
- keine Touch-Störung

### Medium

- deutlich zersprungen
- gelegentliche Touch-Aussetzer

### Severe

- stark zersprungen
- häufigere Touch-Aussetzer

---

# 2. Reparatur

Es gibt keine Teilreparatur.

Immer:

```text
Light ──┐
Medium ─┼─> Display replacement ─> Intact
Severe ─┘
```

Öffentlicher Export:

```lua
exports["lb-brokenphone"]:RepairPhone(source)
```

Für ein konkretes Phone:

```lua
exports["lb-brokenphone"]:RepairPhoneByNumber(phoneNumber)
```

---

# 3. Schaden gehört zum Smartphone

Der Schaden wird niemals am Spieler gespeichert.

Schlüssel:

```text
phoneNumber
```

Beispiel:

```text
555926472 -> Severe
555111222 -> Intact
```

Der gleiche Spieler kann also mehrere Smartphones mit unterschiedlichen Zuständen besitzen.

Wird ein beschädigtes Phone an einen anderen Spieler gegeben, bleibt es beschädigt.

---

# 4. Datenbank

Eine einzelne Tabelle genügt:

```sql
CREATE TABLE phone_damage (
    phone_number VARCHAR(32) PRIMARY KEY,
    damage_level TINYINT NOT NULL,
    damage_seed INT NOT NULL
);
```

Nur beschädigte Phones haben einen Eintrag.

Kein Eintrag:

```text
Intact
```

Bei Reparatur:

```sql
DELETE FROM phone_damage
WHERE phone_number = ?;
```

---

# 5. Damage Seed

Jeder Schaden bekommt einen Seed.

Beispiel:

```text
damageLevel = 2
damageSeed = 18374291
```

Der Seed bestimmt:

- Crack-Texture
- Rotation
- Skalierung
- Position

Dadurch sieht dasselbe beschädigte Phone immer gleich aus.

---

# 6. Overlay

Eigene Resource:

```text
lb-brokenphone
```

mit transparenter NUI.

Diese NUI hat keinen Fokus.

Sie zeigt ausschließlich:

```text
crack overlay
```

über dem sichtbaren LB-Phone-Display.

Kein Overlay über:

- GTA-Welt
- HUD
- Phone-Gehäuse
- andere Geräte

Nur Display.

---

# 7. Crack Assets

Keine Screenshots des Phones.

Stattdessen große transparente Crack-Textures.

Zum Beispiel:

```text
light/
  crack1.webp
  crack2.webp

medium/
  crack1.webp
  crack2.webp
  crack3.webp

severe/
  crack1.webp
  crack2.webp
  crack3.webp
```

Die Bilder dürfen größer als das Display sein.

Sie werden innerhalb der Displayfläche:

- verschoben
- skaliert
- leicht gedreht
- abgeschnitten

Dadurch entstehen viele Varianten mit wenigen Assets.

---

# 8. Display Mask

Die Crack-Texture wird in einem Container gerendert:

```text
damage-display
```

Dieser entspricht der sichtbaren LB-Phone-Displayfläche.

CSS:

```css
overflow: hidden;
border-radius: ...;
pointer-events: none;
```

Alles außerhalb des Displays wird abgeschnitten.

---

# 9. Phone-Bewegung

Das Overlay muss beim Öffnen und Schließen optisch mit LB Phone mitfahren.

LB Phone stellt Zustände für:

```text
phone open
phone on screen
phone closed
```

bereit.

Die Damage-NUI bekommt deshalb dieselben Zustände:

```text
closed
opening
open
closing
```

Beim Öffnen:

```text
LB Phone starts opening
↓
Damage overlay starts opening animation
↓
both reach final position
```

Beim Schließen:

```text
LB Phone starts closing
↓
Damage overlay follows
↓
both disappear
```

Die Bewegung wird als kleines Motion-Profil in unserer Resource definiert:

```lua
Config.Motion = {
    openDuration = ...,
    closeDuration = ...,

    closedY = ...,
    openY = ...,

    easing = ...
}
```

Diese Werte werden einmal an LB Phone angepasst.

Keine komplizierte Tracking-Engine.

Keine laufenden Koordinatenabfragen.

Keine Änderungen an LB Phone.

---

# 10. Display Position

Ein einfaches Profil:

```lua
Config.Display = {
    width = ...,
    height = ...,
    right = ...,
    bottom = ...,
    radius = ...
}
```

Mit relativen Einheiten.

Das Crack-Bild selbst ist auflösungsunabhängig.

Nur der Display-Container muss einmal passend zur LB-Phone-Darstellung eingestellt werden.

---

# 11. Phone Events

Benötigt werden nur:

```text
lb-phone:numberChanged
lb-phone:phoneToggled
lb-phone:setOnScreen
```

Dadurch erkennen wir:

- welches Phone aktiv ist,
- wann es geöffnet wird,
- wann es verschwindet.

Kein permanentes Polling.

---

# 12. Client-Zustand

Minimal:

```lua
State = {
    phoneNumber = nil,
    damageLevel = 0,
    damageSeed = nil,
    phoneOpen = false,
    phoneOnScreen = false
}
```

Mehr braucht V1.0 nicht.

---

# 13. Touch-Störung

Die Overlay-NUI darf keine Klicks abfangen.

Stattdessen wird LB Phones:

```lua
ToggleDisabled(true)
ToggleDisabled(false)
```

für sehr kurze Zeiträume verwendet.

### Medium

Etwa:

```text
alle 4–9 Sekunden
```

für:

```text
100–180 ms
```

kurz nicht reagierend.

### Severe

Etwa:

```text
alle 1.5–4.5 Sekunden
```

für:

```text
120–300 ms
```

Dadurch entsteht:

```text
Click
→ reagiert manchmal nicht
→ erneut klicken
→ funktioniert
```

Keine komplizierte Input-Manipulation.

---

# 14. Touch-System läuft nur wenn nötig

Nur wenn:

```text
damageLevel >= 2
AND
phoneOpen
AND
phoneOnScreen
```

Sonst:

```text
kein Touch-Thread
```

Beim Phone-Schließen sofort beenden.

---

# 15. Öffentliche API

V1.0 braucht nur diese Exports:

```lua
ApplyPhoneDamage(source, level, cause)

ApplyPhoneDamageByNumber(phoneNumber, level, cause)

GetPhoneDamage(phoneNumber)

RepairPhone(source)

RepairPhoneByNumber(phoneNumber)
```

Das reicht für praktisch alle Integrationen.

---

# 16. ApplyPhoneDamage

Beispiel Unfall-Mod:

```lua
exports["lb-brokenphone"]:ApplyPhoneDamage(
    source,
    2,
    "vehicle_crash"
)
```

Phone Damage ermittelt selbst das aktuell ausgerüstete Smartphone.

---

# 17. Schaden eskaliert nur

Beispiel:

```text
Light + Medium Damage
→ Medium
```

```text
Severe + Light Damage
→ bleibt Severe
```

Ein Damage-Event darf ein Phone niemals versehentlich reparieren.

---

# 18. Test-Commands

Separate kleine Test-Resource.

Nur:

```text
/phonedamage 1
/phonedamage 2
/phonedamage 3

/phonerepair
```

und:

```text
/phonedamage 1 555926472
/phonedamage 2 555926472
/phonedamage 3 555926472

/phonerepair 555926472
```

---

# 19. Echte Tests

Die Commands dürfen keinen internen State direkt setzen.

Beispiel:

```text
/phonedamage 2
```

muss laufen über:

```text
Test Command
↓
öffentlicher Export
↓
LB Phone Nummer ermitteln
↓
DB
↓
Server State
↓
Client Update
↓
Overlay
↓
Touch-System
```

Genau wie eine echte externe Mod.

---

# 20. Multi-Phone-Test

Phone A:

```text
555926472
```

Phone B:

```text
555111222
```

Test:

```text
/phonedamage 3 555926472
```

Erwartung:

```text
Phone A = Severe
Phone B = unverändert
```

Dann:

```text
/phonerepair 555111222
```

Phone A muss weiterhin Severe sein.

---

# 21. Übergabe-Test

Spieler A besitzt:

```text
555926472
```

und beschädigt es.

Dann gibt er es Spieler B.

Spieler B rüstet das Phone aus.

Erwartung:

```text
gleiche Schadensstufe
gleicher Seed
gleiches Crack-Muster
```

---

# 22. Restart-Test

Nach:

```text
/phonedamage 2
```

testen:

```text
Phone schließen/öffnen
lb-brokenphone restart
lb-phone restart
Spieler reconnect
Server restart
```

Immer:

```text
gleicher Schaden
gleicher Seed
```

---

# 23. Dateien

Kleine Struktur:

```text
lb-brokenphone/
├── fxmanifest.lua
├── config.lua
├── client.lua
├── server.lua
├── database.sql
│
└── ui/
    ├── index.html
    ├── app.js
    ├── style.css
    │
    └── cracks/
        ├── light/
        ├── medium/
        └── severe/
```

Keine unnötige Aufteilung in zwanzig Dateien.

Wenn einzelne Dateien später zu groß werden, können sie immer noch geteilt werden.

---

# 24. Test-Resource

```text
lb-brokenphone-test/
├── fxmanifest.lua
└── server.lua
```

Mehr braucht sie nicht.

---

# 25. Entwicklungsreihenfolge

## Schritt 1

Resource-Grundgerüst.

## Schritt 2

DB + Schaden pro Telefonnummer.

## Schritt 3

Public Exports.

## Schritt 4

Test-Commands.

Ab diesem Punkt kann bereits getestet werden:

```text
damage
repair
multiple phones
persistence
```

## Schritt 5

Transparente Damage-NUI.

## Schritt 6

Display-Position + Maskierung.

## Schritt 7

Light/Medium/Severe Crack-Rendering.

## Schritt 8

Seed-Variation.

## Schritt 9

Open/Close Motion synchronisieren.

## Schritt 10

Touch-Aussetzer Medium/Severe.

## Schritt 11

Restart-Sicherheit.

## Schritt 12

Finale Tests + Resmon.

---

# 26. Version 1.0 gilt als fertig wenn

- LB Phone selbst unverändert ist.
- Schaden nur am konkreten Smartphone hängt.
- Mehrere Phones unabhängig beschädigt sein können.
- Schaden bei Weitergabe am Phone bleibt.
- Light funktioniert.
- Medium funktioniert.
- Severe funktioniert.
- Reparatur funktioniert.
- Risse nur auf dem Phone-Display liegen.
- Beim Öffnen/Schließen kein deutlich sichtbares Verrutschen entsteht.
- Crack-Muster nach Restart gleich bleiben.
- Touch-Aussetzer bei Medium funktionieren.
- Touch-Aussetzer bei Severe häufiger auftreten.
- `/phonedamage` den echten Produktionsweg testet.
- `/phonerepair` den echten Produktionsweg testet.
- Telefonnummern gezielt getestet werden können.
- Kein unnötiges Polling vorhanden ist.
- Phone Damage im Idle praktisch keine Last erzeugt.
- LB Phone Restart funktioniert.
- Server Restart funktioniert.
- keine bekannten kritischen Bugs vorhanden sind.

---

# 27. V1.0 Gesamtarchitektur

```text
Crash / andere Mod
        │
        ▼
ApplyPhoneDamage()
        │
        ▼
lb-brokenphone SERVER
        │
        ├─ phone number
        ├─ DB
        └─ damage state
              │
              ▼
       affected client
              │
       ┌──────┴──────┐
       │             │
       ▼             ▼
Damage Overlay    Touch Fault
       │             │
       ▼             ▼
LB Phone Display  ToggleDisabled()
```

Und:

```text
lb-phone
=
vollständig unangetastet
```
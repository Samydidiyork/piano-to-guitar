# Piano → Guitare

> Plugin MuseScore + prototype web pour convertir automatiquement une partition piano en tablature guitare.
>
> Projet conçu par **Jean-Pierre Mallet** ([@Samydidiyork](https://github.com/Samydidiyork))

---

## L'idée

L'idée de départ est simple et originale : **insérer une portée tablature guitare entre la clef de Sol et la clef de Fa** d'une partition piano, et y reporter intelligemment les notes des deux mains en évitant les doublons et les surcharges.

```
┌──────────────────────────────┐
│   Clef de SOL  (main droite) │
├──────────────────────────────┤
│   ── TABLATURE GUITARE ──    │  ← générée automatiquement
├──────────────────────────────┤
│   Clef de FA   (main gauche) │
└──────────────────────────────┘
```

La tablature peut ensuite être transcrite en partition guitare, ou inversement. Certains accords de 4 ou 5 sons sont automatiquement réduits à 3 sons selon des règles harmoniques précises.

---

## Règles de réduction harmonique

| Priorité | Intervalle | Action |
|----------|-----------|--------|
| ✅ Toujours garder | Fondamentale (basse, main gauche) | Conservée |
| ✅ Toujours garder | Mélodie (note la plus haute, main droite) | Conservée |
| ✅ Toujours garder | Tierce (3e min ou maj) | Conservée |
| ❌ Sacrifier | Quinte (5e juste) | Supprimée |
| ❌ Sacrifier | Neuvième (2e / 9e) | Supprimée |
| ⚠️ Si surcharge | Autres notes | Supprimées si > 6 notes |

**Règle spéciale — chevauchement :** si la mélodie (main droite) se retrouve au même niveau ou en dessous de la basse (main gauche) après fusion, elle est automatiquement remontée d'une octave.

---

## Prototype web interactif

Tester le prototype directement dans le navigateur :

👉 **[Ouvrir le prototype](https://samydidiyork.github.io/piano-to-guitar/web-prototype/index.html)**

Fonctionnalités :
- Sélectionner les notes main gauche / main droite
- Visualiser la réduction harmonique en temps réel
- Afficher la tablature résultante (case + corde)
- Exemples prêts à tester : Cmaj7, G9, Dm9

---

## Plugin MuseScore

Le fichier `PianoToGuitar.qml` est le plugin pour MuseScore 3/4.

### Installation

1. Télécharger `PianoToGuitar.qml`
2. Le placer dans le dossier plugins de MuseScore :
   - **Windows :** `%APPDATA%\MuseScore\MuseScore4\plugins\`
   - **macOS :** `~/Library/Application Support/MuseScore/MuseScore4/plugins/`
   - **Linux :** `~/.local/share/MuseScore/MuseScore4/plugins/`
3. Dans MuseScore : `Extensions > Gérer les extensions > Activer PianoToGuitar`
4. Ouvrir une partition piano
5. Lancer via `Extensions > Piano to Guitar`

---

## Structure du projet

```
piano-to-guitar/
├── PianoToGuitar.qml          Plugin MuseScore (QML + JavaScript)
├── web-prototype/
│   └── index.html             Prototype web interactif
├── README.md
└── LICENSE
```

---

## Roadmap

- [x] Concept et règles harmoniques
- [x] Algorithme de réduction (fondamentale, tierce, sacrifice quinte/neuvième)
- [x] Correction d'octave sur chevauchement mélodie/basse
- [x] Prototype web interactif
- [x] Plugin MuseScore (QML)
- [ ] Gestion des quintes altérées (♭5, ♯5 → conservées)
- [ ] Accordages alternatifs (DADGAD, open G...)
- [ ] Export MusicXML de la tablature seule
- [ ] Interface de réglage des règles dans le plugin

---

## Contribuer

Les contributions sont les bienvenues, en particulier de la part de :
- Musiciens pour affiner les règles de réduction
- Développeurs MuseScore / QML pour l'intégration des API
- Guitaristes pour valider les positions de tablature

---

## Licence

MIT — Jean-Pierre Mallet, 2025


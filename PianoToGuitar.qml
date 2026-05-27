import QtQuick 2.9
import MuseScore 3.0

MuseScore {
    menuPath:    "Plugins.Piano to Guitar"
    description: "Converts a piano grand staff (treble + bass clef) into a guitar tablature staff placed between them, applying harmonic reduction rules."
    version:     "1.0.0"
    requiresScore: true

    // ─── Musical rules ───────────────────────────────────────────────────────
    // Intervals (in semitones from root) that are sacrificed first when reducing
    // 7  = perfect fifth
    // 2  = major ninth / second
    // 14 = ninth (compound)
    property var SACRIFICE_INTERVALS: [7, 2, 14]

    // Maximum notes on guitar (6 strings)
    property int MAX_NOTES: 6

    // Guitar standard tuning MIDI values (low E to high E)
    property var STRING_TUNING: [40, 45, 50, 55, 59, 64]   // E2 A2 D3 G3 B3 E4
    property int MAX_FRET: 12

    // ─── Entry point ─────────────────────────────────────────────────────────
    onRun: {
        if (!curScore) {
            console.log("[PianoToGuitar] No score open.");
            Qt.quit();
            return;
        }
        var result = processScore(curScore);
        if (result.error) {
            console.log("[PianoToGuitar] Error: " + result.error);
        } else {
            console.log("[PianoToGuitar] Done — " + result.chordsProcessed + " chord(s) processed.");
        }
        Qt.quit();
    }

    // ─── Main processing ─────────────────────────────────────────────────────
    function processScore(score) {
        var staves = findPianoStaves(score);
        if (!staves) {
            return { error: "No piano grand staff found (treble + bass clef pair required)." };
        }

        var cursor = score.newCursor();
        cursor.rewind(0);  // beginning of score

        var chordsProcessed = 0;
        score.startCmd();

        while (cursor.segment) {
            if (cursor.element && cursor.element.type === Element.CHORD) {
                var measure   = cursor.measure;
                var tick      = cursor.tick;
                var rhNotes   = getNotesAtTick(score, staves.treble, tick);
                var lhNotes   = getNotesAtTick(score, staves.bass,   tick);

                if (rhNotes.length > 0 || lhNotes.length > 0) {
                    var reduced = reduceChord(rhNotes, lhNotes);
                    var tabNotes = assignToStrings(reduced.kept);
                    writeToTabStaff(score, staves.tab, tick, tabNotes, cursor.duration);
                    chordsProcessed++;
                }
            }
            cursor.next();
        }

        score.endCmd();
        return { chordsProcessed: chordsProcessed };
    }

    // ─── Staff detection ─────────────────────────────────────────────────────
    // Looks for a consecutive treble-clef staff immediately followed by a bass-clef staff.
    // If a tab staff already exists between them it reuses it, otherwise it adds one.
    function findPianoStaves(score) {
        var trebleIdx = -1;
        var bassIdx   = -1;

        for (var i = 0; i < score.nstaves; i++) {
            var clef = score.staves[i].clefType;
            if (clef === ClefType.G && trebleIdx === -1) {
                trebleIdx = i;
            } else if (clef === ClefType.F && trebleIdx !== -1 && bassIdx === -1) {
                if (i === trebleIdx + 1 || i === trebleIdx + 2) {
                    bassIdx = i;
                }
            }
        }

        if (trebleIdx === -1 || bassIdx === -1) return null;

        // Tab staff sits right between treble and bass
        var tabIdx = trebleIdx + 1;
        if (tabIdx === bassIdx) {
            // Need to insert a tab staff — MuseScore API: add staff after trebleIdx
            score.appendPart("guitar-tablature");
            // After insertion staves shift; re-detect
            bassIdx = tabIdx + 1;
        }

        return { treble: trebleIdx, tab: tabIdx, bass: bassIdx };
    }

    // ─── Note collection ─────────────────────────────────────────────────────
    function getNotesAtTick(score, staffIdx, tick) {
        var notes = [];
        var cursor = score.newCursor();
        cursor.staffIdx = staffIdx;
        cursor.rewindToTick(tick);
        if (cursor.element && cursor.element.type === Element.CHORD) {
            var chord = cursor.element;
            for (var i = 0; i < chord.notes.length; i++) {
                notes.push(chord.notes[i].pitch);  // MIDI pitch
            }
        }
        return notes;
    }

    // ─── Chord reduction algorithm ────────────────────────────────────────────
    // Rules:
    //  1. Always keep: bass (lowest LH note) + melody (highest RH note)
    //  2. Always keep: tierce (3rd, intervals 3 or 4)
    //  3. Sacrifice in order: quinte (7), neuvième (2/14)
    //  4. If melody ≤ bass + 5 semitones → raise melody one octave
    //  5. Remove duplicates (same pitch class)
    //  6. Cap at MAX_NOTES (6 strings)
    function reduceChord(rhNotes, lhNotes) {
        var allMidi = rhNotes.concat(lhNotes).sort(function(a,b){ return a - b; });
        if (allMidi.length === 0) return { kept: [], dropped: [] };

        var bass   = lhNotes.length > 0 ? Math.min.apply(null, lhNotes) : Math.min.apply(null, rhNotes);
        var melody = rhNotes.length > 0 ? Math.max.apply(null, rhNotes) : Math.max.apply(null, lhNotes);
        var bassPC = bass % 12;

        // Deduplicate by pitch class, keep lowest occurrence
        var seen = {};
        var pool = [];
        allMidi.forEach(function(m) {
            var pc = m % 12;
            if (!seen[pc]) {
                seen[pc] = true;
                var interval = ((pc - bassPC) + 12) % 12;
                pool.push({ midi: m, pc: pc, interval: interval });
            }
        });

        // Melody octave correction before reduction
        var octaveShifted = false;
        if (melody <= bass + 5) {
            melody += 12;
            octaveShifted = true;
        }

        var kept    = [];
        var dropped = [];

        pool.forEach(function(note) {
            var isBass   = (note.midi === bass);
            var isMelody = (note.midi === melody) || (octaveShifted && note.midi === melody - 12);
            var doSacrifice = SACRIFICE_INTERVALS.indexOf(note.interval) !== -1 && !isBass && !isMelody;

            if (doSacrifice) {
                dropped.push({ midi: note.midi, reason: intervalLabel(note.interval) });
            } else {
                kept.push({ midi: isMelody && octaveShifted ? note.midi + 12 : note.midi,
                            isBass: isBass, isMelody: isMelody });
            }
        });

        // Enforce MAX_NOTES: drop non-essential notes if still too many
        if (kept.length > MAX_NOTES) {
            var essential = kept.filter(function(n){ return n.isBass || n.isMelody; });
            var extras    = kept.filter(function(n){ return !n.isBass && !n.isMelody; });
            var slots     = MAX_NOTES - essential.length;
            kept   = essential.concat(extras.slice(0, slots));
            dropped = dropped.concat(extras.slice(slots).map(function(n){
                return { midi: n.midi, reason: "surcharge" };
            }));
        }

        kept.sort(function(a,b){ return a.midi - b.midi; });
        return { kept: kept, dropped: dropped, octaveShifted: octaveShifted };
    }

    // ─── String assignment ────────────────────────────────────────────────────
    // Assigns each kept note to a guitar string (lowest fret preference).
    // Returns array of { stringIdx, fret, midi } sorted low→high string.
    function assignToStrings(notes) {
        var guitarMin = STRING_TUNING[0];
        var guitarMax = STRING_TUNING[5] + MAX_FRET;
        var usedStrings = {};
        var result = [];

        var inRange = notes.filter(function(n){
            return n.midi >= guitarMin && n.midi <= guitarMax;
        });

        inRange.forEach(function(note) {
            var bestStr  = -1;
            var bestFret = 999;
            for (var s = 0; s < STRING_TUNING.length; s++) {
                if (usedStrings[s]) continue;
                var fret = note.midi - STRING_TUNING[s];
                if (fret >= 0 && fret <= MAX_FRET && fret < bestFret) {
                    bestStr  = s;
                    bestFret = fret;
                }
            }
            if (bestStr !== -1) {
                usedStrings[bestStr] = true;
                result.push({ stringIdx: bestStr, fret: bestFret, midi: note.midi,
                              isBass: note.isBass, isMelody: note.isMelody });
            }
        });

        return result.sort(function(a,b){ return a.stringIdx - b.stringIdx; });
    }

    // ─── Write tablature ─────────────────────────────────────────────────────
    function writeToTabStaff(score, tabStaffIdx, tick, tabNotes, duration) {
        if (tabNotes.length === 0) return;
        var cursor = score.newCursor();
        cursor.staffIdx  = tabStaffIdx;
        cursor.duration  = duration;
        cursor.rewindToTick(tick);
        cursor.addNote(tabNotes[0].midi);

        var chord = cursor.element;
        // Add remaining notes to same chord
        for (var i = 1; i < tabNotes.length; i++) {
            cursor.addNote(tabNotes[i].midi, true);  // true = add to chord
        }
        // Annotate string/fret info for each note
        if (chord && chord.notes) {
            for (var j = 0; j < chord.notes.length && j < tabNotes.length; j++) {
                chord.notes[j].string = tabNotes[j].stringIdx;
                chord.notes[j].fret   = tabNotes[j].fret;
            }
        }
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────
    function intervalLabel(semitones) {
        var labels = {0:"fond.",1:"♭2",2:"2e/9e",3:"3e min",4:"3e maj",
                      5:"4e",6:"♭5",7:"5e",8:"5e+",9:"6e",10:"7e min",11:"7e maj",14:"9e"};
        return labels[semitones] || "?";
    }
}

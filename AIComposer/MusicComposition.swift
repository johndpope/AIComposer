//
//  MusicComposition.swift
//  AIComposer
//
//  Created by Jess Hendricks on 11/21/15.
//  Copyright © 2015 Jess Hendricks. All rights reserved.
//

import Cocoa
import AudioToolbox

class MusicComposition: NSObject, NSCoding {
    
    internal private(set) var musicParts: [MusicPart]!
    internal private(set) var musicSequence = MusicSequence()
    
    //  Info variables
    internal private(set) var name: String!
    internal private(set) var tempo: Int!
    internal private(set) var numberOfMeasures: Int!
    internal private(set) var numberOfParts: Int!
    internal private(set) var chordProgressionString = ""
    var fitnessScore = 0.0
    var silenceFitness = 0.0
    var chordFitness = 0.0
    var noteFitness = 0.0
    var dynamicsFitness = 0.0
    var rhythmicFitness = 0.0
    var numberOfGenerations = 0
    var numberOfCompositionGenes = 0
    
    override init() {
        self.musicParts = [MusicPart]()
        self.name = "New Composition"
        self.tempo = 0
        self.numberOfMeasures = 0
        super.init()
    }
    
    //  Creates a fresh copy from a previous composition object
    init(composition: MusicComposition) {
        self.name = composition.name
        self.tempo = composition.tempo
        self.numberOfMeasures = composition.numberOfMeasures
        self.numberOfParts = composition.numberOfParts
        self.chordProgressionString = composition.chordProgressionString
        self.fitnessScore = composition.fitnessScore
        self.silenceFitness = composition.silenceFitness
        self.chordFitness = composition.chordFitness
        self.dynamicsFitness = composition.dynamicsFitness
        self.rhythmicFitness = composition.rhythmicFitness
        self.numberOfGenerations = composition.numberOfGenerations
        self.numberOfCompositionGenes = composition.numberOfCompositionGenes
        
        self.musicParts = [MusicPart]()
        for part in composition.musicParts {
            var newMeasures = [MusicMeasure]()
            for measure in part.measures {
                newMeasures.append(MusicMeasure(musicMeasure: measure))
            }
            self.musicParts.append(MusicPart(measures: newMeasures, preset: (preset: part.soundPreset, minNote: part.minNote, maxNote: part.maxNote)))
        }
        super.init()
        self.createMusicSequence()
    }
    
    init(name: String, musicParts: [MusicPart], numberOfMeasures: Int) {
        self.name = name
        self.musicParts = musicParts
        self.numberOfMeasures = numberOfMeasures
        super.init()
        self.createMusicSequence()
        self.generateChordProgressionString()
    }
    
    required init(coder aDecoder: NSCoder)  {
        self.name = aDecoder.decodeObjectForKey("Name") as! String
        self.musicParts = aDecoder.decodeObjectForKey("Parts") as! [MusicPart]
        self.numberOfMeasures = aDecoder.decodeIntegerForKey("Number of Measures")
        self.fitnessScore = aDecoder.decodeDoubleForKey("Fitness Score")
        self.silenceFitness = aDecoder.decodeDoubleForKey("Silence Fitness Score")
        self.chordFitness = aDecoder.decodeDoubleForKey("Chord Fitness Score")
        self.noteFitness = aDecoder.decodeDoubleForKey("Note Fitness Score")
        self.dynamicsFitness = aDecoder.decodeDoubleForKey("Dynamics Fitness Score")
        self.rhythmicFitness = aDecoder.decodeDoubleForKey("Rhythmic Fitness Score")
        self.numberOfGenerations = aDecoder.decodeIntegerForKey("Number of Generations")
        self.numberOfCompositionGenes = aDecoder.decodeIntegerForKey("Number of Composition Genes")
        super.init()
        self.createMusicSequence()
        self.generateChordProgressionString()
    }
    
    func encodeWithCoder(aCoder: NSCoder) {
        aCoder.encodeObject(self.name, forKey: "Name")
        aCoder.encodeObject(self.musicParts, forKey: "Parts")
        aCoder.encodeInteger(self.numberOfMeasures, forKey: "Number of Measures")
        aCoder.encodeDouble(self.fitnessScore, forKey: "Fitness Score")
        aCoder.encodeDouble(self.silenceFitness, forKey: "Silence Fitness Score")
        aCoder.encodeDouble(self.chordFitness, forKey: "Chord Fitness Score")
        aCoder.encodeDouble(self.noteFitness, forKey: "Note Fitness Score")
        aCoder.encodeDouble(self.dynamicsFitness, forKey: "Dynamics Fitness Score")
        aCoder.encodeDouble(self.rhythmicFitness, forKey: "Rhythmic Fitness Score")
        aCoder.encodeInteger(self.numberOfGenerations, forKey: "Number of Generations")
        aCoder.encodeInteger(self.numberOfCompositionGenes, forKey: "Number of Composition Genes")
    }
    
    private func createMusicSequence() {
        if !musicParts.isEmpty {
            NewMusicSequence(&self.musicSequence)
            MusicSequenceSetSequenceType(self.musicSequence, MusicSequenceType.Beats)
            
            var tempoTrack = MusicTrack()
            MusicSequenceGetTempoTrack(self.musicSequence, &tempoTrack)
            
            
            //  Time signatures Meta events seem to be broken in Swift, but that shouldn't be an issue
            //  Get the tempo from measures in the FIRST part in the array
            var previousTempo = musicParts[0].measures[0].tempo
            MusicTrackNewExtendedTempoEvent(tempoTrack, 0.0, previousTempo)
            for measure in musicParts[0].measures {
                if measure.tempo != previousTempo {
                    MusicTrackNewExtendedTempoEvent(tempoTrack, measure.firstBeatTimeStamp, measure.tempo)
                    previousTempo = measure.tempo
                }
            }
            for partIndex in 0..<self.musicParts.count {
                self.addPartToSequence(self.musicParts[partIndex], partNumber: UInt8(partIndex))
            }
            
            //  Update info variables
            self.numberOfParts = self.musicParts.count
            self.tempo = Int(musicParts[0].measures[0].tempo)
        }
    }
    
    func addPartToSequence(part: MusicPart, partNumber: UInt8) {
        var nextTrack = MusicTrack()
        MusicSequenceNewTrack(self.musicSequence, &nextTrack)
        
        
        //  Set sound preset
        var chanmess = MIDIChannelMessage(status: 0xB0, data1: 0, data2: 0, reserved: 0)
        MusicTrackNewMIDIChannelEvent(nextTrack, 0.0, &chanmess)
        chanmess = MIDIChannelMessage(status: 0xB0, data1: 32, data2: 0, reserved: 0)
        MusicTrackNewMIDIChannelEvent(nextTrack, 0, &chanmess)
        chanmess = MIDIChannelMessage(status: 0xC0 + partNumber, data1: part.soundPreset, data2: 0, reserved: 0)
        MusicTrackNewMIDIChannelEvent(nextTrack, 0, &chanmess)
        
        for measure in part.measures {
            for note in measure.notes {
                var midiNoteMessage = MIDINoteMessage()
                midiNoteMessage.channel = note.midiNoteMess.channel
                midiNoteMessage.duration = note.midiNoteMess.duration
                midiNoteMessage.note = UInt8(Int(note.midiNoteMess.note) + measure.keySig)
                midiNoteMessage.releaseVelocity = note.midiNoteMess.releaseVelocity
                midiNoteMessage.velocity = note.midiNoteMess.velocity
                MusicTrackNewMIDINoteEvent(nextTrack, note.timeStamp, &midiNoteMessage)
                
            }
        }
        let lastMeasure = part.measures[part.measures.count - 1]
        let lastTime = lastMeasure.firstBeatTimeStamp + MusicTimeStamp(lastMeasure.timeSignature.numberOfBeats)
        var silentNoteForSpace = MIDINoteMessage(channel: 0, note: 0, velocity: 0, releaseVelocity: 0, duration: 2.0)
        MusicTrackNewMIDINoteEvent(nextTrack, lastTime + 3.0, &silentNoteForSpace)
    }
    
    private func generateChordProgressionString() {
        if self.musicParts.count != 0 {
            for measure in self.musicParts[0].measures {
                self.chordProgressionString = self.chordProgressionString + "\(measure.chord.name) ➝ "
            }
            self.chordProgressionString = self.chordProgressionString + "END"
        }
    }
    
    func exchangeMusicPart(partNumber partNum: Int, newPart: MusicPart) -> MusicPart {
        let returnPart = MusicPart(musicPart: self.musicParts[partNum])
        self.musicParts[partNum] = MusicPart(musicPart: newPart)
        return returnPart
    }
    
    func exchangeMeasure(partNumber partNum: Int, measureNum: Int, newMeasure: MusicMeasure) -> MusicMeasure {
        let returnMeasure = MusicMeasure(musicMeasure: self.musicParts[partNum].measures[measureNum])
        self.musicParts[partNum].setMeasure(measureNum: measureNum, newMeasure: newMeasure)
        return returnMeasure
    }
    
    func finishComposition() {
        for partIndex in 0..<self.musicParts.count {
            for measureIndex in 0..<self.musicParts[partIndex].measures.count {
                self.musicParts[partIndex].measures[measureIndex].humanizeNotes()
            }
        }
    }
    
    
    //  Returns a formatted String for display in the Table View
    var dataString: String {
        var fitnessString = String(format: "\t\tFitness score: %.1f /%.0f", self.fitnessScore, EXPECTED_FITNESS)
        fitnessString = fitnessString + String(format: "\nSilence: %.1f /%.0f", self.silenceFitness, EXPECTED_SILENCE)
        fitnessString = fitnessString + String(format: " ... Chord: %.1f /%.0f", self.chordFitness, EXPECTED_CHORD_DISSONANCE)
        fitnessString = fitnessString + String(format: " ... Note: %.1f /%.0f", self.noteFitness, EXPECTED_NOTE_DISSONANCE)
        fitnessString = fitnessString + String(format: " ... Dynamics: %.1f /%.0f", self.dynamicsFitness, EXPECTED_DYNAMICS)
        fitnessString = fitnessString + String(format: " ... Rhythmic: %.1f /%.0f", self.rhythmicFitness, EXPECTED_RHYTHMIC_VAR)
        fitnessString = fitnessString + "\nGenerations: \(self.numberOfGenerations)\t\t\tGenes: \(self.numberOfCompositionGenes)"

        return "Tempo: \(self.tempo)\t\(self.numberOfMeasures) measures\t\(self.numberOfParts) parts \(fitnessString)"
    }
}

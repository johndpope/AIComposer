//
//  MIDIFileParser.swift
//  AIComposer
//
//  Created by Jess Hendricks on 10/27/15.
//  Copyright © 2015 Jess Hendricks. All rights reserved.
//

import Cocoa
import CoreMIDI
import CoreAudio
import AudioToolbox

/// The `Singleton` instance
private let MIDIFileParserInstance = MIDIFileParser()

class MIDIFileParser: NSObject {
    
    //  Returns the singleton instance
    class var sharedInstance:MIDIFileParser {
        return MIDIFileParserInstance
    }
    
    /*
    *   Load the MIDI file
    *   For now MIDI files should just be small motivic ideas between 2 - 32 quarter notes in length
    *   Returns the midi note data, time resolution
    */
    func loadMIDIFile(filePathString: String) -> (tempoTrack: MusicTrack,
        midiNotes: [(midiNoteMessage: MIDINoteMessage,
        barBeatTime: CABarBeatTime,
        timeStamp: MusicTimeStamp)],
        timeResolution: UInt32,
        timeSigEvents: [(numbeats: UInt8, lengthOfBeat: UInt8, timeStamp: MusicTimeStamp)],
        eventMarkers: [MusicTimeStamp])
    {
        // Load the MIDI File
        var sequence = MusicSequence()
        NewMusicSequence(&sequence)
        
        let midiFileURL = NSURL(fileURLWithPath: filePathString)
        MusicSequenceFileLoad(sequence, midiFileURL, MusicSequenceFileTypeID.MIDIType, MusicSequenceLoadFlags.SMF_ChannelsToTracks)
        
        let timeResolution = self.determineTimeResolutionOfSequence(sequence)
        let midiNoteEvents = parseMIDIEventTracks(sequence, timeResolution: timeResolution)
        let tempoTrackData = parseTempoTrack(sequence)
        return (tempoTrackData.musicTrack, midiNoteEvents.midiEvents, tempoTrackData.timeRes, tempoTrackData.timeSigEvents, midiNoteEvents.eventMarkers)
    }
    
    func createMIDIFile(
        var filePathString: String,
        sequence: MusicSequence)
    {
        if filePathString.rangeOfString(".mid") == nil {
            filePathString = filePathString + ".mid"
        }
        let midiFileURL = NSURL(fileURLWithPath: filePathString)
        
        MusicSequenceFileCreate(sequence, midiFileURL, MusicSequenceFileTypeID.MIDIType, MusicSequenceFileFlags.EraseFile, 0)
    }
    
    private func parseTempoTrack(sequence: MusicSequence) ->
        (musicTrack:    MusicTrack,
        timeRes:        UInt32,
        timeSigEvents:  [(numbeats: UInt8, lengthOfBeat: UInt8, timeStamp: MusicTimeStamp)])
    {
        
        // Get the Tempo Track
        var tempoTrack = MusicTrack()
        MusicSequenceGetTempoTrack(sequence, &tempoTrack)
        let timeResolution = determineTimeResolutionOfSequence(sequence)
        
        // Create an iterator that will loop through the events in the track
        var iterator = MusicEventIterator()
        NewMusicEventIterator(tempoTrack, &iterator);
        
        var hasNext:DarwinBoolean = true
        var timestamp: MusicTimeStamp = 0
        var eventType: MusicEventType = 0
        var eventDataSize: UInt32 = 0
        var eventData: UnsafePointer<Void> = nil
        CAShow(UnsafeMutablePointer<MusicSequence>(sequence))
        
        // Run the loop
        MusicEventIteratorHasCurrentEvent(iterator, &hasNext);
        var timeSigEvents = [(numbeats: UInt8, lengthOfBeat: UInt8, timeStamp: MusicTimeStamp)]()
        while (hasNext) {
            MusicEventIteratorGetEventInfo(iterator, &timestamp, &eventType, &eventData, &eventDataSize);
            if eventType == kMusicEventType_Meta {
                let eventMetaData = UnsafePointer<MIDIMetaEvent>(eventData)
                let midiMessage = eventMetaData.memory
                let beats = eventMetaData.memory.data
                let beatLength = eventMetaData.memory.data
                print("\n---------------------------------\nMeta event found\n\tdata length: \(midiMessage.dataLength)\n\ttype: \(midiMessage.metaEventType)\n\tbeats: \(beats)\n\tMeta Info: \(eventMetaData.memory)")
                if midiMessage.metaEventType == 0x58 {
                    timeSigEvents.append((midiMessage.data, beatLength, timestamp))
                }
            }
            MusicEventIteratorNextEvent(iterator);
            MusicEventIteratorHasCurrentEvent(iterator, &hasNext);
        }
        return (tempoTrack, timeResolution, timeSigEvents)
    }
    
    
    private func determineTimeResolutionOfSequence(sequence: MusicSequence) -> UInt32
    {
        var timeResolution:UInt32  = 0
        var propertyLength:UInt32  = 0
        // Get the Tempo Track
        var tempoTrack = MusicTrack()
        MusicSequenceGetTempoTrack(sequence, &tempoTrack)
        
        MusicTrackGetProperty(tempoTrack,kSequenceTrackProperty_TimeResolution, &timeResolution, &propertyLength);
        
        print("propertyLength: \(propertyLength)")
        print("timeResolution: \(timeResolution)")
        
        return timeResolution
    }
    
    private func parseTrackForMIDIEvents(iterator: MusicEventIterator, sequence: MusicSequence, timeResolution: UInt32) -> (
        midiEvents:[(midiNoteMessage: MIDINoteMessage,
        barBeatTime: CABarBeatTime,
        timeStamp: MusicTimeStamp)],
        eventMarkers: [MusicTimeStamp])
    {
        
        var hasNext:DarwinBoolean = true
        var timestamp: MusicTimeStamp = 0
        var eventType: MusicEventType = 0
        var eventDataSize: UInt32 = 0
        var eventData: UnsafePointer<Void> = nil
        
        MusicEventIteratorHasCurrentEvent(iterator, &hasNext)
        
        var notesForTrack = [(midiNoteMessage: MIDINoteMessage,
            barBeatTime: CABarBeatTime,
            timeStamp: MusicTimeStamp)]()
        var eventMarkers = [MusicTimeStamp]()
        while (hasNext) {
            MusicEventIteratorGetEventInfo(iterator, &timestamp, &eventType, &eventData, &eventDataSize)
            if eventType == kMusicEventType_MIDINoteMessage {
                var barBeatTime = CABarBeatTime()
                MusicSequenceBeatsToBarBeatTime(sequence, timestamp, timeResolution, &barBeatTime)
                let noteMessage = UnsafePointer<MIDINoteMessage>(eventData).memory
                notesForTrack.append((noteMessage, barBeatTime, timestamp))
            } else if eventType == kMusicEventType_MIDIChannelMessage {
                let channelMessage = UnsafePointer<MIDIChannelMessage>(eventData)
                print("Control change received: \(channelMessage.memory.status), data1: \(channelMessage.memory.data1), data2: \(channelMessage.memory.data2)")
                if channelMessage.memory.data1 == 20 {
                    eventMarkers.append(timestamp)
                }
            }
            MusicEventIteratorNextEvent(iterator);
            MusicEventIteratorHasCurrentEvent(iterator, &hasNext);
        }
        return (notesForTrack, eventMarkers)
    }
    
    private func parseMIDIEventTracks(
        sequence: MusicSequence,
        timeResolution: UInt32) -> (midiEvents: [(midiNoteMessage:  MIDINoteMessage,
        barBeatTime:    CABarBeatTime,
        timeStamp:  MusicTimeStamp)],
        eventMarkers: [MusicTimeStamp])
    {
        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(sequence, &trackCount)
        print("Parsing \(trackCount) tracks.")
        var notes = [(midiNoteMessage: MIDINoteMessage,
            barBeatTime: CABarBeatTime,
            timeStamp: MusicTimeStamp)]()
        var eventMarkers = [MusicTimeStamp]()
        var track: MusicTrack = nil
        for (var index:UInt32 = 0; index < trackCount; index++) {
            MusicSequenceGetIndTrack(sequence, index, &track)
            var iterator: MusicEventIterator = nil
            NewMusicEventIterator(track, &iterator)
            let parsedEventsForTrack = self.parseTrackForMIDIEvents(iterator, sequence: sequence, timeResolution: timeResolution)
            eventMarkers.appendContentsOf(parsedEventsForTrack.eventMarkers)
            notes.appendContentsOf(parsedEventsForTrack.midiEvents)
        }
        return (notes, eventMarkers)
    }
    
}

//
//  AudioMaster.swift
//  SoundNav
//
//  Created by Thom Yorke on 30/07/2019.
//  Copyright © 2019 steinwang13. All rights reserved.
//

import Foundation
import AVFoundation
import CoreLocation

class AudioMaster {
    let audioEngine = AVAudioEngine()
    let audioEnvironment = AVAudioEnvironmentNode()
    var destinationLocation: CLLocationCoordinate2D?
    var destinationSoundSource: AVAudioPlayerNode?
    
    func setSoundSourcePosition(location: CLLocationCoordinate2D) {
        destinationLocation = location
    }
    
    func setListenerOrientation(yaw: Float, pitch: Float, row: Float) {
        audioEnvironment.listenerAngularOrientation = AVAudioMake3DAngularOrientation(yaw, pitch, row)
    }
    
    func setListenerPosition(x: Float, y: Float, z: Float) {
        audioEnvironment.listenerPosition = AVAudio3DPoint(x: x, y: y, z: z)
    }
    
    func playEndSound() {
        let reachSoundSource = createSoundSource("bell", atPosition: audioEnvironment.listenerPosition, volume: 3)
        
        reachSoundSource.play()
        destinationSoundSource?.stop()
    }
    
    func playSpatialSound() {
        audioEngine.stop()
        
        destinationSoundSource = createSoundSource("drumloop", atPosition: AVAudio3DPoint(x: Float(destinationLocation!.latitude), y: 0, z: Float(destinationLocation!.longitude)), volume: 5)
        
        audioEngine.connect(audioEnvironment, to: audioEngine.mainMixerNode, format: nil)
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            destinationSoundSource?.play()
            print("Started")
        } catch let e as NSError {
            print("Couldn't start engine", e)
        }
    }
    
    func createSoundSource(_ file: String, withExtension ext: String = "wav", atPosition position: AVAudio3DPoint, volume: Float) -> AVAudioPlayerNode {
        let node = AVAudioPlayerNode()
        node.position = position
        node.reverbBlend = 0.1
        node.renderingAlgorithm = .HRTF
        node.volume = volume
        
        let url = Bundle.main.url(forResource: file, withExtension: ext)!
        let file = try! AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        try! file.read(into: buffer!)
        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEnvironment, format: buffer!.format)
        node.scheduleBuffer(buffer!, at: nil, options: .loops, completionHandler: nil)
        
        return node
    }
}

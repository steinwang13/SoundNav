//
//  DataRecorder.swift
//  SoundNav
//
//  Created by Thom Yorke on 30/07/2019.
//  Copyright © 2019 steinwang13. All rights reserved.
//

import Foundation
import CoreLocation

// Records location data, including time, longitude, latitude, speed and average speed.
class DataRecorder {
    var data = [[String]]()
    var row = [String]()
    var avgSpeed: CLLocationSpeed {
        return speeds.reduce(0,+)/Double(speeds.count)
    }
    var speeds = [CLLocationSpeed]()
    
    var isRecording = false
    
    func addDataByRow(newRow: [String]) {
        if isRecording == true {
            data.append(newRow)
            writeCSV(arrays: data, headers: ["Timestamp", "Longitude", "Latitude", "Speed(m/s)", "Avg. Speed(m/s)"], filename: String("Beacon-Short-UserMotionLog-1.csv"))
        }
    }
    
    func recordGivenRoute(coordinates: [[String]]) {
        writeCSV(arrays: coordinates, headers: ["ID", "Longitude", "Latitude"], filename: String("Long-GivenRoute.csv"))
    }
    
    func writeCSV(arrays: [[String]], headers: [String], filename: String) {
        let numCollumns = arrays.count
        let numRows = arrays.first!.count
        var output = "\(headers.joined(separator: ", "))\n"
        
        for r in 0...numCollumns-1 {
            var row = ""
            for c in 0...numRows-1 {
                row = c == 0 ? arrays[r][c] : row.appending(",  \(arrays[r][c])")
            }
            output = output.appending("\(row)\n")
        }
        
        let localDocumentsURL = FileManager.default.urls(for: FileManager.SearchPathDirectory.documentDirectory, in: .userDomainMask).last
        let myLocalFile = localDocumentsURL?.appendingPathComponent(filename)
        
        guard myLocalFile != nil else {
            print("----------- Couldn't create local file!")
            return
        }
        
        do {
            try output.write(to: myLocalFile!, atomically: true, encoding: String.Encoding.utf8)
        }
        catch let error as NSError {
            print(error.localizedDescription)
            return
        }
        print("Wrote CSV to: \(myLocalFile!)")
    }
}

//
//  ViewController.swift
//  SoundNav
//
//  Created by steinwang13 on 11/07/2019.
//  Copyright © 2019 steinwang13. All rights reserved.
//

import UIKit
import Mapbox
import MapboxCoreNavigation
import MapboxNavigation
import MapboxDirections
import AVFoundation


class ViewController: UIViewController, MGLMapViewDelegate, CLLocationManagerDelegate, NavigationMapViewDelegate, NavigationViewControllerDelegate {
    
    
    var mapView: NavigationMapView?
    var currentRoute: Route? {
        get {
            return routes?.first
        }
        set {
            guard let selected = newValue else { routes?.remove(at: 0); return }
            guard let routes = routes else { self.routes = [selected]; return }
            self.routes = [selected] + routes.filter { $0 != selected }
        }
    }
    var routes: [Route]? {
        didSet {
            guard let routes = routes, let current = routes.first else { mapView?.removeRoutes(); return }
            mapView?.showRoutes(routes)
            mapView?.showWaypoints(current)
        }
    }
    var startButton: UIButton?
    var locationManager = CLLocationManager()
    var longitudeLabel: UILabel?
    var latitudeLabel: UILabel?
    var headingLabel: UILabel?
    var speedLabel: UILabel?
    var avgSpeedLabel: UILabel?
    
    private typealias RouteRequestSuccess = (([Route]) -> Void)
    private typealias RouteRequestFailure = ((NSError) -> Void)
    
    let audioEngine = AVAudioEngine()
    let audioEnvironment = AVAudioEnvironmentNode()
    var soundSource: AVAudioPlayerNode?
    
    var index = 0
    
    var data = [[String]]()
    var row = [String]()
    var speeds = [CLLocationSpeed]()
    
    var isRecording = false
    
    var navigationService: MapboxNavigationService?
    var simulatedLocationManager: CLLocationManager?
    var destination: CLLocationCoordinate2D?
    
    var userArrivedAtDestination = false
    
    //MARK: - Lifecycle Methods
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingHeading()
        locationManager.startUpdatingLocation()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        // Add MapView form Mapbox
        mapView = NavigationMapView(frame: view.bounds)
        mapView?.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView?.userTrackingMode = .follow
        mapView?.delegate = self
        mapView?.navigationMapViewDelegate = self
        mapView?.showsUserHeadingIndicator = true
        
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        mapView?.addGestureRecognizer(gesture)
        
        view.addSubview(mapView!)
        mapView?.styleURL = MGLStyle.outdoorsStyleURL // or streetsStyleURL
        
        longitudeLabel = UILabel(frame: CGRect(x: 32, y: 45, width: 273, height: 21))
        longitudeLabel?.text = "Longitude"
        view.addSubview(longitudeLabel!)
        latitudeLabel = UILabel(frame: CGRect(x: 32, y: 87, width: 273, height: 21))
        latitudeLabel?.text = "Latitude"
        view.addSubview(latitudeLabel!)
        headingLabel = UILabel(frame: CGRect(x: 32, y: 129, width: 273, height: 21))
        headingLabel?.text = "Heading"
        view.addSubview(headingLabel!)
        speedLabel = UILabel(frame: CGRect(x: 32, y: 171, width: 273, height: 21))
        speedLabel?.text = "Speed"
        view.addSubview(speedLabel!)
        avgSpeedLabel = UILabel(frame: CGRect(x: 32, y: 213, width: 273, height: 21))
        avgSpeedLabel?.text = "AvgSpeed"
        view.addSubview(avgSpeedLabel!)
        
        startButton = UIButton()
        startButton?.setTitle("Start Navigation", for: .normal)
        startButton?.translatesAutoresizingMaskIntoConstraints = false
        startButton?.backgroundColor = .blue
        startButton?.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        startButton?.addTarget(self, action: #selector(tappedButton(sender:)), for: .touchUpInside)
        startButton?.isHidden = true
        view.addSubview(startButton!)
        startButton?.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -20).isActive = true
        startButton?.centerXAnchor.constraint(equalTo: self.view.centerXAnchor).isActive = true
        view.setNeedsLayout()
    }
    
    //overriding layout lifecycle callback so we can style the start button
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        startButton?.layer.cornerRadius = startButton!.bounds.midY
        startButton?.clipsToBounds = true
        startButton?.setNeedsDisplay()
        
        audioEngine.attach(audioEnvironment)
        
        audioEnvironment.reverbParameters.enable = true
        audioEnvironment.reverbParameters.loadFactoryReverbPreset(.smallRoom)
    }
    
    @objc func tappedButton(sender: UIButton) {
        guard let route = currentRoute else { return }
        // For demonstration purposes, simulate locations if the Simulate Navigation option is on.
        navigationService = MapboxNavigationService(route: route, simulating: SimulationMode.always) // onPoorGPS
        let navigationOptions = NavigationOptions(navigationService: navigationService)
        let navigationViewController = NavigationViewController(for: route, options: navigationOptions)
        navigationViewController.delegate = self
        simulatedLocationManager = navigationService?.locationManager
        simulatedLocationManager?.startUpdatingLocation()
        
        present(navigationViewController, animated: true, completion: nil)
        
        //        recordGivenRoute()
        isRecording = true
    }
    
//    func recordGivenRoute() {
//        var givenRoute = [[String]]()
//        if let givenRouteCoordinates = self.currentRoute?.coordinates {
//            for i in 0 ..< givenRouteCoordinates.count {
//                givenRoute.append([String(i), givenRouteCoordinates[i].longitude.description, givenRouteCoordinates[i].latitude.description])
//            }
//            print("Finished reading given route into 2D string.")
//        }
//        writeCSV(arrays: givenRoute, headers: ["ID", "Longitude", "Latitude"], filename: String("Short-GivenRoute.csv"))
//    }
    
    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .ended else { return }
        
        let spot = gesture.location(in: mapView)
        guard let location = mapView?.convert(spot, toCoordinateFrom: mapView) else { return }
        
        // Long route destination: 51.454952, -2.609714 (51.4557931, -2.6108597). Starting point: 51.4534538, -2.6081318
        // Short route destination: 51.4534538, -2.6081318. Starting point: 51.4537456, -2.6050194
        let longRouteDestination = CLLocationCoordinate2D(latitude: 51.4557931, longitude: -2.6108597)
        let shortRouteDestination = CLLocationCoordinate2D(latitude: 51.4534538, longitude: -2.6081318)
        destination = location
        
        audioEngine.stop()
        
        if self.routes != nil {
            soundSource = self.createSoundSource("Constant-Brass", atPosition: AVAudio3DPoint(x: Float((self.currentRoute?.coordinates![index].latitude)!), y: 0, z: Float((self.currentRoute?.coordinates![index].longitude)!)), volume: 5, options: .loops)
        }
        
        audioEngine.connect(audioEnvironment, to: audioEngine.mainMixerNode, format: nil)
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            soundSource?.play()
            print("Engine started")
        } catch let e as NSError {
            print("Couldn't start engine", e)
        }
        
        requestRoute(destination: destination!)
        isRecording = false
    }
    
    func requestRoute(destination: CLLocationCoordinate2D) {
        guard let userLocation = mapView?.userLocation!.location else { return }
        let shortStartPoint = CLLocation(latitude: 51.4537456, longitude: -2.6050194)
        let longStartPoint = CLLocation(latitude: 51.4534538, longitude: -2.6081318)
        let userWaypoint = Waypoint(location: userLocation, heading: mapView?.userLocation?.heading, name: "user") //location: shortStartPoint longStartPoint
        let destinationWaypoint = Waypoint(coordinate: destination)
        
        let options = NavigationRouteOptions(waypoints: [userWaypoint, destinationWaypoint], profileIdentifier: MBDirectionsProfileIdentifier.walking)
        //        options.speed = 0.8
        
        Directions.shared.calculate(options) { (waypoints, routes, error) in
            guard let routes = routes else { return }
            self.routes = routes
            self.startButton?.isHidden = false
            self.mapView?.showRoutes(routes)
            self.mapView?.showWaypoints(self.currentRoute!)
        }
    }
    
    // Delegate method called when the user selects a route
    func navigationMapView(_ mapView: NavigationMapView, didSelect route: Route) {
        self.currentRoute = route
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let lastlocation = locations.last
        let lastLongitude = lastlocation?.coordinate.longitude
        let lastLatitude = lastlocation?.coordinate.latitude
        
        longitudeLabel?.text = lastLongitude?.description
        latitudeLabel?.text = lastLatitude?.description
        
        audioEnvironment.listenerPosition = AVAudio3DPoint(x: Float(lastLatitude!), y: 0, z: Float(lastLongitude!))
        
        if self.routes != nil && index < (self.currentRoute?.coordinates?.count)! {
            let nextCoordinate = self.currentRoute?.coordinates![index]
            let distanceToNextCoordinate = nextCoordinate?.distance(to: (lastlocation?.coordinate)!)
            //            print("Current Coordinate is: \(String(describing: nextCoordinate))")

            if distanceToNextCoordinate != nil {
                soundSource?.position = AVAudio3DPoint(x: Float(nextCoordinate!.latitude), y: 0, z: Float(nextCoordinate!.longitude))

                //                print("Distance To Next Coordinate: \(String(describing: distanceToNextCoordinate))")
                if Float((distanceToNextCoordinate?.description)!)! <= 15 {
                    index += 1

                    let reachCurrentCoordinateSoundSource = createSoundSource("bell", atPosition: audioEnvironment.listenerPosition, volume: 3, options: .interruptsAtLoop)
                    reachCurrentCoordinateSoundSource.play()
                }
            }
        }
        
        if isRecording && Float((lastlocation?.distance(from: (simulatedLocationManager?.location)!))!) > 30 {
            simulatedLocationManager?.stopUpdatingLocation()
        }
        else {
            simulatedLocationManager?.startUpdatingLocation()
        }
        
        var speed = lastlocation?.speed
        if Double(speed!) < 0 {
            speed = 0
        }
        speeds.append(speed!)
        
        var avgSpeed: CLLocationSpeed {
            return speeds.reduce(0,+) / Double(speeds.count)
        }
        
        speedLabel?.text = speed?.description
        avgSpeedLabel?.text = String(avgSpeed)
        
        if isRecording == true {
            row = [Date().description, (lastLongitude?.description)!, (lastLatitude?.description)!, (speed?.description)!, String(avgSpeed)]
            data.append(row)
            
            writeCSV(arrays: data, headers: ["Timestamp", "Longitude", "Latitude", "Speed(m/s)", "Avg. Speed(m/s)"], filename: String("TBT-Short-UserMotionLog-1.csv"))
        }
        
        if isRecording {
            let warnSoundSource = createSoundSource("Bleep", atPosition: (soundSource?.position)!, volume: 5, options: .interrupts)
            
            print("Distance to simulatedUser: \(Float((simulatedLocationManager?.location?.distance(from: lastlocation!))!))")
            
            if Float((lastlocation?.distance(from: (simulatedLocationManager?.location)!))!) > 50 {
                warnSoundSource.play()
            }
            else {
                warnSoundSource.stop()
            }
        }
        
        if destination != nil {
            print(Float((destination?.distance(to: (lastlocation?.coordinate)!))!))
        }
        
        if destination != nil && Float((destination?.distance(to: (lastlocation?.coordinate)!))!) <= 15 { // 7.8
            //            userArrivedAtDestination = true
            let reachSoundSource = createSoundSource("bell", atPosition: audioEnvironment.listenerPosition, volume: 3, options: .interrupts)
            
            reachSoundSource.play()
            
            soundSource?.stop()
            
            isRecording = false
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        var lastheading = newHeading.trueHeading + 90
        if lastheading > 180 {
            lastheading -= 360
        }
        
        headingLabel?.text = newHeading.trueHeading.description
        
        audioEnvironment.listenerAngularOrientation = AVAudioMake3DAngularOrientation(Float(lastheading), 0, 0)
    }
    
    func createSoundSource(_ file: String, withExtension ext: String = "wav", atPosition position: AVAudio3DPoint, volume: Float, options: AVAudioPlayerNodeBufferOptions) -> AVAudioPlayerNode {
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
        node.scheduleBuffer(buffer!, at: nil, options: options, completionHandler: nil)
        
        return node
    }
    
    // Show an alert when arriving at the destination.
    func navigationViewController(_ navigationViewController: NavigationViewController, didArriveAt waypoint: Waypoint) -> Bool {
        // End navigation
        navigationViewController.navigationService.endNavigation(feedback: nil)
        
        return false
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


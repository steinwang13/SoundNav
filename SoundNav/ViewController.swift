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
    
    private typealias RouteRequestSuccess = (([Route]) -> Void)
    private typealias RouteRequestFailure = ((NSError) -> Void)
    
    let audioEngine = AVAudioEngine()
    let audioEnvironment = AVAudioEnvironmentNode()

    //MARK: - Lifecycle Methods
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingHeading()
        locationManager.startUpdatingLocation()
        
        // Add MapView form Mapbox
        mapView = NavigationMapView(frame: view.bounds)
        mapView?.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView?.userTrackingMode = .follow
        mapView?.delegate = self
        mapView?.navigationMapViewDelegate = self
        
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
        headingLabel = UILabel(frame: CGRect(x: 32, y: 131, width: 273, height: 21))
        headingLabel?.text = "Heading"
        view.addSubview(headingLabel!)
        
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
        
        audioEngine.attach(audioEnvironment)
    }
    
    //overriding layout lifecycle callback so we can style the start button
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        startButton?.layer.cornerRadius = startButton!.bounds.midY
        startButton?.clipsToBounds = true
        startButton?.setNeedsDisplay()
    }

    @objc func tappedButton(sender: UIButton) {
        guard let route = currentRoute else { return }
        // For demonstration purposes, simulate locations if the Simulate Navigation option is on.
        let navigationService = MapboxNavigationService(route: route, simulating: SimulationMode.always) // onPoorGPS
        let navigationOptions = NavigationOptions(navigationService: navigationService)
        let navigationViewController = NavigationViewController(for: route, options: navigationOptions)
        navigationViewController.delegate = self
        
        present(navigationViewController, animated: true, completion: nil)
    }
    
    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .ended else { return }
        
        let spot = gesture.location(in: mapView)
        guard let location = mapView?.convert(spot, toCoordinateFrom: mapView) else { return }
        
        audioEngine.stop()
        
        let soundSource = self.playSound("drumloop", atPosition: AVAudio3DPoint(x: Float(location.latitude), y: 0, z: Float(location.longitude)))
        
        audioEngine.connect(audioEnvironment, to: audioEngine.mainMixerNode, format: nil)
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            soundSource.play()
            print("Started")
        } catch let e as NSError {
            print("Couldn't start engine", e)
        }
        
        requestRoute(destination: location)
    }
    
    func requestRoute(destination: CLLocationCoordinate2D) {
        guard let userLocation = mapView?.userLocation!.location else { return }
        let userWaypoint = Waypoint(location: userLocation, heading: mapView?.userLocation?.heading, name: "user")
        let destinationWaypoint = Waypoint(coordinate: destination)
        
        let options = NavigationRouteOptions(waypoints: [userWaypoint, destinationWaypoint], profileIdentifier: MBDirectionsProfileIdentifier.walking)
        
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
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        var lastheading = newHeading.trueHeading + 90
        if lastheading > 180 {
            lastheading -= 360
        }
        
        headingLabel?.text = newHeading.trueHeading.description
        
        audioEnvironment.listenerAngularOrientation = AVAudioMake3DAngularOrientation(Float(lastheading), 0, 0)
    }
    
    func playSound(_ file: String, withExtension ext: String = "wav", atPosition position: AVAudio3DPoint) -> AVAudioPlayerNode {
        let node = AVAudioPlayerNode()
        node.position = position
//        node.reverbBlend = 0.1
        node.renderingAlgorithm = .HRTF
        node.volume = 5
        
        let url = Bundle.main.url(forResource: file, withExtension: ext)!
        let file = try! AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        try! file.read(into: buffer!)
        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEnvironment, format: buffer!.format)
        node.scheduleBuffer(buffer!, at: nil, options: .loops, completionHandler: nil)
        
        return node
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        locationManager.stopUpdatingHeading()
        locationManager.stopUpdatingLocation()
    }
}


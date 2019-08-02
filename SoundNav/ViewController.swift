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
    
    let audioMaster = AudioMaster()
    
    let dataRecorder = DataRecorder()

    //MARK: - Lifecycle Methods
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingHeading()
        locationManager.startUpdatingLocation()
        
        setUpMapView()
        
        audioMaster.audioEngine.attach(audioMaster.audioEnvironment)
    }
    
    func setUpMapView() {
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
    }

    @objc func tappedButton(sender: UIButton) {
        guard let route = currentRoute else { return }

        let navigationService = MapboxNavigationService(route: route, simulating: SimulationMode.onPoorGPS) // onPoorGPS
        let navigationOptions = NavigationOptions(navigationService: navigationService)
        let navigationViewController = NavigationViewController(for: route, options: navigationOptions)
        navigationViewController.delegate = self
        
        present(navigationViewController, animated: true, completion: nil)
        
        recordGivenRoute()
        dataRecorder.isRecording = true
    }
    
    func recordGivenRoute() {
        var givenRoute = [[String]]()
        if let givenRouteCoordinates = self.currentRoute?.coordinates {
            for i in 0 ..< givenRouteCoordinates.count {
                givenRoute.append([String(i), givenRouteCoordinates[i].longitude.description, givenRouteCoordinates[i].latitude.description])
            }
            print("Finished reading given route into 2D string.")
        }
        dataRecorder.recordGivenRoute(coordinates: givenRoute)
    }
    
    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .ended else { return }
        
        let spot = gesture.location(in: mapView)
        guard let location = mapView?.convert(spot, toCoordinateFrom: mapView) else { return }
        
        audioMaster.setSoundSourcePosition(location: location)
        audioMaster.playSpatialSound()
        
        requestRoute(destination: location)
        
        dataRecorder.isRecording = false
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
        
        var speed = lastlocation?.speed
        if Double(speed!) < 0 {
            speed = 0
        }
        dataRecorder.speeds.append(speed!)
        
        speedLabel?.text = speed?.description
        avgSpeedLabel?.text = String(dataRecorder.avgSpeed)
        
        dataRecorder.addDataByRow(newRow: [Date().description, (lastLongitude?.description)!, (lastLatitude?.description)!, (speed?.description)!, String(dataRecorder.avgSpeed)])
        
        audioMaster.setListenerPosition(x: Float(lastLatitude!), y: 0, z: Float(lastLongitude!))
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        var lastheading = newHeading.trueHeading + 90
        if lastheading > 180 {
            lastheading -= 360
        }
        
        headingLabel?.text = newHeading.trueHeading.description
        
        audioMaster.setListenerOrientation(yaw: Float(lastheading), pitch: 0, row: 0)
    }
    
    // Show an alert when arriving at the waypoint and wait until the user to start next leg.
    func navigationViewController(_ navigationViewController: NavigationViewController, didArriveAt waypoint: Waypoint) -> Bool {
        // End navigation
        navigationViewController.navigationService.endNavigation(feedback: nil)
        
        audioMaster.playEndSound()
        
        dataRecorder.isRecording = false
        
        return false
    }
}


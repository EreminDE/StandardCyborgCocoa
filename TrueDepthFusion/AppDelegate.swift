//
//  AppDelegate.swift
//  TrueDepthFusion
//
//  Created by Aaron Thompson on 8/12/18.
//

import ARKit
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
	var window: UIWindow?
    
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UserDefaults.standard.register(defaults: [
            "tap_to_start_stop": true,
            "full_resolution_depth_frames": true,
            "stop_scanning_on_reconstruction_failure": true
        ])
        reloadScans()
        
        return true
    }
    
    private(set) var scans: [Scan] = []
    
    private var _scansContainerURL: URL {
        return URL(fileURLWithPath: NSHomeDirectory().appending("/Documents"))
    }
    
    func reloadScans() {
        let urls = try! FileManager.default.contentsOfDirectory(at: _scansContainerURL, includingPropertiesForKeys: nil, options: [])
        let plyURLs = urls
            .filter { $0.pathExtension == "ply" }
            .filter { !$0.lastPathComponent.contains("-mesh") }
        
        scans = plyURLs.map { url in Scan(plyPath: url.path) }
                .sorted { $0.dateCreated.compare($1.dateCreated) == .orderedDescending }
    }
    
    @discardableResult
    func add(_ scan: Scan) -> Bool {
        if scan.plyPath == nil {
            do {
                try scan.write(toContainerPath: _scansContainerURL.path)
                scans.insert(scan, at: 0)
            } catch {
                print("Error saving scan: \(error)")
                return false
            }
        }
        return true
    }
    
    @discardableResult
    func remove(_ scan: Scan) -> Bool {
        if let index = scans.firstIndex(of: scan) {
            do {
                try scan.deleteFiles()
                scans.remove(at: index)
            } catch {
                print("Error deleting files: \(error)")
                return false
            }
        }
        return true
    }
    
    func createBPLYScanDirectory() -> String {
        let directoryName = Scan.string(from: Date())
        let absoluteDirectory = _scansContainerURL.appendingPathComponent(directoryName)
        
        try? FileManager.default.createDirectory(at: absoluteDirectory, withIntermediateDirectories: false, attributes: nil)
        
        return absoluteDirectory.path
    }
    
}

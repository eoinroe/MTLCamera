//
//  ViewController.swift
//  TemplateTest
//
//  Created by Eoin Roe on 27/10/2021.
//

import Cocoa
import MetalKit

// Our macOS specific view controller
class ViewController: NSViewController {

    var renderer: Renderer!
    var mtkView: MTKView!
    
    var sphericalCoordinates = SphericalCoordinates(radialDistance: -8, zenith: 0, azimuth: 0)

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = self.view as? MTKView else {
            print("View attached to ViewController is not an MTKView")
            return
        }

        // Select the device to render with.  We choose the default device
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }

        mtkView.device = defaultDevice

        guard let newRenderer = Renderer(metalKitView: mtkView) else {
            print("Renderer cannot be initialized")
            return
        }

        renderer = newRenderer
        
        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)

        mtkView.delegate = renderer
        
        renderer.camera.position = sphericalCoordinates.pointOnSphere
    }
    
    override func mouseDragged(with event: NSEvent) {
        let sensitivity: Float = 0.005
        
        // What if we instead think of it as choosing a vantage point on a sphere centered on the origin?
        // Then we can use good old spherical coordinates and look-at matrices instead.
        sphericalCoordinates.azimuth += Float(event.deltaX) * sensitivity
        sphericalCoordinates.zenith  += Float(event.deltaY) * sensitivity
        
        // We need to constrain the zenith angle so as to not swap left and right
        sphericalCoordinates.zenith = max(-.pi / 2, min(sphericalCoordinates.zenith, .pi / 2))
        renderer.camera.position = sphericalCoordinates.pointOnSphere
    }
    
    override func scrollWheel(with event: NSEvent) {
        let sensitivity: Float = 0.1
        sphericalCoordinates.radialDistance -= Float(event.deltaY) * sensitivity
        renderer.camera.position = sphericalCoordinates.pointOnSphere
    }
}

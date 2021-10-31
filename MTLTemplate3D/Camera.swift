//
//  Camera.swift
//  TemplateTest
//
//  Created by Eoin Roe on 27/10/2021.
//

import Foundation
import simd

struct SphericalCoordinates {
    var radialDistance: Float, zenith: Float, azimuth: Float
    
    var pointOnSphere: SIMD3<Float> {
        return radialDistance * SIMD3<Float>(x: cos(azimuth) * cos(zenith), y: sin(zenith), z: sin(azimuth) * cos(zenith))
    }
}

/*

struct SphericalCoordinates {
    var radial: Float, zenith: Float, azimuth: Float = 0
    
    var point: SIMD3<Float> {
        return SIMD3<Float>(x: cos(azimuth) * cos(zenith), y: sin(zenith), z: sin(azimuth) * cos(zenith))
    }
    
    var x: Float {
        return cos(azimuth) * cos(zenith)
    }
        
    var y: Float {
        return sin(zenith)
    }
    
    var z: Float {
        return sin(azimuth) * cos(zenith)
    }
}
 
 */

class Camera {
    var position = SIMD3<Float>(repeating: 0)
    var target = SIMD3<Float>(repeating: 0)
    var rotation: Float = 0
    var aspectRatio: Float = 0
    var fovVertHalf: Float = 0
    var distanceNear: Float = 0
    var distanceFar: Float = 0
    
    func getViewMatrix_LH() -> float4x4 {
        return matrix_look_at_left_hand(position, target, vector_float3(0, 1, 0))
    }
    
    func getProjectionMatrix_LH() -> float4x4 {
        return matrix_perspective_left_hand(fovVertHalf * 2.0, aspectRatio, distanceNear, distanceFar)
    }
    
    func getViewMatrix_RH() -> float4x4 {
        return matrix_look_at_right_hand(position, target, vector_float3(0, 1, 0))
    }
    
    func getProjectionMatrix_RH() -> float4x4 {
        return matrix_perspective_right_hand(fovVertHalf * 2.0, aspectRatio, distanceNear, distanceFar)
    }
}

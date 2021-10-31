//
//  Renderer.swift
//  TemplateTest
//
//  Created by Eoin Roe on 27/10/2021.
//

// Our platform independent renderer class

import Metal
import MetalKit
import simd

enum VertexAttribute: Int {
    case position
    case texcoord
}

enum BufferIndex: Int {
    case meshPositions
    case meshGenerics
    case uniforms
}

enum TextureIndex: Int {
    case color
}

struct Uniforms {
    var projectionMatrix: float4x4
    var modelViewMatrix: float4x4
}

// The 256 byte aligned size of our uniform structure
let alignedUniformsSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100

let maxBuffersInFlight = 3

enum RendererError: Error {
    case badVertexDescriptor
}

class Renderer: NSObject, MTKViewDelegate {

    public let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var dynamicUniformBuffer: MTLBuffer
    var pipelineState: MTLRenderPipelineState
    var depthState: MTLDepthStencilState
    var colorMap: MTLTexture

    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)

    var uniformBufferOffset = 0

    var uniformBufferIndex = 0

    var uniforms: UnsafeMutablePointer<Uniforms>

    var projectionMatrix: matrix_float4x4 = matrix_float4x4()

    var rotation: Float = 0

    var mesh: MTKMesh
    
    var camera = Camera()
    var cameraDistanceFromCenter = SIMD3<Float>(0.0, 0.0, -8.0)
    
    enum CoordinateSystem {
        case leftHanded
        case rightHanded
    }
    
    var coordinateSystem = CoordinateSystem.leftHanded

    init?(metalKitView: MTKView) {
        self.device = metalKitView.device!
        self.commandQueue = self.device.makeCommandQueue()!

        let uniformBufferSize = alignedUniformsSize * maxBuffersInFlight

        self.dynamicUniformBuffer = self.device.makeBuffer(length:uniformBufferSize,
                                                           options:[MTLResourceOptions.storageModeShared])!

        self.dynamicUniformBuffer.label = "UniformBuffer"

        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents()).bindMemory(to:Uniforms.self, capacity:1)

        metalKitView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
        metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        metalKitView.sampleCount = 1

        let mtlVertexDescriptor = Renderer.buildMetalVertexDescriptor()

        do {
            pipelineState = try Renderer.buildRenderPipelineWithDevice(device: device,
                                                                       metalKitView: metalKitView,
                                                                       mtlVertexDescriptor: mtlVertexDescriptor)
        } catch {
            print("Unable to compile render pipeline state.  Error info: \(error)")
            return nil
        }

        let depthStateDescriptor = MTLDepthStencilDescriptor()
        depthStateDescriptor.depthCompareFunction = MTLCompareFunction.less
        depthStateDescriptor.isDepthWriteEnabled = true
        self.depthState = device.makeDepthStencilState(descriptor:depthStateDescriptor)!

        do {
            mesh = try Renderer.buildMesh(device: device, mtlVertexDescriptor: mtlVertexDescriptor)
        } catch {
            print("Unable to build MetalKit Mesh. Error info: \(error)")
            return nil
        }

        do {
            colorMap = try Renderer.loadTexture(device: device, textureName: "ColorMap")
        } catch {
            print("Unable to load texture. Error info: \(error)")
            return nil
        }

        super.init()

    }

    class func buildMetalVertexDescriptor() -> MTLVertexDescriptor {
        // Create a Metal vertex descriptor specifying how vertices will by laid out for input into our render
        //   pipeline and how we'll layout our Model IO vertices

        let mtlVertexDescriptor = MTLVertexDescriptor()

        mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].format = MTLVertexFormat.float3
        mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].offset = 0
        mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].bufferIndex = BufferIndex.meshPositions.rawValue

        mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].format = MTLVertexFormat.float2
        mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].offset = 0
        mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].bufferIndex = BufferIndex.meshGenerics.rawValue

        mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stride = 12
        mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stepRate = 1
        mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stepFunction = MTLVertexStepFunction.perVertex

        mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stride = 8
        mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stepRate = 1
        mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stepFunction = MTLVertexStepFunction.perVertex

        return mtlVertexDescriptor
    }

    class func buildRenderPipelineWithDevice(device: MTLDevice,
                                             metalKitView: MTKView,
                                             mtlVertexDescriptor: MTLVertexDescriptor) throws -> MTLRenderPipelineState {
        /// Build a render state pipeline object

        let library = device.makeDefaultLibrary()

        let vertexFunction = library?.makeFunction(name: "vertexShader")
        let fragmentFunction = library?.makeFunction(name: "fragmentShader")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "RenderPipeline"
        pipelineDescriptor.sampleCount = metalKitView.sampleCount
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = mtlVertexDescriptor

        pipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = metalKitView.depthStencilPixelFormat

        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }

    class func buildMesh(device: MTLDevice,
                         mtlVertexDescriptor: MTLVertexDescriptor) throws -> MTKMesh {
        /// Create and condition mesh data to feed into a pipeline using the given vertex descriptor

        let metalAllocator = MTKMeshBufferAllocator(device: device)

        /*
        
        var mdlMesh = MDLMesh.newBox(withDimensions: SIMD3<Float>(4, 4, 4),
                                      segments: SIMD3<UInt32>(2, 2, 2),
                                      geometryType: MDLGeometryType.triangles,
                                      inwardNormals:false,
                                      allocator: metalAllocator)
         
         */
        
        let mdlMesh = MDLMesh.newPlane(withDimensions: vector_float2(repeating: 5.0),
                                       segments: vector_uint2(repeating: 20),
                                       geometryType: .points,
                                       allocator: metalAllocator)

        let mdlVertexDescriptor = MTKModelIOVertexDescriptorFromMetal(mtlVertexDescriptor)

        guard let attributes = mdlVertexDescriptor.attributes as? [MDLVertexAttribute] else {
            throw RendererError.badVertexDescriptor
        }
        attributes[VertexAttribute.position.rawValue].name = MDLVertexAttributePosition
        attributes[VertexAttribute.texcoord.rawValue].name = MDLVertexAttributeTextureCoordinate

        mdlMesh.vertexDescriptor = mdlVertexDescriptor

        return try MTKMesh(mesh:mdlMesh, device:device)
    }

    class func loadTexture(device: MTLDevice,
                           textureName: String) throws -> MTLTexture {
        /// Load texture data with optimal parameters for sampling

        let textureLoader = MTKTextureLoader(device: device)

        let textureLoaderOptions = [
            MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            MTKTextureLoader.Option.textureStorageMode: NSNumber(value: MTLStorageMode.`private`.rawValue)
        ]

        return try textureLoader.newTexture(name: textureName,
                                            scaleFactor: 1.0,
                                            bundle: nil,
                                            options: textureLoaderOptions)

    }

    private func updateDynamicBufferState() {
        /// Update the state of our uniform buffers before rendering

        uniformBufferIndex = (uniformBufferIndex + 1) % maxBuffersInFlight

        uniformBufferOffset = alignedUniformsSize * uniformBufferIndex

        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents() + uniformBufferOffset).bindMemory(to:Uniforms.self, capacity:1)
    }

    private func rotateCamera() -> () {
        /// Update any game state before rendering
        uniforms[0].projectionMatrix = projectionMatrix

        let rotationAxis = SIMD3<Float>(1, 1, 0)
        
        let sceneCenter = SIMD3<Float>(repeating: 0.0)
        camera.target   = sceneCenter

        let rotationMatrix = matrix3x3_rotation (camera.rotation,  rotationAxis);
        camera.rotation += 0.01

        camera.position = sceneCenter
        camera.position += matrix_multiply (rotationMatrix, cameraDistanceFromCenter)
        
        let modelMatrix = matrix4x4_identity()
        
        func getViewMatrix() -> float4x4 {
            switch (coordinateSystem) {
            case .leftHanded:
                return camera.getViewMatrix_LH()
            case .rightHanded:
                return camera.getViewMatrix_RH()
            }
        }
        
        uniforms[0].modelViewMatrix = simd_mul(getViewMatrix(), modelMatrix)
    }
    
    /*
    
    private func rotateCamera()  {
        /// Update any game state before rendering
        uniforms[0].projectionMatrix = projectionMatrix

        let rotationAxis = SIMD3<Float>(1, 1, 0)
        
        let sceneCenter = SIMD3<Float>(repeating: 0.0)
        camera.target   = sceneCenter

        let rotationMatrix = matrix3x3_rotation (camera.rotation,  rotationAxis);
        camera.rotation += 0.01

        camera.position = sceneCenter
        camera.position += matrix_multiply (rotationMatrix, cameraDistanceFromCenter)
        
        let modelMatrix = matrix4x4_identity()
        
        var viewMatrix: float4x4 {
            switch (coordinateSystem) {
            case .leftHanded:
                return camera.getViewMatrix_LH()
            case .rightHanded:
                return camera.getViewMatrix_RH()
            }
        }
        
        uniforms[0].modelViewMatrix = simd_mul(viewMatrix, modelMatrix)
    }
     
     */
    
    private func updateGameState() -> () {
        /// Update any game state before rendering

        uniforms[0].projectionMatrix = projectionMatrix

        let rotationAxis = SIMD3<Float>(1, 1, 0)
        let modelMatrix = matrix4x4_rotation(rotation, rotationAxis)
        
        func getViewMatrix() -> float4x4 {
            switch (coordinateSystem) {
            case .leftHanded:
                return camera.getViewMatrix_LH()
            case .rightHanded:
                return camera.getViewMatrix_RH()
            }
        }
        
        uniforms[0].modelViewMatrix = simd_mul(getViewMatrix(), modelMatrix)
        rotation += 0.01
    }

    func draw(in view: MTKView) {
        /// Per frame updates hare

        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
                semaphore.signal()
            }
            
            self.updateDynamicBufferState()
            
            self.updateGameState()
            // self.rotateCamera()
            
            /// Delay getting the currentRenderPassDescriptor until we absolutely need it to avoid
            ///   holding onto the drawable and blocking the display pipeline any longer than necessary
            let renderPassDescriptor = view.currentRenderPassDescriptor
            
            if let renderPassDescriptor = renderPassDescriptor {
                
                /// Final pass rendering code here
                if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                    renderEncoder.label = "Primary Render Encoder"
                    
                    renderEncoder.pushDebugGroup("Draw Box")
                    
                    renderEncoder.setCullMode(.none)
                    renderEncoder.setTriangleFillMode(.lines)
                    
                    /*
                     https://docs.microsoft.com/en-us/previous-versions/windows/desktop/bb324490(v=vs.85)
                     
                     Microsoft Direct3D uses a left-handed coordinate system. If you are porting an application
                     that is based on a right-handed coordinate system, you must make two changes to the data
                     passed to Direct3D.

                     Flip the order of triangle vertices so that the system traverses them clockwise from the
                     front. In other words, if the vertices are v0, v1, v2, pass them to Direct3D as v0, v2, v1.
                     Use the view matrix to scale world space by -1 in the z direction. To do this, flip the sign
                     of the M31, M32, M33, and M34 fields of the Matrix structure that you use for your view matrix.
                     
                     */
                    
                    switch (coordinateSystem) {
                    case .leftHanded:
                        renderEncoder.setFrontFacing(.clockwise)
                    case .rightHanded:
                        renderEncoder.setFrontFacing(.counterClockwise)
                    }
                    
                    renderEncoder.setRenderPipelineState(pipelineState)
                    
                    renderEncoder.setDepthStencilState(depthState)
                    
                    renderEncoder.setVertexBuffer(dynamicUniformBuffer, offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
                    renderEncoder.setFragmentBuffer(dynamicUniformBuffer, offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
                    
                    for (index, element) in mesh.vertexDescriptor.layouts.enumerated() {
                        
                        
                        guard let layout = element as? MDLVertexBufferLayout else {
                            return
                        }
                        
                        if layout.stride != 0 {
                            
                            let buffer = mesh.vertexBuffers[index]
                            renderEncoder.setVertexBuffer(buffer.buffer, offset:buffer.offset, index: index)
                        }
                    }
                    
                    renderEncoder.setFragmentTexture(colorMap, index: TextureIndex.color.rawValue)
                    
                    for submesh in mesh.submeshes {
                        renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                            indexCount: submesh.indexCount,
                                                            indexType: submesh.indexType,
                                                            indexBuffer: submesh.indexBuffer.buffer,
                                                            indexBufferOffset: submesh.indexBuffer.offset)
                        
                    }
                    
                    renderEncoder.popDebugGroup()
                    
                    renderEncoder.endEncoding()
                    
                    if let drawable = view.currentDrawable {
                        commandBuffer.present(drawable)
                    }
                }
            }
            
            commandBuffer.commit()
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here

        let aspect = Float(size.width) / Float(size.height)
        // projectionMatrix = matrix_perspective_right_hand(radians_from_degrees(65), aspect, 0.1, 100.0)
        projectionMatrix = matrix_perspective_left_hand(radians_from_degrees(65), aspect, 0.1, 100.0)
    }
}

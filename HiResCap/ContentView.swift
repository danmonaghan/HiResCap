//
//  ContentView.swift
//  HiResCap
//
//  Created by dan monaghan on 24/04/2025.
//

import SwiftUI
import RealityKit
import ARKit
import Combine

struct ContentView: View {
    @StateObject var captureModel = FrameCaptureModel(arView: nil)

    var body: some View {
        ZStack {
            ARViewContainer(captureModel: captureModel)
                .edgesIgnoringSafeArea(.all)

            FrameCaptureOverlayView(captureModel: captureModel)
                .frame(width: 160, height: 120)
                .cornerRadius(8)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding([.top, .trailing], 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            DepthCaptureView(model: captureModel)
                .frame(width: 160, height: 120)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            
            VStack {
                Spacer()
                Button("Capture Hi-Res Frame") {
                    captureModel.getHiresFrame()
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(10)
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    let captureModel: FrameCaptureModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.frameSemantics = .sceneDepth
        config.environmentTexturing = .automatic

        if let bestFormat = ARWorldTrackingConfiguration.supportedVideoFormats.first(where: {
            $0.imageResolution == CGSize(width: 3840, height: 2160)
        }) {
            config.videoFormat = bestFormat
        }

        arView.session.run(config)

        // Simple scene
        let box = MeshResource.generateBox(size: 0.1)
        let material = SimpleMaterial(color: .gray, roughness: 0.15, isMetallic: true)
        let modelEntity = ModelEntity(mesh: box, materials: [material])
        modelEntity.position = [0, 0.05, 0]
        let anchor = AnchorEntity(plane: .horizontal, minimumBounds: [0.2, 0.2])
        anchor.addChild(modelEntity)
        arView.scene.addAnchor(anchor)

        // Set the arView on the shared model
        captureModel.arView = arView

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

extension Notification.Name {
    static let captureFrame = Notification.Name("captureFrame")
}

class FrameCaptureModel: ObservableObject {
    @Published var capturedImage: UIImage?
    @Published var capturedDepth: UIImage?
    @Published var resolutionText: String = ""
    
    private var rotationAngle: Double {
            guard let ori = arView?
                    .window?
                    .windowScene?
                    .interfaceOrientation
            else { return 0 }
            switch ori {
            case .landscapeLeft:       return 180
            case .portrait:            return  90
            case .portraitUpsideDown:  return -90
            default:                   return   0
            }
        }
    
    weak var arView: ARView?
    
    init(arView: ARView?) {
        self.arView = arView
    }
    
    public func getHiresFrame(isJpegQuality: Bool = true) {
            arView?.session.captureHighResolutionFrame { [weak self] (frame, error) in
                guard let self = self, let frame = frame else { return }

                // 1) color image
                let colorBuffer = frame.capturedImage
                let ciColor   = CIImage(cvPixelBuffer: colorBuffer)
                let context   = CIContext()
                guard let cgColor = context.createCGImage(ciColor, from: ciColor.extent) else { return }
                let uiColor = UIImage(cgImage: cgColor)

                // 2) depth image
                guard let liveFrame = self.arView?.session.currentFrame,
                      let depthData = liveFrame.sceneDepth else { return }
                let depthBuffer = depthData.depthMap
                let ciDepth = CIImage(cvPixelBuffer: depthData.depthMap)
                guard let cgDepth = context.createCGImage(ciDepth, from: ciDepth.extent) else { return }
                let uiDepthUnrotated = UIImage(cgImage: cgDepth)
                let uiDepth = uiDepthUnrotated.rotated(by: CGFloat(self.rotationAngle))
                
                DispatchQueue.main.async {
                    self.capturedImage = uiColor
                    self.capturedDepth = uiDepth
                    self.resolutionText = "\(cgColor.width) × \(cgColor.height)"
                }
            }
        }
}

struct FrameCaptureView: View {
    @StateObject var captureModel: FrameCaptureModel

    var body: some View {
        VStack {
            if let image = captureModel.capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 300, maxHeight: 300)
                    .border(Color.gray)

                Text(captureModel.resolutionText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            } else {
                Text("No frame captured yet.")
                    .foregroundColor(.gray)
            }

            Button("Capture High-Res Frame") {
                captureModel.getHiresFrame()
            }
            .padding(.top, 10)
        }
        .padding()
    }
}

struct DepthCaptureView: View {
    @ObservedObject var model: FrameCaptureModel

    var body: some View {
        Group {
            if let depth = model.capturedDepth {
                Image(uiImage: depth)
                    .resizable()
                    .scaledToFit()
                    .border(Color.white, width: 1)
            } else {
                Text("No depth yet")
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 180, height: 180)
        .background(Color.black.opacity(0.2))
        .cornerRadius(8)
    }
}

struct FrameCaptureOverlayView: View {
    @ObservedObject var captureModel: FrameCaptureModel

    var body: some View {
        if let image = captureModel.capturedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
        } else {
            Color.clear
        }
    }
}

extension UIImage {
    func rotated(by degrees: CGFloat) -> UIImage {
        let radians = degrees * .pi/180
        // figure out the size of the rotated view’s containing box
        var newSize = CGRect(origin: .zero, size: size)
            .applying(CGAffineTransform(rotationAngle: radians))
            .integral.size

        UIGraphicsBeginImageContextWithOptions(newSize, false, scale)
        guard let ctx = UIGraphicsGetCurrentContext() else { return self }

        // move origin to middle so we rotate around the center
        ctx.translateBy(x: newSize.width/2, y: newSize.height/2)
        ctx.rotate(by: radians)

        // draw the image into the context
        draw(in: CGRect(x: -size.width/2,
                        y: -size.height/2,
                        width: size.width,
                        height: size.height))

        let rotated = UIGraphicsGetImageFromCurrentImageContext() ?? self
        UIGraphicsEndImageContext()
        return rotated
    }
}

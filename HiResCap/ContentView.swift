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
                .frame(width: 160, height: 90)
                .cornerRadius(8)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding([.top, .trailing], 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

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
    @Published var resolutionText: String = ""
    
    weak var arView: ARView?
    
    init(arView: ARView?) {
        self.arView = arView
    }
    
    public func getHiresFrame(isJpegQuality: Bool = true) {
        arView?.session.captureHighResolutionFrame { [weak self] (frame, error) in
            guard let self = self, let frame = frame else { return }
            
            let pixelBuffer = frame.capturedImage
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
            let uiImage = UIImage(cgImage: cgImage)
            
            print("Captured resolution: \(cgImage.width) × \(cgImage.height)")
            
            DispatchQueue.main.async {
                self.capturedImage = uiImage
                self.resolutionText = "\(cgImage.width) × \(cgImage.height)"
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

#Preview {
    ContentView()
}

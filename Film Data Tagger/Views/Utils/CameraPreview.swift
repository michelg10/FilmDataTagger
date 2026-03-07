//
//  CameraPreview.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/19/26.
//

import SwiftUI
import AVFoundation

/// UIView backed by an AVCaptureVideoPreviewLayer.
/// Created once on CameraManager and reused across navigation to avoid
/// the ~150ms cost of reconnecting the layer to the capture session.
class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

/// Hosts CameraManager's cached preview view via reparenting.
/// Creating this SwiftUI view is cheap — it just moves the existing UIView
/// into a new container rather than creating a new AVCaptureVideoPreviewLayer.
struct CameraPreview: UIViewRepresentable {
    let previewView: CameraPreviewUIView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.clipsToBounds = true
        reparent(into: container)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        if previewView.superview != container {
            reparent(into: container)
        }
    }

    private func reparent(into container: UIView) {
        previewView.removeFromSuperview()
        previewView.frame = container.bounds
        previewView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(previewView)
    }
}

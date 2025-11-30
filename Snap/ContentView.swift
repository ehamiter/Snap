//
//  ContentView.swift
//  Snap
//
//  Created by Eric on 6/23/25.
//

import SwiftUI
import UniformTypeIdentifiers

enum ProcessingMode: String, CaseIterable {
    case resizeAppStore = "Resize image to App Store specs"
    case generateMockup = "Generate iPhone 15 Pro mockup"
}

struct ContentView: View {
    @State private var isProcessing = false
    @State private var statusMessage = "Drop an image to process"
    @State private var isDragOver = false
    @State private var selectedMode: ProcessingMode = .resizeAppStore
    
    var body: some View {
        VStack(spacing: 20) {
            // Drop Zone
            RoundedRectangle(cornerRadius: 12)
                .fill(isDragOver ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isDragOver ? Color.accentColor : Color.gray, lineWidth: 2)
                        .opacity(isDragOver ? 1.0 : 0.5)
                )
                .overlay(
                    VStack(spacing: 16) {
                        Text("📱")
                            .font(.system(size: 48))
                        
                        Text(isDragOver ? "Drop iPhone screenshot here" : "Drag iPhone screenshot here")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(isDragOver ? .accentColor : .secondary)
                    }
                )
                .frame(minWidth: 400, minHeight: 200)
                .onDrop(of: [.image], isTargeted: $isDragOver) { providers in
                    handleDrop(providers: providers)
                }
            
            // Mode Selection
            HStack(spacing: 24) {
                ForEach(ProcessingMode.allCases, id: \.self) { mode in
                    HStack(spacing: 6) {
                        Image(systemName: selectedMode == mode ? "checkmark.square.fill" : "square")
                            .foregroundColor(selectedMode == mode ? .accentColor : .secondary)
                        Text(mode.rawValue)
                            .font(.subheadline)
                    }
                    .onTapGesture {
                        selectedMode = mode
                    }
                }
            }
            
            // Status and Progress
            VStack(spacing: 12) {
                Text(statusMessage)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .frame(height: 60)
        }
        .padding(40)
        .frame(width: 500, height: 400)
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, error in
                DispatchQueue.main.async {
                    if let url = item as? URL {
                        processImage(url: url)
                    } else if let data = item as? Data {
                        // Handle data if URL is not available
                        processImageData(data: data)
                    }
                }
            }
            return true
        }
        return false
    }
    
    private func processImage(url: URL) {
        let mode = selectedMode
        let processingMessage = mode == .resizeAppStore ? "Resizing image..." : "Processing screenshot..."
        updateStatus(processingMessage, isProcessing: true)
        let startedAccessing = url.startAccessingSecurityScopedResource()
        print("Processing image at \(url.path), mode=\(mode.rawValue), startAccessing=\(startedAccessing)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            let success: Bool
            let successMessage: String
            let failureMessage: String
            
            switch mode {
            case .resizeAppStore:
                let resizer = AppStoreImageResizer()
                success = resizer.resizeImage(imageURL: url)
                successMessage = "✅ Image resized for App Store!"
                failureMessage = "❌ Failed to resize image. Please try again."
            case .generateMockup:
                let mockupGenerator = iPhoneMockupGenerator()
                success = mockupGenerator.generateMockup(screenshotURL: url)
                successMessage = "✅ iPhone mockup generated successfully!"
                failureMessage = "❌ Failed to generate mockup. Please try again."
            }
            
            if startedAccessing {
                url.stopAccessingSecurityScopedResource()
            }
            
            DispatchQueue.main.async {
                if success {
                    updateStatus(successMessage)
                } else {
                    updateStatus(failureMessage)
                }
            }
        }
    }
    
    private func processImageData(data: Data) {
        // Save data to temporary file and process
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_screenshot.png")
        
        do {
            try data.write(to: tempURL)
            processImage(url: tempURL)
        } catch {
            updateStatus("❌ Failed to process image data.")
        }
    }
    
    private func updateStatus(_ message: String, isProcessing: Bool = false) {
        statusMessage = message
        self.isProcessing = isProcessing
        
        if !isProcessing && (message.contains("✅") || message.contains("❌")) {
            // Reset message after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if !self.isProcessing {
                    statusMessage = "Drop an image to process"
                }
            }
        }
    }
}

// MARK: - App Store Image Resizer
class AppStoreImageResizer {
    
    private let targetWidth = 1260
    private let targetHeight = 2736
    
    func resizeImage(imageURL: URL) -> Bool {
        guard let sourceImage = NSImage(contentsOf: imageURL),
              let sourceCGImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("Error: Could not load image at \(imageURL.path)")
            return false
        }
        
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("Error: Could not create graphics context")
            return false
        }
        
        context.interpolationQuality = .high
        context.draw(sourceCGImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        
        guard let resizedCGImage = context.makeImage() else {
            print("Error: Could not create resized image")
            return false
        }
        
        return saveImage(resizedCGImage, originalURL: imageURL)
    }
    
    private func saveImage(_ cgImage: CGImage, originalURL: URL) -> Bool {
        let originalName = originalURL.deletingPathExtension().lastPathComponent
        let outputName = "\(originalName)_appstore.png"
        let outputDirectory = originalURL.deletingLastPathComponent()
        let outputURL = outputDirectory.appendingPathComponent(outputName)
        let directoryAccess = outputDirectory.startAccessingSecurityScopedResource()
        
        defer {
            if directoryAccess {
                outputDirectory.stopAccessingSecurityScopedResource()
            }
        }
        
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            print("Error: Could not create PNG data")
            return false
        }
        
        do {
            try pngData.write(to: outputURL)
            print("✅ App Store image saved as: \(outputURL.path)")
            
            DispatchQueue.main.async {
                NSWorkspace.shared.selectFile(outputURL.path, inFileViewerRootedAtPath: outputDirectory.path)
            }
            
            return true
        } catch {
            print("Error saving image to \(outputURL.path): \(error)")
            return false
        }
    }
}

// MARK: - iPhone Mockup Generator
class iPhoneMockupGenerator {
    
    func generateMockup(screenshotURL: URL) -> Bool {
        guard let screenshotImage = NSImage(contentsOf: screenshotURL) else {
            print("Error: Could not load screenshot at \(screenshotURL.path)")
            return false
        }
        
        // Try to find frame image in app bundle first
        var frameImage: NSImage?
        
        if let framePath = Bundle.main.path(forResource: "iphone15pro_frame", ofType: "png") {
            frameImage = NSImage(contentsOfFile: framePath)
        } else {
            print("Error: Could not find iphone15pro_frame.png in bundle")
        }

        guard let frame = frameImage else {
            print("Error: Could not load iPhone frame image")
            return false
        }
        
        return processImages(screenshot: screenshotImage, frame: frame, originalURL: screenshotURL)
    }
    
    private func processImages(screenshot: NSImage, frame: NSImage, originalURL: URL) -> Bool {
        let frameSize = frame.size
        let screenshotSize = screenshot.size
        
        // Calculate scaling and positioning - fine-tuned for iPhone 15 Pro frame
        let targetHeight = frameSize.height
        let scale = (targetHeight / screenshotSize.height) * 0.84
        let newWidth = screenshotSize.width * scale
        let newHeight = screenshotSize.height * scale
        
        let xOffset = (frameSize.width - newWidth) / 2
        let yOffset = (frameSize.height - newHeight) / 2 + 12
        
        // Create composite image
        let compositeSize = NSSize(width: frameSize.width, height: frameSize.height)
        let compositeImage = NSImage(size: compositeSize)
        
        compositeImage.lockFocus()
        
        // Save graphics state
        NSGraphicsContext.current?.saveGraphicsState()
        
        // Draw scaled screenshot with rounded corners
        let screenshotRect = NSRect(x: xOffset, y: yOffset, width: newWidth, height: newHeight)
        let cornerRadius: CGFloat = 85 * scale
        
        // Create rounded rectangle path
        let path = NSBezierPath(roundedRect: screenshotRect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.addClip()
        
        // Draw the screenshot
        screenshot.draw(in: screenshotRect)
        
        // Restore graphics state and draw frame on top
        NSGraphicsContext.current?.restoreGraphicsState()
        frame.draw(in: NSRect(origin: .zero, size: frameSize))
        
        compositeImage.unlockFocus()
        
        // Crop the final image (matching Python crop box)
        let cropRect = NSRect(x: 150, y: 0, width: 800, height: 1500)
        let croppedImage = cropImage(compositeImage, to: cropRect)
        
        // Save the result
        return saveImage(croppedImage, originalURL: originalURL)
    }
    
    private func cropImage(_ image: NSImage, to rect: NSRect) -> NSImage {
        let croppedImage = NSImage(size: rect.size)
        croppedImage.lockFocus()
        
        _ = NSRect(origin: .zero, size: image.size)
        let destRect = NSRect(origin: .zero, size: rect.size)
        
        // Calculate the source rectangle based on the crop rectangle
        let sourceX = rect.origin.x
        let sourceY = rect.origin.y
        let sourceWidth = rect.size.width
        let sourceHeight = rect.size.height
        
        let cropSourceRect = NSRect(x: sourceX, y: sourceY, width: sourceWidth, height: sourceHeight)
        
        image.draw(in: destRect, from: cropSourceRect, operation: .copy, fraction: 1.0)
        croppedImage.unlockFocus()
        
        return croppedImage
    }
    
    private func saveImage(_ image: NSImage, originalURL: URL) -> Bool {
        // Generate output filename
        let originalName = originalURL.deletingPathExtension().lastPathComponent
        let outputName = "\(originalName)_iphone_mockup.png"
        let outputDirectory = originalURL.deletingLastPathComponent()
        let outputURL = outputDirectory.appendingPathComponent(outputName)
        let directoryAccess = outputDirectory.startAccessingSecurityScopedResource()
        print("Saving mockup to \(outputURL.path)")
        print("Directory access started: \(directoryAccess)")
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: outputDirectory.path, isDirectory: &isDir)
        print("Output directory exists=\(exists), isDir=\(isDir.boolValue), writable=\(fm.isWritableFile(atPath: outputDirectory.path))")
        defer {
            if directoryAccess {
                outputDirectory.stopAccessingSecurityScopedResource()
            }
        }
        
        // Convert NSImage to PNG data
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("Error: Could not get CGImage for saving")
            return false
        }
        
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            print("Error: Could not create PNG data")
            return false
        }
        
        do {
            try pngData.write(to: outputURL)
            print("✅ iPhone mockup saved as: \(outputURL.path)")
            
            // Reveal in Finder on the main thread
            DispatchQueue.main.async {
                NSWorkspace.shared.selectFile(outputURL.path, inFileViewerRootedAtPath: outputDirectory.path)
            }
            
            return true
        } catch {
            print("Error saving image to \(outputURL.path): \(error)")
            return false
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}

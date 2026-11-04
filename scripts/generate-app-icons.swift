#!/usr/bin/env swift
// Run from the repository root: swift scripts/generate-app-icons.swift
// Icon Composer owns the native mask; legacy PNGs need their own mask and safe area.
import AppKit

let source = URL(fileURLWithPath: "ManaBar/AppIcon.icon/Assets/Artwork.png")
let image = NSImage(contentsOf: source)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let directory = URL(fileURLWithPath: "ManaBar/Assets.xcassets/AppIcon.appiconset")
let contents = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("Contents.json"))) as! [String: Any]
for item in contents["images"] as! [[String: String]] {
    let points = Int(item["size"]!.split(separator: "x")[0])!
    let scale = Int(item["scale"]!.dropLast())!
    let size = points * scale
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    context.addPath(CGPath(roundedRect: body, cornerWidth: 206, cornerHeight: 206, transform: nil))
    context.clip()
    context.interpolationQuality = .high
    context.draw(image, in: body)
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: directory.appendingPathComponent(item["filename"]!))
    print("\(item["filename"]!): \(size)×\(size)")
}

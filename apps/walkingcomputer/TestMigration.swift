#!/usr/bin/env swift

import Foundation

print("Testing migration from legacy artifacts to spec.md")
print("Current artifacts:")
let files = try! FileManager.default.contentsOfDirectory(atPath: "/Users/fresh/Documents/codewalk/apps/walkingcomputer/artifacts")
    .filter { $0.hasSuffix(".md") || $0.hasSuffix(".legacy") }
    .sorted()
for file in files {
    print("  - \(file)")
}

print("\nTo complete the test:")
print("1. Build and run the app: xcodebuild build -scheme WalkingComputer")
print("2. The app will automatically migrate on first read/write")
print("3. Check artifacts/ directory again to see spec.md and .legacy files")
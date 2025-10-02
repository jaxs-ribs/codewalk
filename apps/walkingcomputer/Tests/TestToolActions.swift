#!/usr/bin/env swift

import Foundation

@discardableResult
func write(_ s: String) -> Int { fputs(s + "\n", stdout); return 0 }

struct Assert {
    static func eq(_ a: String, _ b: String, _ msg: String) {
        if a == b { write("✅ \(msg)") } else { write("❌ \(msg): \(a) != \(b)") }
    }
    static func ok(_ cond: Bool, _ msg: String) {
        if cond { write("✅ \(msg)") } else { write("❌ \(msg)") }
    }
}

// Simple runner
func run() {
    write("=== ToolAction Minimal Tests ===\n")

    let am = ArtifactManager()

    // Prepare sample content
    let desc = "# Project Description\n\nHello world description"
    let phase = "# Project Phasing\n\n## Phase 1: Init\nDo it.\n\n**Definition of Done:** See log"
    let fullSpec = desc + "\n\n" + phase

    // 1) Overwrite description
    let okDesc = am.overwrite(artifact: "description", content: desc)
    Assert.ok(okDesc, "overwrite(description) returns true")
    let (rd1, rp1) = am.readSpec()
    Assert.ok((rd1 ?? "").contains("Hello world description"), "readSpec() contains description")

    // 2) Overwrite phasing
    let okPh = am.overwrite(artifact: "phasing", content: phase)
    Assert.ok(okPh, "overwrite(phasing) returns true")
    let (rd2, rp2) = am.readSpec()
    Assert.ok((rp2 ?? "").contains("Phase 1"), "readSpec() contains phasing")

    // 3) Overwrite full spec
    let okSpec = am.overwrite(artifact: "spec", content: fullSpec)
    Assert.ok(okSpec, "overwrite(spec) returns true")
    if let raw = am.safeRead(filename: "spec.md") {
        Assert.ok(raw.contains("Project Description") && raw.contains("Project Phasing"), "spec.md has both sections")
    }

    // 4) write_diff fallback via content
    let okDiffFallback = am.applyUnifiedDiff(artifact: "spec", diff: "", fallbackContent: fullSpec + "\n\n<!-- updated -->")
    Assert.ok(okDiffFallback, "write_diff with fallback content succeeds")
    if let raw2 = am.safeRead(filename: "spec.md") {
        Assert.ok(raw2.contains("updated"), "fallback content applied")
    }

    // 5) write_diff naive overwrite when diff looks like full content
    let okDiffAsContent = am.applyUnifiedDiff(artifact: "description", diff: desc + "\n\n(edited)", fallbackContent: nil)
    Assert.ok(okDiffAsContent, "write_diff with content-like diff succeeds as overwrite")
    let (rd3, _) = am.readSpec()
    Assert.ok((rd3 ?? "").contains("edited"), "description updated from diff content-like payload")

    write("\n=== Done ===")
}

run()


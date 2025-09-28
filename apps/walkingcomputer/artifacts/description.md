# Project Description

We're building a zero knowledge virtual machine from scratch in Rust. The goal is a high performance zkVM that can prove general purpose computations without revealing the data. We're taking a test driven approach where every phase has comprehensive tests so we can always fall back on them for safety.

The core idea is simple. We'll design a minimal 32 bit RISC instruction set architecture with as few opcodes as possible. This keeps the trace width small which directly translates to smaller proofs and faster proving times. Each instruction will be carefully benchmarked using Criterion dot rs to catch any performance regressions immediately in our CI pipeline.

For the cryptographic backend we're going with either Halo 2 or Plonky 3. Both give us modern proof systems with excellent performance characteristics. We'll implement GPU kernels for the heavy finite field operations and write hand tuned assembly for the most critical paths. The finite field arithmetic is where most zkVMs lose time so we're going to optimize the hell out of that.

The VM itself will be memory safe thanks to Rust's ownership system. No garbage collection means predictable performance which is crucial for proving times. We'll expose the VM through a clean Rust API first. Later we can add REST endpoints if we want HTTP access but the core VM is pure Rust.

Testing is fundamental here. Every constraint in our proof system gets unit tests. Every optimization gets benchmark tests against the previous version. We'll know immediately if something breaks because the tests will fail before we even commit. This way we can iterate quickly without fear of breaking existing functionality.

The end result should be a zkVM that can compete with the current leaders like SP1 and RISC Zero in terms of speed while maintaining the flexibility to prove arbitrary computations. We're not targeting any specific use case yet just building a fast general purpose proving engine that we can trust.
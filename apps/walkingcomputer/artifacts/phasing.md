# Project Phasing

## Phase 1: Bytecode Loader & Decoder
Build a loader that can read a simple bytecode file and decode it into Rust data structures. Support basic operations like loading a file at runtime, parsing opcodes into an enum, and storing them in a Vec<u8> with proper error handling for malformed bytecode.  
**Definition of Done:** Run `cargo run examples/fib.zkbc`, see "Bytecode loaded: 42 instructions" printed in console with no panics.

## Phase 2: Basic Register VM Core
Create a minimal register-based VM that can execute simple arithmetic with 16 general-purpose registers and a program counter. Implement ADD, SUB, MUL, and MOV instructions with immediate values. The VM runs in a loop fetching and executing until it hits a HALT.  
**Definition of Done:** Execute a bytecode with "ADD r1, r2, r3; HALT", see registers update correctly and "VM halted after 2 cycles" printed.

## Phase 3: Memory System & Load/Store
Add a flat memory space with byte addressing and implement LOAD/STORE instructions. Provide 64KB of memory, addressable via registers plus immediate offsets, with proper bounds checking that throws a clean error on invalid access.  
**Definition of Done:** Run bytecode "STORE r1, 0x1000; LOAD r2, 0x1000", see r2 contains same value as r1 and "Memory access at 0x1000" logged.

## Phase 4: Control Flow & Jumps
Add conditional and unconditional jumps. Implement JMP, JEQ, JNE with register comparisons, plus a flags register to track zero and carry bits. This enables building loops and if-statements in bytecode.  
**Definition of Done:** Execute bytecode with "JEQ r1, r2, label" where r1==r2, see program counter jump to label address and "Jump taken to 0x0042" printed.

## Phase 5: System Calls & Host Interface
Add a syscall interface so the guest can request services from the host. Implement a simple ABI with syscall numbers in r0 and arguments in r1-r3, starting with basic I/O like print integer and read clock cycle counter.  
**Definition of Done:** Run bytecode with "MOV r0, 1; MOV r1, 42; SYSCALL", see "Guest output: 42" printed to host console with syscall number logged.

## Phase 6: Execution Trace Recording
Instrument the VM to record every instruction execution in a trace. Each trace entry contains PC, opcode, and register states.  
**Definition of Done:** Run fibonacci bytecode for 10 cycles, see "Trace: 10 entries" printed with each entry showing PC and opcode.

## Phase 7: Memory Merkle Tree
Build a sparse Merkle tree over memory for efficient proofs. Each memory access updates the tree with a Merkle commitment.  
**Definition of Done:** Run bytecode with memory operations, see "Memory root: 0xabc123..." printed and consistent across runs.

## Phase 8: Cryptographic Proof Generation & Verification
Generate a STARK proof that the execution trace is valid. Implement a simple AIR with constraints for register consistency and memory Merkle paths, then generate a proof that can be verified in constant time without re-executing the entire program.  
**Definition of Done:** Generate proof for 10-cycle trace, see "Proof size: 4.2KB" and "Verification: true" when running verifier on proof with same public inputs.
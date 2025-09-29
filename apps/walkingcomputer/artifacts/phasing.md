# Project Phasing

## Phase 1: Core Tensor Ops
So first we'll build a pure-Python tensor class that wraps a simple NumPy array and tracks shape/dtype. Then we'll add basic element-wise ops (add, mul, relu) and their backward stubs so autograd has hooks to grab later. We'll keep every op CPU-only for now so we can test the whole forward-backward cycle without WebGPU complexity. **Definition of Done:** pytest shows `Tensor([[1,2],[3,4]]) + Tensor.ones(2,2)` equals `[[2,3],[4,5]]` and `.backward()` populates `.grad` on leaf tensors.

## Phase 2: WebGPU Kernels
Next we'll write minimal WGSL shaders for the same element-wise ops (add, mul, relu) plus a naïve row-major matmul. We'll create a tiny WebGPU harness in Python that queues these shaders, copies buffers, and returns results as new Tensors, but we'll still fall back to NumPy if WebGPU is unavailable so CI keeps running. **Definition of Done:** `tensor.wgpu_add(other)` produces the same numeric result as the CPU version while `wgpu_matmul(A,B)` passes a 64×64 golden-test within 1e-3 tolerance.

## Phase 3: Autograd Engine
After that we'll wire up a tape-based autograd that records every op (CPU or WebGPU) and automatically chains gradients through arbitrary graphs. We'll register backward kernels for each WGSL shader so GPU tensors propagate grads without ever leaving the GPU, then expose a single `.backward()` call that walks the graph and accumulates grads in-place. **Definition of Done:** a three-layer MLP defined with our ops can converge on a tiny XOR dataset, achieving <0.05 loss after 1k steps using SGD.

## Phase 4: RL Skeleton & CartPole
Then we'll add a slim RL module with policy-gradient loss and a replay buffer, plus our own CartPole env that returns float32 observations and rewards. We'll stitch everything together so the agent samples actions, collects returns, and calls `.backward()` through the GPU path, all without external RL libraries. **Definition of Done:** the agent trains for 500 episodes and keeps the pole upright for 195+ steps on 10 consecutive runs, verified by a seed-controlled eval script.
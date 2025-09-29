# Project Phasing

## Phase 1: Scalar Autograd Core
So first we'll build a single Scalar type that holds f32 value, gradient, and a compute graph node. Then we'll wire in backward passes for add, mul, and pow so gradients flow automatically. After that we'll add shape-aware broadcasting so mismatched dimensions still align during ops.

**Definition of Done:** Two 3×1 and 1×4 tensors multiply to produce 3×4 result with correct gradients on every scalar.

## Phase 2: Tensor & Buffer Ops
Next we'll wrap scalars into contiguous 1-D buffers and add a Tensor struct that owns shape, stride, offset, and the buffer. Then we'll port all scalar ops to work on whole buffers with the same interface, so swapping in WGSL later is painless.

**Definition of Done:** Element-wise add of two 1M-item tensors completes in under 50ms on CPU and produces bitwise-identical gradients to scalar loop.

## Phase 3: Layers & Optimizer
Then we'll stack tensors into MLP layers with ReLU and a tiny SGD optimizer that updates parameters in place. We'll keep layer API minimal: forward(&self, x: &Tensor) -> Tensor and parameters() -> Vec<&mut Tensor>.

**Definition of Done:** A 2-layer net trains on 1k random 10-D points for 10 epochs, loss drops below 0.01, and no parameters become NaN.

## Phase 4: RL & Card Gym
After that we'll clone a minimal 52-card Gym env and implement REINFORCE with baseline. Our agent will be just a small MLP that outputs action logits, and we'll run 10k episodes until it wins >45% of simplified poker hands.

**Definition of Done:** Training script prints "win_rate: 0.46" and completes in <5min on laptop CPU.
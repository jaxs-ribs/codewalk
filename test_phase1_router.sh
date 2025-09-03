#!/bin/bash

# Phase 1 Test: Router 5-way response handling
echo "=== Phase 1 Test: 5-way Router Response Handling ==="
echo

# Colors for output  
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Build the router test binary
echo "Building router test binary..."
cargo test -p router --no-run 2>/dev/null || {
    echo -e "${RED}Failed to build router tests${NC}"
    exit 1
}

echo -e "${GREEN}✓ Router built successfully${NC}"
echo

# Test the confirmation analyzer directly
echo "Testing confirmation response analyzer..."
echo "----------------------------------------"

# Create a simple Rust test program
cat > /tmp/test_router_confirmation.rs << 'EOF'
use router::confirmation::{analyze_confirmation_response, create_confirmation_response};
use router::RouterAction;

fn main() {
    let test_cases = vec![
        // Test continue patterns
        ("yes continue", "ContinuePrevious"),
        ("continue where we left off", "ContinuePrevious"),
        ("resume", "ContinuePrevious"),
        
        // Test new patterns
        ("start new", "StartNew"),
        ("fresh session", "StartNew"),
        ("start over", "StartNew"),
        
        // Test decline patterns
        ("no", "DeclineSession"),
        ("no thanks", "DeclineSession"),
        ("cancel", "DeclineSession"),
        
        // Test ambiguous patterns
        ("yes", "AmbiguousConfirmation"),
        ("okay", "AmbiguousConfirmation"),
        ("sure", "AmbiguousConfirmation"),
        
        // Test unintelligible patterns
        ("purple banana", "UnintelligibleResponse"),
        ("what?", "UnintelligibleResponse"),
        ("hmm", "UnintelligibleResponse"),
    ];
    
    let mut passed = 0;
    let mut failed = 0;
    
    for (input, expected) in test_cases {
        let action = analyze_confirmation_response(input);
        let action_str = format!("{:?}", action);
        
        if action_str.contains(expected) {
            println!("✓ '{}' → {}", input, expected);
            passed += 1;
        } else {
            println!("✗ '{}' → Expected {}, got {:?}", input, expected, action);
            failed += 1;
        }
    }
    
    println!("\nResults: {} passed, {} failed", passed, failed);
    
    if failed > 0 {
        std::process::exit(1);
    }
}
EOF

# Compile and run the test
echo "Running confirmation analyzer tests..."
rustc /tmp/test_router_confirmation.rs -L target/debug/deps --extern router=target/debug/librouter.rlib -o /tmp/test_router 2>/dev/null

if [ -f /tmp/test_router ]; then
    /tmp/test_router
    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}✓ All confirmation tests passed!${NC}"
    else
        echo -e "\n${RED}✗ Some confirmation tests failed${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}Could not run standalone test, falling back to cargo test${NC}"
    cargo test -p router confirmation::tests --quiet
fi

echo
echo "Testing router with confirmation context..."
echo "-------------------------------------------"

# Test that the router properly detects confirmation context
cargo test -p router -- --nocapture confirmation 2>&1 | grep -q "test result: ok"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Router confirmation tests passed${NC}"
else
    echo -e "${RED}✗ Router confirmation tests failed${NC}"
    exit 1
fi

echo
echo "=== Phase 1 Test Summary ==="
echo "----------------------------"
echo -e "${GREEN}✓${NC} Router now supports 5 response types:"
echo "  1. ContinuePrevious - Resume last session"
echo "  2. StartNew - Fresh session"
echo "  3. DeclineSession - Don't start"
echo "  4. AmbiguousConfirmation - Needs clarification (e.g., just 'yes')"
echo "  5. UnintelligibleResponse - Couldn't understand"
echo
echo -e "${GREEN}Phase 1 Complete!${NC}"
echo
echo "Expected behavior when integrated:"
echo "  - 'yes' alone → AmbiguousConfirmation → Re-prompt for clarification"
echo "  - 'yes continue' → ContinuePrevious → Resume with --resume flag"
echo "  - 'start fresh' → StartNew → New session ID"
echo "  - 'no thanks' → DeclineSession → Return to idle"
echo "  - 'purple banana' → UnintelligibleResponse → 'Didn't quite get that'"

# Cleanup
rm -f /tmp/test_router_confirmation.rs /tmp/test_router
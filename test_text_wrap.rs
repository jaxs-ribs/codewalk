// Test text wrapping functionality
use codewalk::utils::TextWrapper;

fn main() {
    println!("Testing text wrapping (max width: 100 chars)\n");
    println!("{}", "=".repeat(100));
    
    // Test 1: Short line
    let short = "This is a short line";
    println!("\nTest 1 - Short line:");
    println!("Input:  {}", short);
    println!("Output:");
    for line in TextWrapper::wrap_line(short) {
        println!("  {}", line);
    }
    
    // Test 2: Long line without prefix
    let long = "This is a very long line that definitely exceeds our maximum width limit of 100 characters and needs to be wrapped into multiple lines for proper display in the terminal user interface";
    println!("\nTest 2 - Long line:");
    println!("Input:  {}", long);
    println!("Output:");
    for line in TextWrapper::wrap_line(long) {
        println!("  {}", line);
    }
    
    // Test 3: Line with ASR prefix
    let asr_line = "[ASR] This is a very long transcription that goes on and on and on and definitely needs to be wrapped because it's way too long for a single line and would overflow the terminal width if not wrapped properly";
    println!("\nTest 3 - ASR prefix:");
    println!("Input:  {}", asr_line);
    println!("Output:");
    for line in TextWrapper::wrap_line(asr_line) {
        println!("  {}", line);
    }
    
    // Test 4: Line with Claude prefix
    let claude_line = "Claude: Here's a very long response from Claude that includes lots of details about the code implementation and various technical considerations that need to be taken into account when building this feature";
    println!("\nTest 4 - Claude prefix:");
    println!("Input:  {}", claude_line);
    println!("Output:");
    for line in TextWrapper::wrap_line(claude_line) {
        println!("  {}", line);
    }
    
    // Test 5: Line with no good break points
    let no_breaks = "Thisisaverylongwordwithoutanyspacesorbreakpointsthatneedstobeforcefullywrappedatthemaximumwidthlimitbecausetherearenonaturalbreakpoints";
    println!("\nTest 5 - No break points:");
    println!("Input:  {}", no_breaks);
    println!("Output:");
    for line in TextWrapper::wrap_line(no_breaks) {
        println!("  {}", line);
    }
    
    println!("\n{}", "=".repeat(100));
    println!("All tests completed!");
}
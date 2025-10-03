import Foundation

@main
struct SessionTestRunner {
    static func main() async {
        let tests = SessionManagementTests()
        await tests.runAllTests()
    }
}

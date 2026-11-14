import BusLensMacCore
import Darwin
import Foundation

@main
enum BusLensMain {
    static func main() {
        let args = CommandLine.arguments
        if BusCLIRunner.isHeadlessInvocation(arguments: args) {
            let result = MainActor.assumeIsolated {
                BusCLIRunner.execute(arguments: args)
            }
            if !result.stdout.isEmpty {
                FileHandle.standardOutput.write(Data(result.stdout.utf8))
            }
            if !result.stderr.isEmpty {
                FileHandle.standardError.write(Data(result.stderr.utf8))
            }
            fflush(stdout)
            fflush(stderr)
            Darwin.exit(result.exitCode)
        }
        BusLensApp.main()
    }
}

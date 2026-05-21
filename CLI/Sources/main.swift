import Foundation

let exit = CLI.run(argv: Array(CommandLine.arguments.dropFirst()))
Foundation.exit(exit)

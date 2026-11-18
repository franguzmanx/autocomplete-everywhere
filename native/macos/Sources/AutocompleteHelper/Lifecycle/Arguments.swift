import Foundation

enum HelperArguments {
    static func parentPID(from arguments: [String]) -> pid_t? {
        guard
            let flag = arguments.firstIndex(of: "--parent-pid"),
            arguments.indices.contains(flag + 1),
            let value = Int32(arguments[flag + 1]),
            value > 1
        else {
            return nil
        }
        return value
    }
}

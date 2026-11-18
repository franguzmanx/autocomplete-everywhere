import Foundation

struct LineReader {
    func readStandardInput(_ receive: (String) -> Void) {
        while let line = readLine(strippingNewline: true) {
            receive(line)
        }
    }
}

import Foundation
// macOS's own heat level: 0 nominal, 1 fair, 2 serious, 3 critical.
print(ProcessInfo.processInfo.thermalState.rawValue)

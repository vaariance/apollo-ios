import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: Status extensions
extension HTTPURLResponse {
  var isSuccessful: Bool {
    return (200..<300).contains(statusCode)
  }
}

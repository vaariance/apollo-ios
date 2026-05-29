import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An `AsyncSequence` that emits `Data` for each chunk of a network response.
///
/// For a multi-part response, each element emitted by the sequence should be the `Data` for an individual chunked part
/// of the response.
public protocol AsyncChunkSequence: AsyncSequence, Sendable where Element == Data {
  
}

/// An ``AsyncChunkSequence`` implementation that parses the chunks of an HTTP multi-part response from a
/// `URLSession.AsyncBytes` data stream. It uses the multi-part boundary specified by the `HTTPURLResponse` to split
/// the data into chunks as it is received.
public struct AsyncHTTPResponseChunkSequence: AsyncChunkSequence {
  public typealias Element = Data

  private let bytes: AnyAsyncByteSequence
  private let response: HTTPURLResponse?

  /// Designated Initializer
  ///
  /// - Parameters:
  ///   - bytes: The response byte stream to be separated into multi-part chunks.
  ///   - response: The HTTP response whose `Content-Type` header determines the multipart boundary.
  public init<S: AsyncSequence & Sendable>(_ bytes: S, response: HTTPURLResponse?) where S.Element == UInt8 {
    self.bytes = AnyAsyncByteSequence(bytes)
    self.response = response
  }

  public func makeAsyncIterator() -> AsyncIterator {
    return AsyncIterator(bytes.makeAsyncIterator(), boundary: chunkBoundary)
  }

  private var chunkBoundary: String? {
    guard let response else {
      return nil
    }

    return response.multipartHeaderComponents.boundary
  }

  public struct AsyncIterator: AsyncIteratorProtocol {
    public typealias Element = Data

    private var underlyingIterator: AnyAsyncByteSequence.AsyncIterator

    private let boundary: Data?

    private typealias Constants = MultipartResponseParsing

    fileprivate init(
      _ underlyingIterator: AnyAsyncByteSequence.AsyncIterator,
      boundary: String?
    ) {
      self.underlyingIterator = underlyingIterator

      if let boundaryString = boundary?.data(using: .utf8) {
        self.boundary = Constants.Delimiter + boundaryString
      } else {
        self.boundary = nil
      }
    }

    public mutating func next() async throws -> Data? {
      var buffer = Data()

      while let next = try await self.underlyingIterator.next() {
        buffer.append(next)

        if let boundary,
           let boundaryRange = buffer.range(of: boundary, options: [.anchored, .backwards]) {
          buffer.removeSubrange(boundaryRange)

          formatAsChunk(&buffer)

          if !buffer.isEmpty {
            return buffer
          }
        }
      }

      formatAsChunk(&buffer)

      return buffer.isEmpty ? nil : buffer
    }

    private func formatAsChunk(_ buffer: inout Data) {
      if buffer.prefix(Constants.CRLF.count) == Constants.CRLF {
        buffer.removeFirst(Constants.CRLF.count)
      }

      if buffer.starts(with: Constants.CloseDelimiter) {
        buffer.removeAll()
      }
    }
  }
}

// MARK: - Type-erased async byte sequence

private struct AnyAsyncByteSequence: AsyncSequence, Sendable {
  typealias Element = UInt8

  private let makeIteratorClosure: @Sendable () -> AsyncIterator

  init<S: AsyncSequence & Sendable>(_ sequence: S) where S.Element == UInt8 {
    self.makeIteratorClosure = {
      AsyncIterator(sequence.makeAsyncIterator())
    }
  }

  func makeAsyncIterator() -> AsyncIterator {
    makeIteratorClosure()
  }

  struct AsyncIterator: AsyncIteratorProtocol {
    private var box: AnyAsyncByteIteratorBox

    init<I: AsyncIteratorProtocol>(_ iterator: I) where I.Element == UInt8 {
      self.box = ConcreteAsyncByteIteratorBox(iterator)
    }

    mutating func next() async throws -> UInt8? {
      try await box.next()
    }
  }
}

private protocol AnyAsyncByteIteratorBox: Sendable {
  mutating func next() async throws -> UInt8?
}

private struct ConcreteAsyncByteIteratorBox<I: AsyncIteratorProtocol>: AnyAsyncByteIteratorBox, @unchecked Sendable where I.Element == UInt8 {
  private var iterator: I

  init(_ iterator: I) {
    self.iterator = iterator
  }

  mutating func next() async throws -> UInt8? {
    try await iterator.next()
  }
}

// MARK: - Data byte sequence (cross-platform fallback)

public struct AsyncDataByteSequence: AsyncSequence, Sendable {
  public typealias Element = UInt8

  private let data: Data

  public init(_ data: Data) {
    self.data = data
  }

  public func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(data: data)
  }

  public struct AsyncIterator: AsyncIteratorProtocol {
    private let data: Data
    private var index: Data.Index

    fileprivate init(data: Data) {
      self.data = data
      self.index = data.startIndex
    }

    public mutating func next() async throws -> UInt8? {
      guard index < data.endIndex else { return nil }
      defer { index = data.index(after: index) }
      return data[index]
    }
  }
}

// MARK: - Darwin convenience (URLSession.AsyncBytes)
#if canImport(Darwin)
extension URLSession.AsyncBytes {

  var chunks: AsyncHTTPResponseChunkSequence {
    return AsyncHTTPResponseChunkSequence(self, response: task.response as? HTTPURLResponse)
  }

}
#endif

// MARK: - Cross-platform convenience (Data)
extension Data {
  func chunks(response: HTTPURLResponse?) -> AsyncHTTPResponseChunkSequence {
    AsyncHTTPResponseChunkSequence(AsyncDataByteSequence(self), response: response)
  }
}

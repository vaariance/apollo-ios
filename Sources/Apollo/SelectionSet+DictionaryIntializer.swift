import ApolloAPI

public enum RootSelectionSetInitializeError: Error {
  case hasNonHashableValue
}

// AnyHashable lost its unconditional `Sendable` conformance in the Xcode 27 / Swift 6.x toolchain,
// so it can no longer be erased to `JSONValue` (= any Sendable & Hashable), and `Sendable` — a
// marker protocol — cannot appear in a dynamic cast. `Sendable` adds no witness table, so
// `any Hashable` and `JSONValue` share an identical existential layout; reinterpreting between them
// is layout-safe and preserves the underlying value (JSON scalars are genuinely Sendable).
@inline(__always)
func _eraseToJSONValue(_ value: AnyHashable) -> JSONValue {
  unsafeBitCast(value as any Hashable, to: JSONValue.self)
}

extension RootSelectionSet {
  /// Initializes a `SelectionSet` with a raw JSON response object.
  ///
  /// The process of converting a JSON response into `SelectionSetData` is done by using a
  /// `GraphQLExecutor` with a`GraphQLSelectionSetMapper` to parse, validate, and transform
  /// the JSON response data into the format expected by `SelectionSet`.
  ///
  /// - Parameters:
  ///   - data: A dictionary representing a JSON response object for a GraphQL object.
  ///   - variables: [Optional] The operation variables that would be used to obtain
  ///                the given JSON response data.
  @_disfavoredOverload
  public init(
    data: [String: Any],
    variables: GraphQLOperation.Variables? = nil
  ) async throws {
    let jsonObject = try Self.convertToAnyHashableValueDict(dict: data)
    try await self.init(data: jsonObject, variables: variables)
  }
  
  /// Convert dictionary type [String: Any] to [String: AnyHashable]
  /// - Parameter dict: [String: Any] type dictionary
  /// - Returns: converted [String: AnyHashable] type dictionary
  private static func convertToAnyHashableValueDict(dict: [String: Any]) throws -> JSONObject {
    var result = JSONObject()

    for (key, value) in dict {
      if let arrayValue = value as? [Any] {
        result[key] = try convertToAnyHashableArray(array: arrayValue) as JSONValue
      } else  {
        if let dictValue = value as? [String: Any] {
          result[key] = try convertToAnyHashableValueDict(dict: dictValue) as JSONValue
        } else if let hashableValue = value as? AnyHashable {
          result[key] = _eraseToJSONValue(hashableValue)
        } else {
          throw RootSelectionSetInitializeError.hasNonHashableValue
        }
      }
    }
    return result
  }

  /// Convert Any type Array type to AnyHashable type Array
  /// - Parameter array: Any type Array
  /// - Returns: AnyHashable type Array
  private static func convertToAnyHashableArray(array: [Any]) throws -> [JSONValue] {
    var result: [JSONValue] = []
    for value in array {
      if let array = value as? [Any] {
        result.append(try convertToAnyHashableArray(array: array) as JSONValue)
      } else if let dict = value as? [String: Any] {
        result.append(try convertToAnyHashableValueDict(dict: dict) as JSONValue)
      } else if let hashable = value as? AnyHashable {
        result.append(_eraseToJSONValue(hashable))
      } else {
        throw RootSelectionSetInitializeError.hasNonHashableValue
      }
    }
    return result
  }
}

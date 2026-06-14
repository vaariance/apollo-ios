import Foundation
@_spi(Internal) import ApolloAPI

struct BaseResponseExecutionHandler: Sendable {

  let responseBody: JSONObject
  let rootKey: CacheReference
  let variables: GraphQLOperation.Variables?

  init(
    responseBody: JSONObject,
    rootKey: CacheReference,
    variables: GraphQLOperation.Variables?
  ) {
    self.responseBody = responseBody
    self.rootKey = rootKey
    self.variables = variables
  }

  /// Call this function when you want to execute on an entire operation and its response data.
  /// This function should also be called to execute on the partial (initial) response of an
  /// operation with deferred selection sets.
  func execute<
    Accumulator: GraphQLResultAccumulator,
    Data: RootSelectionSet
  >(
    selectionSet: Data.Type,
    with accumulator: Accumulator
  ) async throws -> Accumulator.FinalResult? {
    guard let dataEntry = jsonObject(responseBody["data"]) else {
      return nil
    }

    return try await executor.execute(
      selectionSet: Data.self,
      on: dataEntry,
      withRootCacheReference: rootKey,
      variables: variables,
      accumulator: accumulator
    )
  }

  /// Call this function to execute on a specific selection set and its incremental response data.
  /// This is typically used when executing on deferred selections.
  func execute<
    Accumulator: GraphQLResultAccumulator,
    Operation: GraphQLOperation
  >(
    selectionSet: any Deferrable.Type,
    in operation: Operation.Type,
    with accumulator: Accumulator
  ) async throws -> Accumulator.FinalResult? {
    guard let dataEntry = jsonObject(responseBody["data"]) else {
      return nil
    }

    return try await executor.execute(
      selectionSet: selectionSet,
      in: Operation.self,
      on: dataEntry,
      withRootCacheReference: rootKey,
      variables: variables,
      accumulator: accumulator
    )
  }

  var executor: GraphQLExecutor<NetworkResponseExecutionSource> {
    GraphQLExecutor(executionSource: NetworkResponseExecutionSource())
  }

  func parseErrors() -> [GraphQLError]? {
    guard let errorsEntry = jsonObjects(responseBody["errors"]) else {
      return nil
    }

    return errorsEntry.map {
      GraphQLError($0)
    }
  }

  func parseExtensions() -> JSONObject? {
    return jsonObject(responseBody["extensions"])
  }

  private func jsonObject(_ value: JSONValue?) -> JSONObject? {
    guard let value else { return nil }
    if let object = value as? JSONObject { return object }
    if let object = value as? AnyHashable as? JSONObject { return object }
    guard JSONSerialization.isValidJSONObject(value),
      let data = try? JSONSerialization.data(withJSONObject: value),
      let object = try? JSONSerializationFormat.deserialize(data: data) as JSONObject
    else {
      return nil
    }
    return object
  }

  private func jsonObjects(_ value: JSONValue?) -> [JSONObject]? {
    guard let value else { return nil }
    if let objects = value as? [JSONObject] { return objects }
    if let objects = value as? AnyHashable as? [JSONObject] { return objects }
    if let values = value as? [JSONValue] {
      let objects = values.compactMap(jsonObject)
      return objects.count == values.count ? objects : nil
    }
    guard JSONSerialization.isValidJSONObject(value),
      let data = try? JSONSerialization.data(withJSONObject: value),
      let objects = try? JSONSerializationFormat.deserialize(data: data) as [JSONValue]
    else {
      return nil
    }
    let converted = objects.compactMap(jsonObject)
    return converted.count == objects.count ? converted : nil
  }
}

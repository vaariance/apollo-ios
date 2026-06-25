import Foundation
@_spi(Internal) import ApolloAPI

@_spi(Internal)
public final class JSONSerializationFormat {
  public class func serialize(value: any JSONEncodable) throws -> Data {
    return try JSONSerialization.sortedData(withJSONObject: value._jsonValue)
  }

  public class func serialize(value: JSONObject) throws -> Data {
    return try JSONSerialization.sortedData(withJSONObject: value)
  }

  private class func deserializeJSONValue(data: Data) throws -> JSONValue {
    let rawValue = try JSONSerialization.jsonObject(with: data, options: [])
    return try convertFoundationJSONValue(rawValue)
  }

  private class func convertFoundationJSONValue(_ value: Any) throws -> JSONValue {
    if let arrayValue = value as? [Any] {
      return try convertFoundationJSONArray(arrayValue) as JSONValue
    }

    if let objectValue = value as? [String: Any] {
      return try convertFoundationJSONObject(objectValue) as JSONValue
    }

    // Normalize scalar leaves to the Foundation types Apollo's decoders expect.
    // Apple's `JSONSerialization` yields `NSNumber`/`NSString`/`NSNull`, but
    // swift-foundation (Android/Linux) yields native `Double`/`Int`/`Bool`/`String`,
    // which fail the decoders' `value as? NSNumber` checks. Box numbers/bools as
    // `NSNumber` so both platforms decode identically.
    switch value {
    case is NSNull:
      return NSNull()
    case let number as NSNumber:
      return number
    case let bool as Bool:
      return NSNumber(value: bool)
    case let int as Int:
      return NSNumber(value: int)
    case let double as Double:
      return NSNumber(value: double)
    case let string as String:
      return string
    default:
      break
    }

    if let hashableValue = value as? AnyHashable {
      return _eraseToJSONValue(hashableValue)
    }

    throw JSONDecodingError.couldNotConvert(
      value: String(describing: type(of: value)),
      to: JSONValue.self
    )
  }

  private class func convertFoundationJSONArray(_ array: [Any]) throws -> [JSONValue] {
    try array.map { try convertFoundationJSONValue($0) }
  }

  private class func convertFoundationJSONObject(_ object: [String: Any]) throws -> JSONObject {
    var result = JSONObject()
    for (key, value) in object {
      result[key] = try convertFoundationJSONValue(value)
    }
    return result
  }

  public class func deserialize(data: Data) throws -> [JSONValue] {
    let rawValue = try JSONSerialization.jsonObject(with: data, options: [])
    guard let array = rawValue as? [Any] else {
      throw JSONDecodingError.couldNotConvert(
        value: String(describing: type(of: rawValue)),
        to: [JSONValue].self
      )
    }
    return try convertFoundationJSONArray(array)
  }

  public class func deserialize(data: Data) throws -> JSONObject {
    let rawValue = try JSONSerialization.jsonObject(with: data, options: [])
    guard let object = rawValue as? [String: Any] else {
      throw JSONDecodingError.couldNotConvert(
        value: String(describing: type(of: rawValue)),
        to: JSONObject.self
      )
    }
    return try convertFoundationJSONObject(object)
  }
}

extension JSONSerialization {

  /// Uses `sortedKeys` to create a stable representation of JSON objects.
  ///
  /// - Parameter object: The object to serialize
  /// - Returns: The serialized data
  /// - Throws: Errors related to the serialization of data.
  static func sortedData(withJSONObject object: Any) throws -> Data {
    return try self.data(withJSONObject: object, options: [.sortedKeys])
  }
}

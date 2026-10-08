// Test-only surface for exercising the real store on hosts without Apple SDKs.
// This does not validate Combine observation behavior or Apple SDK compatibility.
public protocol ObservableObject: AnyObject {}

@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}

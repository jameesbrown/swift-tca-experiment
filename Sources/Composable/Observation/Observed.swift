import Observation

@MainActor @dynamicMemberLookup public struct Observed<State> {
  let _observed: _Observed<State>
  init(_ subject: _Observed<State>) { self._observed = subject }
  @inline(__always) public var wrappedValue: State {
    get { _observed.withAccess(\.self) }
    set { _observed.withMutation(of: \.self, { $0 = newValue }) }
  }
  public subscript<Member>(dynamicMember keyPath: KeyPath<State, Member>)
    -> Member
  { _observed.withAccess(keyPath) }
  @inline(__always)
  public subscript<Member>(dynamicMember keyPath: WritableKeyPath<State, Member>)
    -> Member
  {
    get { _observed.withAccess(keyPath) }
    nonmutating set { _observed.withMutation(of: keyPath, { $0 = newValue }) }
  }
  public func withMutation<Member>(
    of keyPath: WritableKeyPath<State, Member>,
    mutation: (inout Member) -> Void
  ) { _observed.withMutation(of: keyPath, { mutation(&$0) }) }
  @inline(__always) func invalidate() { _observed.invalidate() }
}

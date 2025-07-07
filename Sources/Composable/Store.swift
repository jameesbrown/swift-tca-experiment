import CasePaths
import SwiftUI

extension Store {
  public convenience init(
    _ initialValue: consuming State,
    reducer: @escaping Reducer<State, Action>
  ) {
    self.init(
      toState: .init(
        \State.self,
        storage: _Storage(initialValue),
        isInvalidated: { _ in false },
        invalidate: {}
      ),
      rootStore: RootStore(),
      sendToParent: { _ in },
      reducer: reducer
    )
    self.rootStore.addSender(
      id: id,
      send: { [self] sendable in _send(sendable.action.base as! Action) },
      onInvalidation: { [self] in
        for child in self.children.values {
          rootStore.removeSender(id: .init(child))
        }
      }
    )
  }

  public func send(
    _ action: Action,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) {
    self._send(
      action,
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column
    )
  }

  public func scope<ChildState, ChildAction>(
    state: WritableKeyPath<State, ChildState>,
    action: CaseKeyPath<Action, ChildAction>,
    reducer: @escaping Reducer<ChildState, ChildAction>
  ) -> Store<ChildState, ChildAction> {
    self.scope(
      state: self.state._observed.appending(path: state),
      action: action,
      reducer: reducer
    )
  }

  public func scope<ChildState, ChildAction>(
    state: WritableKeyPath<State, ChildState?>,
    action: CaseKeyPath<Action, ChildAction>,
    reducer: @escaping Reducer<ChildState, ChildAction>
  ) -> Store<ChildState, ChildAction>? {
    let toState: _Observed<ChildState> = self.state._observed.appending(
      path: state
    )
    guard !toState.isInvalidated(isObserving: true) else {
      guard
        let child = children.removeValue(forKey: id(toState, action))
          as? Store<ChildState, ChildAction>
      else { return nil }
      rootStore.removeSender(id: child.id)
      return nil
    }
    return self.scope(state: toState, action: action, reducer: reducer)
  }

  public func scope<ElementState, ElementAction>(
    state toElementState: WritableKeyPath<
      State, IdentifiedArrayOf<ElementState>
    >,
    action: CaseKeyPath<
      Action, IdentifiedAction<ElementState.ID, ElementAction>
    >,
    reducer: @escaping Reducer<
      ElementState, IdentifiedAction<ElementState.ID, ElementAction>
    >
  ) -> some RandomAccessCollection<
    Store<ElementState, IdentifiedAction<ElementState.ID, ElementAction>>
  >
  where
    ElementState: Identifiable, ElementAction: Sendable,
    ElementState.ID: Sendable
  {
    self[dynamicMember: toElementState].ids
      .compactMap({
        self.scope(
          state: toElementState.appending(path: \.[id: $0]),
          action: action,
          reducer: reducer
        )
      })
  }

  @inlinable
  public subscript<Value>(dynamicMember keyPath: KeyPath<State, Value>) -> Value
  { self.state[dynamicMember: keyPath] }

  /// Observe a value that is lower down in the heirarchy from a parent feature.
  public func observing<Value>(_ keyPath: KeyPath<State, Value>) -> Observed<
    Value
  > {
    .init(
      self.state._observed.appending(
        path: keyPath as! WritableKeyPath<State, Value>
      )
    )
  }
}

extension Store: Identifiable {
  nonisolated public var id: ObjectIdentifier { .init(self) }
}

extension Store {
  @inlinable public func bind<LocalState>(
    _ toState: WritableKeyPath<State, LocalState>
  ) -> Binding<LocalState> {
    .init(
      get: { self[dynamicMember: toState] },
      set: { newValue in self.state[dynamicMember: toState] = newValue }
    )
  }
  public func send(_ action: Action, animation: Animation) {
    withAnimation(animation) { self.send(action) }
  }
}

extension Bindable {
  @inlinable @MainActor
  public func scope<State, Action, ChildState, ChildAction>(
    state toState: WritableKeyPath<State, ChildState?>,
    action: CaseKeyPath<Action, ChildAction>,
    reducer: @escaping Reducer<ChildState, ChildAction>
  ) -> Binding<Store<ChildState, ChildAction>?>
  where Value == Store<State, Action> {
    let reducer = _HashableReducer(id: id, base: reducer)
    return self[state: toState, action, reducer]
  }
}

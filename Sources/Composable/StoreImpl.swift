import CasePaths
import Observation

@dynamicMemberLookup @MainActor
public class Store<State, Action: Sendable>: Observable {
  var _sendToParent: (Action) -> Void
  let reducer: Reducer<State, Action>
  var children = [AnyHashable: AnyObject]()
  var rootStore: RootStore
  @usableFromInline let state: Observed<State>

  init(
    toState: _Observed<State>,
    rootStore: RootStore,
    sendToParent: @escaping (Action) -> Void,
    reducer: @escaping Reducer<State, Action>
  ) {
    self.state = .init(toState)
    self.rootStore = rootStore
    self.reducer = reducer
    self._sendToParent = sendToParent
  }

  @inline(__always) func withLock(_ operation: @escaping () -> Void) {
    guard !StoreContext._lock else {
      // TODO: I don't think this should happen, would cause weird behaviour.
      assertionFailure()
      StoreContext.bufferedActions.append(operation)
      return
    }
    StoreContext._lock = true
    defer { StoreContext._lock = false }
    operation()
    guard !StoreContext.bufferedActions.isEmpty else { return }
    let buffered = StoreContext.bufferedActions
    StoreContext.bufferedActions.removeAll()
    var iter = buffered.makeIterator()
    while let next = iter.next() { next() }
  }

  @inline(__always) func _send(
    _ action: Action,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) {
    guard !state._observed.isInvalidated() else {
      reportIssue(
        "Sending an action to an invalidated store.",
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
      return
    }
    defer {
      withLock { [unowned self] in
        for effect in StoreContext.effects { rootStore.yield(effect) }
        StoreContext.effects = []
      }
    }
    withLock { [unowned self] in
      // NB: Exclusive access problem.
      var state = state
      let effect = reducer(&state, action).sendAsAnyAction(id)
      _ = consume state
      #if DEBUG
        TestLocals.effectTracker(effect)
      #endif
      StoreContext.effects.append(effect)
    }
    _sendToParent(action)
  }

  @usableFromInline func scope<ChildState, ChildAction>(
    state toState: _Observed<ChildState>,
    action: CaseKeyPath<Action, ChildAction>,
    reducer: @escaping Reducer<ChildState, ChildAction>
  ) -> Store<ChildState, ChildAction> {
    let scopeID = id(toState, action)
    guard let childStore = children[scopeID] as? Store<ChildState, ChildAction>
    else {
      let childStore = Store<ChildState, ChildAction>(
        toState: toState,
        rootStore: self.rootStore,
        sendToParent: { [weak self] childAction in
          self?._send(action(childAction))
        },
        reducer: reducer
      )
      self.rootStore.addSender(
        id: childStore.id,
        send: { [childStore] sendable in
          childStore.send(sendable.action.base as! ChildAction)
        },
        onInvalidation: { [childStore, rootStore] in
          for child in childStore.children.values {
            rootStore.removeSender(id: .init(child))
          }
        }
      )
      self.children[scopeID] = childStore
      childStore.rootStore = rootStore
      return childStore
    }
    return childStore
  }
  @usableFromInline subscript<ChildState, ChildAction>(
    state toState: WritableKeyPath<State, ChildState?>,
    action: CaseKeyPath<Action, ChildAction>,
    reducer: _HashableReducer<ChildState, ChildAction>
  ) -> Store<ChildState, ChildAction>? {
    get {
      StoreContext.$isObserving.withValue(true) {
        self.scope(state: toState, action: action, reducer: reducer.base)
      }
    }
    set {
      let childState: _Observed<ChildState> = self.state._observed.appending(
        path: toState
      )
      if newValue == nil, !childState.isInvalidated() {
        self.invalidate(childState, action)
      }
    }
  }

  func id<ChildState, ChildAction>(
    _ state: _Observed<ChildState>,
    _ action: CaseKeyPath<Action, ChildAction>
  ) -> ScopeID<ChildState, Action> { ScopeID(state: state, action: action) }

  func invalidate<ChildState, ChildAction: Sendable>(
    _ state: _Observed<ChildState>,
    _ action: CaseKeyPath<Action, ChildAction>
  ) {
    guard
      let child = self.children.removeValue(forKey: id(state, action))
        as? Store<ChildState, ChildAction>
    else { return }
    child.state.invalidate()
    rootStore.removeSender(id: child.id)
  }

  deinit {
    #if DEBUG
      Logger.shared.log("\(storeTypeName(of: self)) DEINIT")
    #endif
  }
}

@MainActor @_spi(internals) public enum StoreContext {
  static var effects = [Effect<AnyAction>]()
  static var bufferedActions = [() -> Void]()
  @_spi(internals) public static var _lock = false
  @TaskLocal static var isObserving = false
}

@usableFromInline struct _HashableReducer<State, Action>: Hashable {
  let id: AnyHashable
  let base: Reducer<State, Action>
  @usableFromInline init(
    id: AnyHashable,
    base: @escaping Reducer<State, Action>
  ) {
    self.id = id
    self.base = base
  }
  @usableFromInline func hash(into hasher: inout Hasher) { hasher.combine(id) }
  @usableFromInline static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.id == rhs.id
  }
}

struct ScopeID<State, Action>: Hashable, @unchecked Sendable {
  let state: _Observed<State>
  let action: PartialCaseKeyPath<Action>
}

struct AnyAction: Sendable {
  var sender: ObjectIdentifier
  var action: AnySendable
  struct AnySendable: @unchecked Sendable {
    let base: Any
    init<Base: Sendable>(_ base: Base) { self.base = base }
  }
}

enum TestLocals {
  @TaskLocal static var effectTracker: @Sendable (Effect<AnyAction>) -> Void = {
    _ in
  }
}

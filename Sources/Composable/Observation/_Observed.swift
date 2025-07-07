import Observation

@usableFromInline struct _Observed<State>: Hashable {
  let unwrapped: AnyKeyPath
  private var _isInvalidated: (_ isObserving: Bool) -> Bool
  var invalidate: () -> Void
  let cachedValueStorage: _CachedValueStorage
  // NB: Initialized by `Store.create(_:)`.
  @MainActor let storage: any ObservationStorage
  // TODO: Explain the purpose of this.
  final class _CachedValueStorage { var value: State? }
  @MainActor init<Root>(
    _ unwrapped: WritableKeyPath<Root, State>,
    storage: some ObservationStorage<Root>,
    cachedValueStorage: _CachedValueStorage = .init(),
    isInvalidated: @escaping (_ isObserving: Bool) -> Bool,
    invalidate: @escaping () -> Void
  ) {
    self.unwrapped = unwrapped
    self.storage = storage
    self.cachedValueStorage = cachedValueStorage
    self._isInvalidated = isInvalidated
    self.invalidate = invalidate
  }

  @inline(__always) func isInvalidated(isObserving: Bool = false) -> Bool {
    self._isInvalidated(isObserving)
  }
  @MainActor func withAccess<Value>(_ keyPath: KeyPath<State, Value>) -> Value {
    guard !isInvalidated() else {
      let state = cachedValueStorage.value!
      return state[keyPath: keyPath]
    }
    func open<Root>(_ storage: some ObservationStorage<Root>) -> Value {
      let unwrapped = unsafeDowncast(
        unwrapped,
        to: WritableKeyPath<Root, State>.self
      )
      let fromRootToValue = unwrapped.appending(path: keyPath)
      storage.access(fromRootToValue)
      return storage.address.pointee[keyPath: fromRootToValue]
    }
    return open(storage)
  }

  @MainActor func withMutation<Value>(
    of keyPath: WritableKeyPath<State, Value>,
    _ mutation: (inout Value) -> Void
  ) {
    guard !isInvalidated() else { return }
    @inline(__always) func open<Root>(_ storage: some ObservationStorage<Root>)
    {
      storage.withMutation(
        unsafeDowncast(unwrapped, to: WritableKeyPath<Root, State>.self)
          .appending(path: keyPath),
        mutation: { mutation(&$0) }
      )
    }
    open(storage)
  }

  @MainActor func appending<ChildState>(
    path: WritableKeyPath<State, ChildState>
  ) -> _Observed<ChildState> { _appending(path: path, referencing: storage) }

  @MainActor func appending<ChildState>(
    path: WritableKeyPath<State, ChildState?>
  ) -> _Observed<ChildState> { _appending(path: path, referencing: storage) }

  @inline(__always) @MainActor func _appending<Root, ChildState>(
    path: WritableKeyPath<State, ChildState>,
    referencing storage: some ObservationStorage<Root>
  ) -> _Observed<ChildState> {
    let keyPath = unsafeDowncast(
      unwrapped,
      to: WritableKeyPath<Root, State>.self
    )
    let unwrapped = keyPath.appending(path: path)
    let toChildState = _Observed<ChildState>(
      unwrapped,
      storage: storage,
      isInvalidated: { [_isInvalidated] _ in
        _isInvalidated( /*isObserving:*/false)
      },
      invalidate: {}
    )
    // If we are appending to an invalidated parent, we dont want to try
    // and get an initial value, doing so will cause a crash.
    guard !isInvalidated() else { return toChildState }
    toChildState.cachedValueStorage.value =
      storage.address.pointee[keyPath: unwrapped]
    return toChildState
  }

  @inline(__always) @MainActor func _appending<Root, ChildState>(
    path: WritableKeyPath<State, ChildState?>,
    referencing storage: some ObservationStorage<Root>
  ) -> _Observed<ChildState> {
    let keyPath = unsafeDowncast(
      unwrapped,
      to: WritableKeyPath<Root, State>.self
    )
    let optionalValue = keyPath.appending(path: path)
    let cachedValueStorage = _Observed<ChildState>._CachedValueStorage()
    let toChildState = _Observed<ChildState>(
      keyPath.appending(path: (path.appending(path: \.!))),
      storage: storage,
      cachedValueStorage: cachedValueStorage,
      isInvalidated: { [unowned(unsafe) storage, _isInvalidated] in
        // NB: This avoids uneeded observation.
        guard !_isInvalidated( /*isObserving:*/false) else { return true }
        if $0 { storage.access(optionalValue) }
        return storage.address.pointee[keyPath: optionalValue] == nil
      },
      invalidate: {
        [unowned(unsafe) storage, unowned(unsafe) cachedValueStorage] in
        guard let value = storage.address.pointee[keyPath: optionalValue] else {
          return
        }
        cachedValueStorage.value = value
        // NB: This is necessary for things like dismissing sheets.
        storage.withMutation(optionalValue, mutation: { $0 = nil })
      }
    )
    // If we are appending to an invalidated parent, we dont want to try
    // and get an initial value, doing so will cause a crash.
    guard !isInvalidated() else { return toChildState }
    toChildState.cachedValueStorage.value =
      storage.address.pointee[keyPath: optionalValue]
    return toChildState
  }

  @usableFromInline nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(self.unwrapped)
  }

  @usableFromInline nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.unwrapped == rhs.unwrapped
  }
}

// NB: Using this protocol simplifies the code
// and does not (significantly?) increase the overhead vs unsafeDowncast(_:to:).
protocol ObservationStorage<Root>: AnyObject {
  associatedtype Root
  var address: UnsafeMutablePointer<Root> { get }
  func access<Value>(_ keyPath: KeyPath<Root, Value>)
  func withMutation<Value>(
    _ keyPath: WritableKeyPath<Root, Value>,
    mutation: (inout Value) -> Void
  )
}

final class _Storage<Root>: ObservationStorage, Observable {
  let address: UnsafeMutablePointer<Root>
  private let rootKeyPath = \_Storage<Root>.address.pointee
  private let _$observationRegistrar = ObservationRegistrar()

  init(_ value: consuming Root) {
    let _storage = UnsafeMutablePointer<Root>.allocate(capacity: 1)
    _storage.initialize(to: value)
    self.address = _storage
  }

  deinit {
    let oldValue = address.pointee
    // TODO: Does this serve a purpose?
    _ = consume oldValue
    address.deinitialize(count: 1)
    address.deallocate()
  }

  func access<Value>(_ keyPath: KeyPath<Root, Value>) {
    self._$observationRegistrar.access(
      self,
      keyPath: rootKeyPath.appending(path: keyPath)
    )
  }

  func withMutation<Value>(
    _ keyPath: WritableKeyPath<Root, Value>,
    mutation: (inout Value) -> Void
  ) {
    self._$observationRegistrar.withMutation(
      of: self,
      keyPath: rootKeyPath.appending(path: keyPath)
    ) { mutation(&address.pointee[keyPath: keyPath]) }
  }
}

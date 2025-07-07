import IdentifiedCollections
// TODO: Remove
import SwiftUI

@usableFromInline actor RootStore {
  let effects = AsyncStream<Effect<AnyAction>>.makeStream()
  var debouncedOperations: [OperationID: Task<Void, Error>] = [:]
  @MainActor var senders = IdentifiedArrayOf<_Send>()
  @MainActor func addSender(
    id: ObjectIdentifier,
    send: @escaping @MainActor (AnyAction) -> Void,
    onInvalidation: @escaping @MainActor () -> Void
  ) {
    senders.append(.init(id: id, send: send, onInvalidation: onInvalidation))
  }
  @usableFromInline @MainActor func removeSender(id: ObjectIdentifier) {
    senders.remove(id: id)?.onInvalidation()
  }
  func task(
    priority: TaskPriority?,
    operation: @escaping @Sendable (_ send: Send<AnyAction>) async -> Void
  ) async {
    await Task(
      priority: priority,
      operation: {
        await operation(
          Send {
            logEvent(.completed($0))
            // Since we are awaiting these one by one, this should be okay to do.
            self.senders[id: $0.sender]?.send($0)
          }
        )
      }
    )
    .cancellableValue
  }

  // TODO: should inline?
  @MainActor func yield(_ effect: Effect<AnyAction>) {
    effects.continuation.yield(effect)
  }

  func runEffects() async {
    for await effect in effects.stream {
      if let debounce = effect.debounce, let id = effect.id {
        logEvent(.debouncing(effect))
        if let running = debouncedOperations[id] {
          logEvent(.cancelled(id))
          running.cancel()
        }
        // TODO: could this cause some weird reentrant stuff?.
        // eg. what if we hit the self.task but are just about to cancel?
        debouncedOperations[id] = Task {
          try await Task.sleep(for: debounce)
          logEvent(.startedEffect(effect))
          switch effect.operation {
          case let .run(priority, operation):
            await self.task(priority: priority, operation: operation)
            debouncedOperations.removeValue(forKey: id)
          // TODO: Technically you could debounce a synchronous effect.
          case .send, .none: return
          }
        }
      } else {
        /// If an effect has just an `id`, it is intended to cancel the debounced effect
        /// with the same `id`. We look for the matching one, cancel it and remove it.
        if let id = effect.id {
          if let running = debouncedOperations[id] { running.cancel() }
          debouncedOperations.removeValue(forKey: id)
        }
        switch effect.operation {
        case let .run(priority, operation):
          logEvent(.startedEffect(effect))
          await self.task(priority: priority, operation: operation)
        case let .send(action, animation):
          await Task { @MainActor in
            while StoreContext._lock { await Task.yield() }
            withAnimation(animation) {
              self.senders[id: action.sender]?.send(action)
            }
          }
          .cancellableValue
        case .none: continue
        }
      }
    }
  }
  init() { Task { await self.runEffects() } }
}

enum Event {
  case debouncing(Effect<AnyAction>)
  case cancelled(OperationID)
  case startedEffect(Effect<AnyAction>)
  case completed(AnyAction)
}

func logEvent(_ event: Event) {
  #if DEBUG
    Logger.shared.log(
      {
        switch event {
        case let .debouncing(effect):
          """

          [EFFECT - DEBOUNCED] 
          --------------------
          -- ID: \(String(effect.id!.description))
          -- DURATION: \(String(effect.debounce!.description))

          __________________________________________
          """
        case let .cancelled(id):
          """

          [EFFECT - CANCELLED]
          --------------------
          -- ID: \(String(id.description))

          __________________________________________
          """
        case let .startedEffect(effect):
          """

          [EFFECT - STARTED] 
          --------------------
          -- OPERATION: \(effect.operation)

          __________________________________________
          """
        case let .completed(result):
          """

          [EFFECT - COMPLETE]
          --------------------
          -- SENDING: \(result.action.base)

          __________________________________________
          """
        }
      }()
    )
  #endif
}

struct _Send: Identifiable, Sendable {
  let id: ObjectIdentifier
  let send: @MainActor (AnyAction) -> Void
  let onInvalidation: @MainActor () -> Void
}

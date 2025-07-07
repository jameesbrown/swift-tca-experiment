@_exported import CasePaths
@_exported import ConcurrencyExtras
@_exported import Dependencies
@_exported import IdentifiedCollections
@_exported import SharedState
@_exported import Validated

extension Validated: @retroactive @unchecked Sendable
where Value: Sendable, Error: Sendable {}

public typealias Reducer<State, Action> = @Sendable @MainActor (
  inout Observed<State>, Action
) -> Effect<Action>

/// A noop reducer.
public func empty<State, Action>() -> Reducer<State, Action> {
  { _, _ in .none }
}

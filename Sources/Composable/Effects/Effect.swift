// MIT License
//
// Copyright (c) 2020 Point-Free, Inc.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import CasePaths
import Dependencies
import SwiftUI
import Tagged

public struct Effect<Action> {
  init(operation: Operation) { self.operation = operation }
  let operation: Operation
  enum Operation: @unchecked Sendable {
    case run(
      TaskPriority? = nil,
      @Sendable (_ send: Send<Action>) async -> Void
    )
    case send(Action, Animation? = nil)
    case none
  }
  /// Used only by `RootStore` to keep track of debounced operations.
  var id: OperationID?
  private(set) var debounce: ContinuousClock.Duration?
  func map<NewAction>(_ transform: (Self) -> Effect<NewAction>) -> Effect<
    NewAction
  > {
    var newEffect = transform(self)
    newEffect.debounce = self.debounce
    newEffect.id = self.id
    return newEffect
  }

  public func debounced<V: Equatable>(
    for duration: ContinuousClock.Duration,
    id: CaseKeyPath<Action, V>
  ) -> Self {
    var debounced = self
    debounced.debounce = duration
    debounced.id = .init(.init(id))
    return debounced
  }
  public func debounced<ID: Hashable>(
    for duration: ContinuousClock.Duration,
    id: ID
  ) -> Self {
    var debounced = self
    debounced.debounce = duration
    debounced.id = .init(.init(id))
    return debounced
  }

  /// Cancels the effect with the passed in `id` before running this one.
  public func cancelling<V: Equatable>(id: CaseKeyPath<Action, V>) -> Self {
    var replacement = self
    replacement.id = .init(.init(id))
    return replacement
  }
  /// Cancels the effect with the passed in `id` before running this one.
  public func cancelling<ID: Hashable>(id: ID) -> Self {
    var replacement = self
    replacement.id = .init(.init(id))
    return replacement
  }

  public static var none: Self { .init(operation: .none) }

  public static func run(
    priority: TaskPriority? = nil,
    operation: @escaping @Sendable (_ send: Send<Action>) async throws -> Void,
    catch handler: (
      @Sendable (_ error: Error, _ send: Send<Action>) async -> Void
    )? = nil,
    fileID: StaticString = #fileID,
    line: UInt = #line
  ) -> Self {
    withEscapedDependencies { escaped in
      Self(
        operation: .run(priority) { send in
          await escaped.yield {
            do { try await operation(send) } catch is CancellationError {
              return
            } catch {
              guard let handler else {
                assertionFailure(
                  """
                  Uncaught error \(error). 
                  Provide a closure for the `catch` argument to handle errors.
                  """
                )
                return
              }
              await handler(error, send)
            }
          }
        }
      )
    }
  }

  /// Sends an action back into the system with an animation.
  ///
  /// - Parameters:
  ///   - action: An action.
  ///   - animation: An animation.
  @MainActor public static func send(
    _ action: Action,
    animation: Animation? = nil
  ) -> Self { Self(operation: .send(action, animation)) }
}

public struct Send<Action>: Sendable {
  let send: @MainActor @Sendable (Action) -> Void
  public init(send: @escaping @MainActor @Sendable (Action) -> Void) {
    self.send = send
  }
  /// Sends an action back into the system from an effect.
  ///
  /// - Parameter action: An action.
  @MainActor public func callAsFunction(_ action: Action) {
    guard !Task.isCancelled else { return }
    self.send(action)
  }
  /// Sends an action back into the system from an effect with animation.
  ///
  /// - Parameters:
  ///   - action: An action.
  ///   - animation: An animation.
  @MainActor public func callAsFunction(_ action: Action, animation: Animation?)
  { callAsFunction(action, transaction: Transaction(animation: animation)) }

  /// Sends an action back into the system from an effect with transaction.
  ///
  /// - Parameters:
  ///   - action: An action.
  ///   - transaction: A transaction.
  @MainActor public func callAsFunction(
    _ action: Action,
    transaction: Transaction
  ) {
    guard !Task.isCancelled else { return }
    withTransaction(transaction) { self(action) }
  }
}

extension Effect: Sendable where Action: Sendable {}

typealias OperationID = Tagged<
  Effect<AnyAction>.Operation, UncheckedSendable<AnyHashable>
>

extension Effect {
  @MainActor func sendAsAnyAction(_ sender: ObjectIdentifier) -> Effect<
    AnyAction
  > where Action: Sendable {
    var effect =
      switch operation {
      case let .run(priority, operation):
        Effect<AnyAction>
          .run(
            priority: priority,
            operation: { send in
              await operation(
                .init { action in
                  send(.init(sender: sender, action: .init(action)))
                }
              )
            }
          )
      case let .send(action, animation):
        Effect<AnyAction>
          .send(
            .init(sender: sender, action: .init(action)),
            animation: animation
          )
      case .none: Effect<AnyAction>.none
      }
    effect.debounce = self.debounce
    effect.id = self.id
    return effect
  }
  @MainActor func embed<ParentAction: CasePathable & Sendable>(
    _ keyPath: CaseKeyPath<ParentAction, Action>
  ) -> Effect<ParentAction> where Action: Sendable {
    @UncheckedSendable var keyPath = keyPath
    return switch self.operation {
    case let .run(priority, operation):
      Effect<ParentAction>
        .run(
          priority: priority,
          operation: { [$keyPath] send in
            await operation(
              .init { action in send($keyPath.wrappedValue(action)) }
            )
          }
        )
    case let .send(action, animation):
      Effect<ParentAction>.send(keyPath(action), animation: animation)
    case .none: Effect<ParentAction>.none
    }
  }
}

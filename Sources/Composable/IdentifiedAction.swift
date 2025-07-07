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

/// A wrapper type for actions that can be presented in a list.
///
/// Use this type for modeling a feature's domain that needs to present child features using
/// ``Reducer/forEach(_:action:element:fileID:line:)-8wpyp``.
public enum IdentifiedAction<ID: Hashable & Sendable, Action>: CasePathable {
  /// An action sent to the element at a given identifier.
  case element(id: ID, action: Action)

  public static var allCasePaths: AllCasePaths { AllCasePaths() }

  public struct AllCasePaths {
    public var element: AnyCasePath<IdentifiedAction, (id: ID, action: Action)>
    {
      AnyCasePath(
        embed: { .element(id: $0, action: $1) },
        extract: {
          guard case let .element(id, action) = $0 else { return nil }
          return (id, action)
        }
      )
    }

    public subscript(id id: ID) -> AnyCasePath<IdentifiedAction, Action> {
      AnyCasePath(
        embed: { .element(id: id, action: $0) },
        extract: {
          guard case .element(id, let action) = $0 else { return nil }
          return action
        }
      )
    }
  }
}

extension IdentifiedAction: Equatable where Action: Equatable {}
extension IdentifiedAction: Hashable where Action: Hashable {}
extension IdentifiedAction: Sendable where ID: Sendable, Action: Sendable {}

extension IdentifiedAction: Decodable where ID: Decodable, Action: Decodable {}
extension IdentifiedAction: Encodable where ID: Encodable, Action: Encodable {}

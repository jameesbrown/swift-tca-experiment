// MIT License
//
// Copyright (c) 2021 Point-Free, Inc.
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

import SwiftUI

extension View {
  @_disfavoredOverload public func sheet<Item, ID: Hashable, Content: View>(
    item: Binding<Item?>,
    id: KeyPath<Item, ID>,
    onDismiss: (() -> Void)? = nil,
    @ViewBuilder content: @escaping (Binding<Item>) -> Content
  ) -> some View {
    sheet(item: item[id: id], onDismiss: onDismiss) {
      content(Binding(unwrapping: item, default: $0.initialValue))
    }
  }
  /// Presents a sheet using a binding as a data source for the sheet's content.
  ///
  /// A version of ``SwiftUI/View/sheet(item:id:onDismiss:content:)-1hi9l`` that takes an
  /// identifiable item.
  ///
  /// - Parameters:
  ///   - item: A binding to an optional source of truth for the sheet. When `item` is non-`nil`,
  ///     the system passes the item's content to the modifier's closure. You display this content
  ///     in a sheet that you create that the system displays to the user. If `item`'s identity
  ///     changes, the system dismisses the sheet and replaces it with a new one using the same
  ///     process.
  ///   - onDismiss: The closure to execute when dismissing the sheet.
  ///   - content: A closure returning the content of the sheet.
  @_disfavoredOverload public func sheet<Item: Identifiable, Content: View>(
    item: Binding<Item?>,
    onDismiss: (() -> Void)? = nil,
    @ViewBuilder content: @escaping (Binding<Item>) -> Content
  ) -> some View {
    sheet(item: item, id: \.id, onDismiss: onDismiss, content: content)
  }

  /// Presents a sheet using a binding as a data source for the sheet's content.
  ///
  /// A version of ``SwiftUI/View/sheet(item:id:onDismiss:content:)-1hi9l`` that is passed an item
  /// and not a binding to an item.
  ///
  /// - Parameters:
  ///   - item: A binding to an optional source of truth for the sheet. When `item` is non-`nil`,
  ///     the system passes the item's content to the modifier's closure. You display this content
  ///     in a sheet that you create that the system displays to the user. If `item`'s identity
  ///     changes, the system dismisses the sheet and replaces it with a new one using the same
  ///     process.
  ///   - id: The key path to the provided item's identifier.
  ///   - onDismiss: The closure to execute when dismissing the sheet.
  ///   - content: A closure returning the content of the sheet.
  public func sheet<Item, ID: Hashable, Content: View>(
    item: Binding<Item?>,
    id: KeyPath<Item, ID>,
    onDismiss: (() -> Void)? = nil,
    @ViewBuilder content: @escaping (Item) -> Content
  ) -> some View {
    sheet(item: item, id: id, onDismiss: onDismiss) { content($0.wrappedValue) }
  }
}

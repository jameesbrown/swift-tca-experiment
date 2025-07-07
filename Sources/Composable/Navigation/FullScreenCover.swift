import SwiftUI

extension View {
  public func fullScreenCover<D, C: View>(
    item: Binding<D?>,
    @ViewBuilder destination: @escaping (D) -> C
  ) -> some View {
    fullScreenCover(isPresented: Binding(item)) {
      if let item = item.wrappedValue { destination(item) }
    }
  }
  @_disfavoredOverload public func fullScreenCover<D, C: View>(
    item: Binding<D?>,
    @ViewBuilder destination: @escaping (Binding<D>) -> C
  ) -> some View {
    fullScreenCover(item: item) { _ in
      Binding(unwrapping: item).map(destination)
    }
  }
}

import SwiftUI
#if os(iOS)
import UIKit
#endif

package let scrollCoordinatesSpaceName = "Scroll"

/// Attributes from the `ScrollView` to pass down to the `reorderable` so that it can autoscroll.
@available(iOS 17.0, macOS 15.0, *)
package struct AutoScrollContainerAttributes {
  let position: Binding<ScrollPosition>
  let bounds: CGSize
  let contentBounds: CGSize
  let offset: CGPoint
  // Abstracted scrolling and current point for iOS 17 fallback (UIKit) or iOS 18 (SwiftUI)
  let scrollTo: (CGPoint) -> Void
  let currentPoint: () -> CGPoint?
}

/// Key used to set and retrieve the `ScrollView` attributes from the environment.
@available(iOS 17.0, macOS 15.0, *)
private struct AutoScrollContainerAttributesEnvironmentKey: EnvironmentKey {
  static let defaultValue: AutoScrollContainerAttributes? = nil
}

@available(iOS 17.0, macOS 15.0, *)
extension EnvironmentValues {
  package var autoScrollContainerAttributes: AutoScrollContainerAttributes? {
    get { self[AutoScrollContainerAttributesEnvironmentKey.self] }
    set { self[AutoScrollContainerAttributesEnvironmentKey.self] = newValue }
  }
}

/// Information about the current scroll state.
///
/// This only exists to use as the "transformation" type for `onScrollGeometryChange`.
private struct ScrollInfo: Equatable {
  let bounds: CGSize
  let offset: CGPoint
}

#if os(iOS)
// A tiny helper to discover the ancestor UIScrollView and observe its changes on iOS 17.
@available(iOS 17.0, *)
private struct ScrollViewIntrospector: UIViewRepresentable {
  let onResolve: (UIScrollView) -> Void
  func makeUIView(context: Context) -> UIView { IntrospectView(onResolve: onResolve) }
  func updateUIView(_ uiView: UIView, context: Context) {}

  private final class IntrospectView: UIView {
    let onResolve: (UIScrollView) -> Void
    init(onResolve: @escaping (UIScrollView) -> Void) {
      self.onResolve = onResolve
      super.init(frame: .zero)
      isUserInteractionEnabled = false
      backgroundColor = .clear
    }
    required init?(coder: NSCoder) { nil }
    override func didMoveToWindow() {
      super.didMoveToWindow()
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        if let sv = self.enclosingScrollView() {
          self.onResolve(sv)
        }
      }
    }
    private func enclosingScrollView() -> UIScrollView? {
      var v: UIView? = self
      while let view = v {
        if let sv = view as? UIScrollView { return sv }
        v = view.superview
      }
      return nil
    }
  }
}
#endif

/// View Modifier used to enable autoscrolling when the use user drags an element to the edge of the `ScrollView`.
@available(iOS 17.0, macOS 15.0, *)
private struct AutoScrollOnEdgesViewModifier: ViewModifier {
  @State var position: ScrollPosition = .init(idType: Never.self, x: 0.0, y: 0.0)
  @State var scrollContentBounds: ScrollInfo = ScrollInfo(bounds: CGSize.zero, offset: .zero)
#if os(iOS)
  @State private var uiScrollView: UIScrollView?
  @State private var offsetObservation: NSKeyValueObservation?
  @State private var sizeObservation: NSKeyValueObservation?
#endif
  
  func body(content: Content) -> some View {
    GeometryReader { proxy in
      Group {
        if #available(iOS 18.0, *) {
          content
            .coordinateSpace(name: scrollCoordinatesSpaceName)
            .scrollPosition($position)
            .onScrollGeometryChange(for: ScrollInfo.self, of: {
              return ScrollInfo(bounds: $0.contentSize, offset: $0.contentOffset)
            }, action: { oldValue, newValue in
              if (scrollContentBounds != newValue) {
                scrollContentBounds = newValue
              }
            })
        } else {
          // iOS 17 fallback: we can set basic values so API compiles; autoscroll is effectively disabled.
          content
            .coordinateSpace(name: scrollCoordinatesSpaceName)
            .scrollPosition($position)
#if os(iOS)
            .background(
              ScrollViewIntrospector { sv in
                if uiScrollView !== sv {
                  uiScrollView = sv
                  // Observe both contentOffset and contentSize to keep state in sync.
                  offsetObservation = sv.observe(\.contentOffset, options: [.new, .initial]) { scrollView, _ in
                      let info = ScrollInfo(bounds: scrollView.contentSize, offset: scrollView.contentOffset)
                      if scrollContentBounds != info { scrollContentBounds = info }
                    }
                  sizeObservation = sv.observe(\.contentSize, options: [.new, .initial]) { scrollView, _ in
                      let info = ScrollInfo(bounds: scrollView.contentSize, offset: scrollView.contentOffset)
                      if scrollContentBounds != info { scrollContentBounds = info }
                    }
                }
              }
            )
#endif
        }
      }
      .environment(
        \.autoScrollContainerAttributes,
         AutoScrollContainerAttributes(
          position: $position,
          bounds: proxy.size,
          contentBounds: scrollContentBounds.bounds,
          offset: scrollContentBounds.offset,
          scrollTo: {
            if #available(iOS 18.0, *) {
              position.wrappedValue.scrollTo(point: $0)
            } else {
              #if os(iOS)
              uiScrollView?.setContentOffset($0, animated: false)
              #endif
            }
          },
          currentPoint: {
            if #available(iOS 18.0, *) {
              return position.wrappedValue.point
            } else {
              #if os(iOS)
              return uiScrollView?.contentOffset
              #else
              return nil
              #endif
            }
          }
         ))
    }
  }
}

@available(iOS 17.0, macOS 10.15, *)
extension ScrollView {
  /// Enables the `ScrollView` to automatically scroll when the user drags an element from a ``ReorderableVStack`` or ``ReorderableHStack`` to its edges.
  ///
  /// Because ``Reorderable`` doesn't rely on SwiftUI's native `onDrag`, it also doesn't automatically trigger auto-scrolling when users drag the element to the edge of the parent/ancestor `ScrollView`. Applying this modifier to the `ScrollView` re-enables this behavior.
  public func autoScrollOnEdges() -> some View {
    modifier(AutoScrollOnEdgesViewModifier())
  }
}

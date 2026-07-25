//
//  AppStoreTransition.swift
//  Test
//
//  Created by 胡杰 on 2026/7/25.
//

import SwiftUI

struct TransitionConfig {
    var cardCornerRadius: CGFloat = 20
    var detailCornerRadius: CGFloat = 55
    var detailCardHeight: CGFloat = 460
    var animation: Animation = .smooth(duration: 0.3, extraBounce: 0)
}

struct AppStoreTransition<Hero: View, Content: View>: View {
    var config: TransitionConfig = .init()
    @ViewBuilder var hero: (_ isExpanded: Bool, _ dismiss: (() -> ())?) -> Hero
    @ViewBuilder var content: (_ safeArea: EdgeInsets, _ dismiss: @escaping () -> ()) -> Content
    @State private var showFullScreenCover: Bool = false
    @State private var sourceRect: CGRect = .zero
    @State private var buttonScale: CGFloat = 1
    var body: some View {
        Button {
            withoutAnimation {
                showFullScreenCover = true
            }
        } label: {
            Rectangle()
                .foregroundStyle(.clear)
                .overlay {
                    if !showFullScreenCover {
                        hero(false, nil)
                    }
                }
                .clipShape(.rect(cornerRadius: config.cardCornerRadius))
                .contentShape(.rect(cornerRadius: config.cardCornerRadius))
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: { newValue in
                    buttonScale = newValue.width / sourceRect.width
                }
            
        }
        .buttonStyle(AppStoreButtonStyle())
        .onGeometryChange(for: CGRect.self, of: {
            $0.frame(in: .global)
        }, action: { newValue in
            sourceRect = newValue
        })
        .fullScreenCover(isPresented: $showFullScreenCover) {
            TransitionFullScreenCover(
                config: config,
                buttonScale: $buttonScale,
                showFullScreenCover: $showFullScreenCover,
                sourceRect: $sourceRect,
                hero: hero,
                content: content
            )
        }
    }
}

fileprivate struct TransitionFullScreenCover<Hero: View, Content: View>: View {
    var config: TransitionConfig
    @Binding var buttonScale: CGFloat
    @Binding var showFullScreenCover: Bool
    @Binding var sourceRect: CGRect
    @ViewBuilder var hero: (_ isExpanded: Bool, _ dismiss: (() -> ())?) -> Hero
    @ViewBuilder var content: (_ safeArea: EdgeInsets, _ dismiss: @escaping () -> ()) -> Content
    @State private var animateContents: Bool = false
    @State private var dragScale: CGFloat = 1
    @State private var isHorizontalSwipe: Bool = false
    @State private var safeArea: EdgeInsets = .init()
    var body: some View {
        let cornerRadius = animateContents ? config.detailCornerRadius : config.cardCornerRadius
        
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                Rectangle()
                    .foregroundStyle(.clear)
                    .overlay {
                        hero(animateContents, dismiss)
                    }
                    .frame(
                        width: animateContents ? nil : sourceRect.width,
                        height: animateContents ? config.detailCardHeight : sourceRect.height
                    )
                    .offset(x: animateContents ? 0 : sourceRect.minX,
                            y: animateContents ? 0: sourceRect.minY)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .visualEffect { [animateContents] content, proxy in
                        let minY = proxy.frame(in: .scrollView).minY
                        let height = animateContents ? (proxy.size.height + 10) : 0
                        return content
                            .offset(y: -minY > height ? -(minY + height) : 0)
                            .offset(y: minY > 0 ? -minY : 0)
                    }
                    .zIndex(1000)
                
                content(safeArea, dismiss)
            }
        }
        .background(.background)
        .mask(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .frame(
                    width: animateContents ? nil : sourceRect.width,
                    height: animateContents ? nil : sourceRect.height
                )
                .offset(x: animateContents ? 0 : sourceRect.minX,
                        y: animateContents ? 0: sourceRect.minY)
        }
        .overlay(alignment: .topLeading) {
            DismissButton()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .frame(
                    width: animateContents ? nil : sourceRect.width,
                    height: animateContents ? config.detailCardHeight : sourceRect.height
                )
                .offset(x: animateContents ? 0 : sourceRect.minX,
                        y: animateContents ? safeArea.top: sourceRect.minY)
        }
        .scaleEffect(dragScale)
        .scaleEffect(buttonScale)
        .ignoresSafeArea()
        .gesture(AppStoreGesture {
            handleGesture($0)
        })
        .onGeometryChange(for: EdgeInsets.self) {
            $0.safeAreaInsets
        } action: { newValue in
            safeArea = newValue
        }
        .task {
            guard !animateContents else {return}
            withAnimation(config.animation) {
                animateContents = true
            }
        }
        .presentationBackground {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(animateContents ? 1 : 0)
        }
    }
    
    @ViewBuilder
    private func DismissButton() -> some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .frame( width: 20, height: 30)
                .contentShape(.circle)
        }
        .buttonStyle(.glass)
        .padding(.trailing, 15)
        .animation(.linear(duration: 0.15)) {
            $0.opacity(animateContents ? 1 : 0)
        }
        .opacity((dragScale - 0.95) / 0.05)
    }

    private func handleGesture(_ gesture: UIPanGestureRecognizer) {
        let state = gesture.state
        let translationX = gesture.translation(in: gesture.view).x * 1.2
        let translationY = gesture.translation(in: gesture.view).y
        let translation = isHorizontalSwipe ? translationX : translationY
        
        if state == .began {
            isHorizontalSwipe = gesture.location(in: gesture.view).x < 30
        }
        
        if state == .began || state == .changed {
            let progress = max(min(translation / config.detailCardHeight, 1), 0)
            dragScale = 1 - (progress * 0.2)
        } else {
            isHorizontalSwipe = false
            
            if dragScale < 0.9 {
                dismiss()
            } else {
                withAnimation(config.animation) {
                    dragScale = 1
                }
            }
        }
    }
    
    private func dismiss() {
        withAnimation(config.animation, completionCriteria: .removed) {
            dragScale = 1
            animateContents = false
        } completion: {
            withoutAnimation {
                showFullScreenCover = false
            }
        }
    }
}

private struct AppStoreButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .keyframeAnimator(initialValue: 1.0, trigger: configuration.isPressed) { content, scale in
                content
                    .scaleEffect(scale)
            } keyframes: { _ in
                if configuration.isPressed {
                    CubicKeyframe(0.95, duration: 0.15)
                } else {
                    CubicKeyframe(1, duration: 0.15)
                }
            }

    }
}

fileprivate struct AppStoreGesture: UIGestureRecognizerRepresentable {
    var handle: (UIPanGestureRecognizer) -> ()
    func makeUIGestureRecognizer(context: Context) -> some UIPanGestureRecognizer {
        let gesture = UIPanGestureRecognizer()
        gesture.delegate = context.coordinator
        return gesture
    }
    
    func updateUIGestureRecognizer(_ recognizer: UIGestureRecognizerType, context: Context) {
    }
    
    func handleUIGestureRecognizerAction(_ recognizer: UIGestureRecognizerType, context: Context) {
        handle(recognizer)
    }
    
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            if let scrollview = otherGestureRecognizer.view as? UIScrollView {
                let contentOffset = scrollview.contentOffset.y.rounded()
                
                return contentOffset <= 1
            }
            return false
        }
        
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pangesture = gestureRecognizer as? UIScreenEdgePanGestureRecognizer else {
                return false
            }
            let velocity = pangesture.velocity(in: pangesture.view)
            
            let locationX = pangesture.location(in: pangesture.view).x
            
            return velocity.y > abs(velocity.x) || (locationX < 30)
        }
    }
}

fileprivate extension View {
    func withoutAnimation(block: @escaping () -> ()) {
        DispatchQueue.main.async {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                block()
            }
        }
    }
}

#Preview {
    ContentView()
}

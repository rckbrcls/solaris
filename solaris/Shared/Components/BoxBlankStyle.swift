//
//  BoxBlankStyle.swift
//  solaris
//
//  Created by Erick Barcelos on 12/04/25.
//

import SwiftUI

struct BoxBlankStyle: ViewModifier {
    var cornerRadius: CGFloat = 10
    var padding: CGFloat = 16
    var width: CGFloat? = nil
    var maxWidth: CGFloat? = nil
    var height: CGFloat? = nil
    var maxHeight: CGFloat? = nil
    
    func body(content: Content) -> some View {
        var view = AnyView(content)
        if width != nil || height != nil {
            view = AnyView(view.frame(width: width, height: height))
        }
        if maxWidth != nil || maxHeight != nil {
            view = AnyView(view.frame(maxWidth: maxWidth, maxHeight: maxHeight))
        }
        return view
            .padding(padding)
            .fontWeight(.bold)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.borderStrong, lineWidth: 1)
                    .frame(maxWidth: maxWidth ?? width, maxHeight: maxHeight ?? height)
                    .allowsHitTesting(false)
            )
    }
}

// Extensão para facilitar o uso do BoxBlankStyle
extension View {
    public func boxBlankStyle(cornerRadius: CGFloat = 10, padding: CGFloat = 16, width: CGFloat? = nil, maxWidth: CGFloat? = nil, height: CGFloat? = nil, maxHeight: CGFloat? = nil) -> some View {
        self.modifier(BoxBlankStyle(cornerRadius: cornerRadius, padding: padding, width: width, maxWidth: maxWidth, height: height, maxHeight: maxHeight))
    }
}

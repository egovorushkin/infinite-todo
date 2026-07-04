//
//  ProgressRing.swift
//  todo
//
//  A tiny glanceable completion ring, used next to a parent task's "3/7"
//  count — a ring reads at a glance where a bare fraction needs reading.
//

import SwiftUI

struct ProgressRing: View {
    let progress: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.snappy, value: progress)
    }
}

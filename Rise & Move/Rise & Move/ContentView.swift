//
//  ContentView.swift
//  Rise & Move
//
//  Created by Joshua Costanza on 12/29/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Rise & Move")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("An alarm designed to help you break morning autopilot")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    ContentView()
}


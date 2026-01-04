//
//  NotificationDisabledBanner.swift
//  Rise & Move
//
//  Created by Joshua Costanza on 1/3/26.
//

import SwiftUI

struct NotificationDisabledBanner: View {
    let title: String
    let message: String
    let ctaTitle: String
    let onTapCTA: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .opacity(0.9)
                }

                Spacer(minLength: 8)
            }

            Button(action: onTapCTA) {
                Text(ctaTitle)
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.15))
        )
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

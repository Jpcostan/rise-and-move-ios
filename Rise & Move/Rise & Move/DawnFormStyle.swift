//
//  DawnFormStyle.swift
//  Rise & Move
//
//  Created by Joshua Costanza on 12/31/25.
//

import SwiftUI

struct DawnFormStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { configureFormAppearance() }
            .onDisappear { resetFormAppearance() }
    }

    private func configureFormAppearance() {
        let bg = UIColor.clear
        UITableView.appearance().backgroundColor = bg
        UITableViewCell.appearance().backgroundColor = bg

        let material = UIColor.white.withAlphaComponent(0.10)
        UITableView.appearance().separatorStyle = .none
        UITableView.appearance().sectionHeaderTopPadding = 10

        UITableViewCell.appearance().contentView.backgroundColor = material
        UITableViewCell.appearance().backgroundColor = bg
    }

    private func resetFormAppearance() {
        // Optional: keep as-is since your whole app uses the dawn theme.
        // If you later add screens that need default styling, we can reset here.
    }
}

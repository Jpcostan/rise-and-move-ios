//
//  AppRouter.swift
//  Rise & Move
//
//  Created by Joshua Costanza on 12/29/25.
//
import Foundation
import Combine

@MainActor
final class AppRouter: ObservableObject {
    @Published var activeAlarmID: UUID? = nil

    // Phase 9.1: Stub. StoreKit will flip this later.
    @Published var isPro: Bool = true

    func openAlarm(id: UUID) {
        activeAlarmID = id
    }

    func clearActiveAlarm() {
        activeAlarmID = nil
    }
}

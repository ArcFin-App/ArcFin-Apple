// SPDX-License-Identifier: AGPL-3.0-or-later

import ComposableArchitecture
import Foundation
import AuthCore

// MARK: - Root reducer

@Reducer
public struct RootReducer: Sendable {

    @ObservableState
    public struct State: Equatable {
        public var authState: AuthState = .unauthenticated
        public var selectedTab: AppTab = .home

        public init() {}
    }

    public enum Action: Sendable {
        case onAppear
        case setAuthState(AuthState)
        case selectTab(AppTab)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .none

            case let .setAuthState(authState):
                state.authState = authState
                return .none

            case let .selectTab(tab):
                state.selectedTab = tab
                return .none
            }
        }
    }
}

// MARK: - App tab

public enum AppTab: String, Sendable, Equatable, CaseIterable {
    case home        = "Home"
    case library     = "Library"
    case search      = "Search"
    case stats       = "Stats"
    case seerr       = "Requests"
    case settings    = "Settings"
}

// MARK: - Store typealias

public typealias RootStore = StoreOf<RootReducer>

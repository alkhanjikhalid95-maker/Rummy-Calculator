//
//  ContentView.swift
//  Rummy Calculator
//
//  Created by khalid alkhanji on 20/03/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = GameViewModel()
    @Environment(\.scenePhase) private var scenePhase

    private var guest: NearbyGuest { .shared }

    var body: some View {
        ZStack {
            if viewModel.isGameStarted {
                GameScreenView(viewModel: viewModel)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            } else if guest.phase == .following {
                FollowingGameView(guest: guest)
                    .transition(.opacity)
            } else {
                StartPageView(viewModel: viewModel)
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading)))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: viewModel.isGameStarted)
        .animation(.easeInOut(duration: 0.3), value: guest.phase)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                viewModel.persistSession()
            }
        }
    }
}

#Preview {
    ContentView()
}

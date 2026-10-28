//
//  MyBucharestApp.swift
//  MyBucharest
//
//  Created by Vlad Rusu on 04/08/2026.
//

import AVFoundation
import SwiftUI

@main
struct MyBucharestApp: App {
    @State private var router = AppRouter()
    @State private var store = PlacesStore()
    @State private var profile = ProfileStore()
    @State private var location = LocationService()

    init() {
        // Sunetul clipurilor se aude și când telefonul e pe silențios, ca în TikTok/Reels.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(store)
                .environment(profile)
                .environment(location)
        }
    }
}

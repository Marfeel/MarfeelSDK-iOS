//
//  ContentView.swift
//  Playground
//
//  Created by Marc García Lopez on 02/05/2023.
//

import SwiftUI

struct ContentView: View {
    @StateObject var store = BlogPostsStore()

    var body: some View {
        TabView {
            AllPosts()
                .environmentObject(store)
                .tabItem {
                    Image(systemName: "list.dash")
                    Text("Posts")
                }
            ExperiencesView()
                .tabItem {
                    Image(systemName: "sparkles")
                    Text("Experiences")
                }
        }
    }
}
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

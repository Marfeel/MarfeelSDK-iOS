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
        AllPosts()
            .environmentObject(store)
            .tabItem {
                Image(systemName: "list.dash")
                Text("See all")
            }
    }
}
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

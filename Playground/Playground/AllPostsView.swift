//
//  AllPostsView.swift
//  Playground
//
//  Created by Marc García Lopez on 02/05/2023.
//

import SwiftUI
import MarfeelSDK_iOS

struct AllPosts: View {
    @EnvironmentObject var store: BlogPostsStore
    
    var body: some View {
        NavigationView {
            List {
                ForEach(store.blogPosts) {post in
                    NavigationLink(destination: BlogPostView(blogPost: post)) {
                        BlogPostCardList(blogPost: post)
                    }
                }
            }
            .navigationTitle("All blog posts")
            .listStyle(InsetListStyle())
        }
        .onAppear(perform: {
            CompassTracker.shared.setUserType(.logged)
            CompassTracker.shared.addUserSegment("segment1")
            CompassTracker.shared.addUserSegment("segment1")
            CompassTracker.shared.addUserSegment("segment2")
            CompassTracker.shared.setSessionVar(name: "lolo", value: "lola")
            CompassTracker.shared.setSessionVar(name: "lolo2", value: "lola2")
            CompassTracker.shared.setUserVar(name: "hihi", value: "haha")
            CompassTracker.shared.setUserVar(name: "hihi2", value: "haha2")
            CompassTracker.shared.trackScreen("ios homepage")
        })
    }
}

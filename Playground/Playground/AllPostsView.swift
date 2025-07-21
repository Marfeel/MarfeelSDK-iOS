//
//  AllPostsView.swift
//  Playground
//
//  Created by Marc García Lopez on 02/05/2023.
//

import SwiftUI
import SwiftUIIntrospect
import MarfeelSDK_iOS

struct AllPosts: View {
    @EnvironmentObject var store: BlogPostsStore
    @State private var scrollView: UIScrollView?
    
    var body: some View {
        NavigationView {
            ScrollView {
                ForEach(store.blogPosts) {post in
                    NavigationLink(destination: BlogPostView(blogPost: post)) {
                        BlogPostCardList(blogPost: post)
                    }
                }
            }
            .navigationTitle("All blog posts")
            .listStyle(InsetListStyle())
            .introspect(.scrollView, on: .iOS(.v13, .v14, .v15, .v16, .v17, .v18)) {
                scrollView = $0
             }
            .onAppear(perform: {
                CompassTracker.shared.setLandingPage("landing page")
                CompassTracker.shared.setUserType(.logged)
                CompassTracker.shared.addUserSegment("segment1")
                CompassTracker.shared.addUserSegment("segment1")
                CompassTracker.shared.addUserSegment("segment2")
                CompassTracker.shared.setSessionVar(name: "lolo", value: "lola")
                CompassTracker.shared.setSessionVar(name: "lolo2", value: "lola2")
                CompassTracker.shared.setUserVar(name: "hihi", value: "haha")
                CompassTracker.shared.setUserVar(name: "hihi2", value: "haha2")
                CompassTracker.shared.trackScreen(name: "ios homepage", scrollView: scrollView)
                CompassTracker.shared.setPageMetric(name: "metric_string", value: 100)
            })
        }
    }
}

//
//  BlogPostView.swift
//  Playground
//
//  Created by Marc García Lopez on 02/05/2023.
//

import SwiftUI
import SDWebImageSwiftUI

struct BlogPostView: View {
    
    var blogPost: BlogPost
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack {
                    WebImage(url: blogPost.image)
                        .renderingMode(.original)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 310)
                        .frame(maxWidth: UIScreen.main.bounds.width)
                        .clipped()
                    
                    VStack {
                        HStack {
                            Text(blogPost.title)
                                .font(.title3)
                                .fontWeight(.heavy)
                                .foregroundColor(.primary)
                                .lineLimit(3)
                                .padding(.vertical, 15)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        
                        Text(blogPost.blogpost)
                            .multilineTextAlignment(.leading)
                            .font(.body)
                            .foregroundColor(Color.primary.opacity(0.9))
                            .padding(.bottom, 25)
                            .frame(maxWidth: .infinity)
                        
                        if let videoId = blogPost.videoId {
                            YouTubeView(videoId: videoId)
                                .frame(height: 300)
                                .frame(maxWidth: UIScreen.main.bounds.width)
                                .padding()
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

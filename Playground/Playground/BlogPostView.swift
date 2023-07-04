//
//  BlogPostView.swift
//  Playground
//
//  Created by Marc García Lopez on 02/05/2023.
//

import SwiftUI
import SDWebImageSwiftUI
import YouTubePlayerKit
import Combine
import MarfeelSDK_iOS

struct BlogPostView: View {
    var blogPost: BlogPost
    
    @State var isVideoInitialized = false
    private var videoPlayer: YouTubePlayer
    
    init(blogPost: BlogPost) {
        self.blogPost = blogPost
        self.videoPlayer = YouTubePlayer(stringLiteral: "https://youtube.com/watch?v=\(blogPost.videoId)")
    }
    
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
                        YouTubePlayerView(videoPlayer)
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: {
            CompassTracker.shared.trackNewPage(url: URL(string: blogPost.url)!)
            CompassTracker.shared.setPageVar(name: "pepe", value: blogPost.id.description)
            CompassTracker.shared.setPageVar(name: "pepe2", value: blogPost.id.description)
            CompassTracker.shared.setUserVar(name: "pepe-user", value: blogPost.id.description)
        })
        .onReceive(videoPlayer.playbackStatePublisher) { state in
            guard isVideoInitialized else {
                return
            }
            
            switch state {
            case .playing:
                videoPlayer.getCurrentTime {
                    time in
                    do {
                        CompassTrackerMultimedia.shared.registerEvent(id: blogPost.videoId, event: .PLAY, eventTime: Int(try time.get()))
                    } catch {}
                }
            case .paused:
                videoPlayer.getCurrentTime {
                    time in
                    do {
                        CompassTrackerMultimedia.shared.registerEvent(id: blogPost.videoId, event: .PAUSE, eventTime: Int(try time.get()))
                    } catch {}
                }
            case .ended:
                videoPlayer.getCurrentTime {
                    time in
                    do {
                        CompassTrackerMultimedia.shared.registerEvent(id: blogPost.videoId, event: .END, eventTime: Int(try time.get()))
                    } catch {}
                }
            default:
                break
            }
        }
        .onReceive(videoPlayer.durationPublisher) { time in
            guard !isVideoInitialized else {
                return
            }
            CompassTrackerMultimedia.shared.initializeItem(
                id: blogPost.videoId,
                provider: "youtube",
                providerId: blogPost.videoId,
                type: .VIDEO,
                metadata: MultimediaMetadata.init(
                    title: "title",
                    description: "description",
                    url: URL(string: "https://youtube.com/watch?v=\(blogPost.videoId)"),
                    authors: "authors",
                    duration: Int(time)
                )
            )
            videoPlayer.getCurrentTime {
                time in
                do {
                    CompassTrackerMultimedia.shared.registerEvent(id: blogPost.videoId, event: .PLAY, eventTime: Int(try time.get()))
                } catch {}
            }
            self.isVideoInitialized = true
        }
        .onReceive(videoPlayer.currentTimePublisher()) { time in
            CompassTrackerMultimedia.shared.registerEvent(id: blogPost.videoId, event: .UPDATE_CURRENT_TIME, eventTime: Int(time))
        }
    }
}

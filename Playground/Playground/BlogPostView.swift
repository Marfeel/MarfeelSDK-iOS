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
    @State private var experiences: [Experience] = []
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

                        experiencesSection
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                }
                .frame(maxWidth: .infinity)

            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: {
            CompassTracker.shared.trackNewPage(url: URL(string: blogPost.url)!, rs: blogPost.rs)
            CompassTracker.shared.setPageVar(name: "pepe", value: blogPost.id.description)
            CompassTracker.shared.setPageVar(name: "pepe2", value: blogPost.id.description)
            CompassTracker.shared.setUserVar(name: "pepe-user", value: blogPost.id.description)
            CompassTracker.shared.trackConversion(conversion: "conv_1")
            CompassTracker.shared.trackConversion(conversion: "conv_2")
            CompassTracker.shared.trackConversion(
                conversion: "conv_3",
                options: ConversionOptions(
                    initiator: "testInit",
                    id: "testId",
                    value: "testValue",
                    meta: ["key1": "val1", "key2": "val2"],
                    scope: ConversionScope.page
                )
            )
            CompassTracker.shared.trackConversion(
                conversion: "conv_4",
                options: ConversionOptions(
                    initiator: "testInit",
                    id: "4",
                    value: "4",
                    meta: ["key1": "val1", "key2": "val2"]
                )
            )
            CompassTracker.shared.trackConversion(
                conversion: "conv_3",
                options: ConversionOptions(
                    initiator: "testInit",
                    id: "testId",
                    value: "testValue",
                    meta: ["key1": "val1", "key2": "val2"],
                    scope: ConversionScope.page
                )
            )
            CompassTracker.shared.trackConversion(
                conversion: "conv_5"
            )
            CompassTracker.shared.trackConversion(
                conversion: "conv_5"
            )

            CompassTracker.shared.getRFV { _ in }

            CompassTracker.shared.setSiteUserId("test-user-1")

            CompassTracker.shared.getRFV { _ in }

            fetchExperiencesForPost()
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
                        CompassTrackerMultimedia.shared.registerEvent(id: blogPost.videoId, event: .PLAY, eventTime: Int(try time.get().converted(to: .seconds).value))
                    } catch {}
                }
            case .paused:
                videoPlayer.getCurrentTime {
                    time in
                    do {
                        CompassTrackerMultimedia.shared.registerEvent(id: blogPost.videoId, event: .PAUSE, eventTime: Int(try time.get().converted(to: .seconds).value))
                    } catch {}
                }
            case .ended:
                videoPlayer.getCurrentTime {
                    time in
                    do {
                        CompassTrackerMultimedia.shared.registerEvent(id: blogPost.videoId, event: .END, eventTime: Int(try time.get().converted(to: .seconds).value))
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
                    duration: Int(time.converted(to: .seconds).value)
                )
            )
            videoPlayer.getCurrentTime {
                time in
                do {
                    CompassTrackerMultimedia.shared.registerEvent(id: blogPost.videoId, event: .PLAY, eventTime: Int(try time.get().converted(to: .seconds).value))
                } catch {}
            }
            self.isVideoInitialized = true
        }
        .onReceive(videoPlayer.currentTimePublisher()) { time in
            CompassTrackerMultimedia.shared.registerEvent(id: blogPost.videoId, event: .UPDATE_CURRENT_TIME, eventTime: Int(time.converted(to: .seconds).value))
        }
    }

    private var experiencesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Experiences for this page").font(.headline).padding(.top, 16)

            if experiences.isEmpty {
                Text("No experiences fetched yet.")
                    .font(.caption).foregroundColor(.gray)
            } else {
                ForEach(experiences, id: \.id) { exp in
                    let link = RecirculationLink(url: exp.contentUrl ?? blogPost.url, position: 0)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("[\(exp.type.rawValue)] \(exp.name)")
                                .font(.system(size: 12, weight: .semibold))
                            if let family = exp.family {
                                Text("family=\(family.rawValue)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                            }
                        }
                        Spacer()
                        Button("Click") {
                            Experiences.shared.trackClick(experience: exp, link: link)
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                    .onAppear {
                        Experiences.shared.trackImpression(experience: exp, link: link)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fetchExperiencesForPost() {
        Experiences.shared.fetchExperiences(
            filterByType: nil,
            filterByFamily: nil,
            resolve: false,
            url: blogPost.url
        ) { fetched in
            DispatchQueue.main.async {
                experiences = fetched
                for exp in fetched {
                    let link = RecirculationLink(url: exp.contentUrl ?? blogPost.url, position: 0)
                    Experiences.shared.trackEligible(experience: exp, links: [link])
                }
            }
        }
    }
}

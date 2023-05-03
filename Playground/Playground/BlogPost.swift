//
//  BlogPost.swift
//  Playground
//
//  Created by Marc García Lopez on 02/05/2023.
//

import Foundation

struct BlogPost: Identifiable {
    let id = UUID()
    
    var title: String
    var subtitle: String
    var image: URL?
    var blogpost: String
    var featured = false
    var url: String
    var videoId: String?
}

var articleList: [BlogPost] = []

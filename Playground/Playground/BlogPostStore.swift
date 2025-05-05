//
//  BlogPostStore.swift
//  Playground
//
//  Created by Marc García Lopez on 02/05/2023.
//

import Foundation


class BlogPostsStore: ObservableObject {
    var blogPosts: [BlogPost] = [
        BlogPost(
            title: "Post 1 Title",
            subtitle: "Post 1 Subtitle",
            image: URL(string: "https://placedog.net/500/350?1"),
            blogpost: """
                What's that like? What's it taste like? Describe it like Hemingway. Well, Baby O, it's not exactly mai-tais and Yahtzee out here — but let's do it. There are two types of tragedies in life. One is not getting what you want, the other is getting it.

                They somehow managed to get every creep and freak in the universe onto this one plane. Ugly all day. What if I just make her a little pair of wings out of paper?

                The ladies are dirty. Walk away. The ladies are dirty. The first and most important rule of gun-running is to never get shot with your own merchandise. The only question is: "How do we arm the other 11?"

                Unless you're a 20 year old guitarist from Seattle. It's a grunge thing. Well, there's a problem sir, he's got a gun! When I get out of here... I'm gonna have you fired.
            """,
            featured: true,
            url: "http://dev.marfeel.co/2022/11/25/article-with-video-html5/",
            videoId: "UbjLtXKEE-I",
            rs: "recirculation source"
        ),
        BlogPost(
            title: "Post 2 Title",
            subtitle: "Post 2 Subtitle",
            image: URL(string: "https://placedog.net/500/350?2"),
            blogpost: """
                 I drive a Volvo, a beige one. But what I'm dealing with here is one of the most deadly substances the Earth has ever known, so what say you cut me some friggin' slack? I'm one of those fortunate people who like my job, sir. Got my first chemistry set when I was seven, blew my eyebrows off, we never saw the cat again, been into it ever since. I'm ready, ready for the big ride, baby!

                 If you see my wife again, you tell her I love her... she's my hummingbird. I just stole fifty cars in one night! I'm a little tired, little *wired*, and I think I deserve a little appreciation! I think the wife and me are splitting up. Her point is that we're both kind of selfish and unrealistic, so we're not really good for each other.

                 I don't predict it. Nobody does, 'cause i-it's just wind. It's wind. It blows all over the place! He is living. Just not the way you think. I believe it's warlord.

                 Eve, listen to me. The man you think is your husband isn't. I love pressure. I eat it for breakfast. I killed him. I took a grenade, threw it in there and blew him up.

            """,
            featured: false,
            url: "http://dev.marfeel.co/2022/07/29/hola-1/",
            videoId: "UbjLtXKEE-I"
        ),
        BlogPost(
            title: "Post 3 Title",
            subtitle: "Post 3 Subtitle",
            image: URL(string: "https://placedog.net/500/350?3"),
            blogpost: """
                The first and most important rule of gun-running is to never get shot with your own merchandise. On any other day, that might seem strange. They somehow managed to get every creep and freak in the universe onto this one plane.

                The ladies are dirty. Walk away. The ladies are dirty. Sorry boss, but there's only two men I trust. One of them's me. The other's not you. The only question is: "How do we arm the other 11?"

                There are two types of tragedies in life. One is not getting what you want, the other is getting it. Thank God there are still legal ways to exploit developing countries. Now, what would my daughter think of me if I left you to be dishonored and die?

                Put the bunny, back in the box... That's funny, my name's Roger... Two Rogers don't make a right. People don't throw things at me any more. Maybe because I carry a bow around.
            """,
            featured: false,
            url: "http://dev.marfeel.co/2022/07/29/corrupti-sit-vero-asperiores-ratione-non-velit/",
            videoId: "UbjLtXKEE-I"
        ),
        BlogPost(
            title: "Post 4 Title",
            subtitle: "Post 4 Subtitle",
            image: URL(string: "https://placedog.net/500/350?4"),
            blogpost: """
                I think the wife and me are splitting up. Her point is that we're both kind of selfish and unrealistic, so we're not really good for each other. If you see my wife again, you tell her I love her... she's my hummingbird. I just stole fifty cars in one night! I'm a little tired, little *wired*, and I think I deserve a little appreciation!

                I love pressure. I eat it for breakfast. Eve, listen to me. The man you think is your husband isn't. I believe it's warlord.

                I killed him. I took a grenade, threw it in there and blew him up. I don't predict it. Nobody does, 'cause i-it's just wind. It's wind. It blows all over the place! I'm one of those fortunate people who like my job, sir. Got my first chemistry set when I was seven, blew my eyebrows off, we never saw the cat again, been into it ever since.

                I drive a Volvo, a beige one. But what I'm dealing with here is one of the most deadly substances the Earth has ever known, so what say you cut me some friggin' slack? I'm ready, ready for the big ride, baby! He is living. Just not the way you think.

            """,
            featured: false,
            url: "http://dev.marfeel.co/2022/06/28/consectetur-consequuntur-quis-nobis-quia/",
            videoId: "UbjLtXKEE-I"
        )
    ]
}

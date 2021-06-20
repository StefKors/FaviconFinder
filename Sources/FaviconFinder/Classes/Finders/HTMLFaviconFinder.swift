//
//  HTMLFaviconFinder.swift
//  Pods
//
//  Created by William Lumley on 26/5/21.
//

import Foundation

#if canImport(SwiftSoup)
import SwiftSoup

#endif

class HTMLFaviconFinder: FaviconFinderProtocol {

    // MARK: - Types

    struct HTMLFaviconReference {
        let rel: String
        let href: String
    }

    // MARK: - Properties

    var url: URL
    var preferredType: String
    var logEnabled: Bool

    /// When parsing through HTML, these are the type of images we'll look for in the HTML header
    private var acceptableIconTypes = FaviconType.allTypes

    /// The preferred type of favicon we're after
    //var preferredType: String? = FaviconType.appleTouchIcon.rawValue

    required init(url: URL, preferredType: String?, logEnabled: Bool) {
        self.url = url
        self.preferredType = preferredType ?? FaviconType.appleTouchIcon.rawValue //Default to `appleTouchIcon` type if user does not present us with one
        self.logEnabled = logEnabled
    }

    func search(onFind: @escaping ((Result<FaviconURL, FaviconError>) -> Void)) {

        //Download the web page at our URL
        URLSession.shared.dataTask(with: self.url, completionHandler: {(data, response, error) in
            
            //Make sure our data exists
            guard let data = data else {
                if self.logEnabled {
                    print("Could NOT get favicon from url: \(self.url), Data was nil.")
                }
                onFind(.failure(.emptyData))
                return
            }
            
            //Make sure we can parse the response into a string
            guard let html = String(data: data, encoding: String.Encoding.utf8) else {
                if self.logEnabled {
                    print("Could NOT get favicon from url: \(self.url), could not parse HTML.")
                }
                onFind(.failure(.failedToParseHTML))
                return
            }
            
            //Make sure we can find a favicon in our retrieved string (at this point we're assuming it's valid HTML)
            guard let faviconURL = self.faviconURL(from: html) else {
                if self.logEnabled {
                    print("Could NOT get favicon from url: \(self.url), failed to parse favicon from HTML.")
                }
                onFind(.failure(.failedToDownloadFavicon))
                return
            }
            
            //We found our favicon, let's download it
            if self.logEnabled {
                print("Extracted favicon: \(faviconURL.url.absoluteString)")
            }

            onFind(.success(faviconURL))
            
        }).resume()
    }

}

private extension HTMLFaviconFinder {

    /**
     Parses the provided HTML for the favicon URL
     - parameter htmlStr: The HTML that we will be parsing and iterating through to find the favicon
     - returns: The URL that the favicon can be found at
    */
    func faviconURL(from htmlStr: String) -> FaviconURL? {
        var htmlOpt: Document?
        do {
            htmlOpt = try SwiftSoup.parse(htmlStr)
        }
        catch let error {
            if logEnabled {
                print("Could NOT parse HTML due to error: \(error). HTML: \(htmlStr)")
            }
            return nil
        }
        
        guard let html = htmlOpt else {
            if logEnabled {
                print("Could NOT parse HTML from string: \(htmlStr)")
            }
            return nil
        }
        
        guard let head = html.head() else {
            if logEnabled {
                print("Could NOT parse HTML head from string: \(htmlStr)")
            }
            return nil
        }

        // Where we're going to store our HTML favicons
        var possibleIcons = [HTMLFaviconReference]()

        var allLinks = Elements()
        do {
            allLinks = try head.select("link")
        }
        catch let error {
            if logEnabled {
                print("Could NOT parse HTML due to error: \(error). HTML: \(htmlStr)")
            }
            return nil
        }
        
        //Iterate over every 'link' tag that's in the head document, and collect them
        for element in allLinks {
            do {
                let rel = try element.attr("rel")
                let href = try element.attr("href")
                
                //If this is an icon that we deem might be a favicon, add it to our array
                if FaviconType.contains(relTypes: self.acceptableIconTypes, rawRelType: rel) {
                    let possibleIcon = HTMLFaviconReference(rel: rel, href: href)
                    possibleIcons.append(possibleIcon)
                }
            }
            catch let error {
                if logEnabled {
                    print("Could NOT parse HTML due to error: \(error). HTML: \(htmlStr)")
                }
                continue
            }
        }

        //Extract the most preferrable icon, and return it's href as a URL object
        guard let mostPreferrableIcon = self.mostPreferrableIcon(icons: possibleIcons) else {
            return nil
        }

        let href = mostPreferrableIcon.icon.href
        
        //If we don't have a http or https prepended to our href, prepend our base domain
        if !Regex.testForHttpsOrHttp(input: href) {
            let baseRef = { () -> URL in
                if let baseRef = try? html.head()?.getElementsByTag("base").attr("href"),
                   let baseRefUrl = URL(string: baseRef, relativeTo: self.url) {
                    return baseRefUrl
                } else {
                    return self.url
                }
            }

            guard let url = URL(string: href, relativeTo: baseRef()) else {
                return nil
            }

            let faviconURL = FaviconURL(url: url, type: mostPreferrableIcon.type)
            return faviconURL
        }
        
        guard let url = URL(string: href) else {
            return nil
        }
        
        let faviconURL = FaviconURL(url: url, type: mostPreferrableIcon.type)
        return faviconURL
    }
    
    /**
     Returns the most desirable FaviconRelType from an array of FaviconRelType
     - parameter icons: Our array of our image links that we have to choose a desirable one from
     - returns: The most preferred image link from our aray of icons
     */
    func mostPreferrableIcon(icons: [HTMLFaviconReference]) -> (icon: HTMLFaviconReference, type: FaviconType)? {
        if let icon = icons.first(where: { FaviconType(rawValue: $0.rel) == .appleTouchIcon }) {
            return (icon: icon, type: FaviconType(rawValue: icon.rel)!)
        }
        else if let icon = icons.first(where: { FaviconType(rawValue: $0.rel) == .appleTouchIconPrecomposed }) {
            return (icon: icon, type: FaviconType(rawValue: icon.rel)!)
        }
        else if let icon = icons.first(where: { FaviconType(rawValue: $0.rel) == .shortcutIcon }) {
            return (icon: icon, type: FaviconType(rawValue: icon.rel)!)
        }
        else if let icon = icons.first(where: { FaviconType(rawValue: $0.rel) == .icon }) {
            return (icon: icon, type: FaviconType(rawValue: icon.rel)!)
        }

        return nil
    }

}

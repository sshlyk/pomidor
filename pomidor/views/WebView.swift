import UIKit
import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    
    let query: String
    let webView: WKWebView
    
    init(query: String) {
        self.query = query
        let webConfiguration = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.allowsBackForwardNavigationGestures = true
    }

    func makeUIView(context: Context) -> WKWebView {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
        if let myURL = URL(string: AppConfig.UI.kMovieSearchBaseURL.appending(encodedQuery)) {
            webView.load(URLRequest(url: myURL))
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        
    }
}

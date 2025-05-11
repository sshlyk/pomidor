import UIKit
import SwiftUI
import WebKit

struct WebViewContainer: UIViewRepresentable {
    
    let url: String
    let webView: WebView


    func makeUIView(context: Context) -> WKWebView {
        webView.loadView()
        
        if let myURL = URL(string: AppConfig.UI.kMovieSearchBaseURL.appending(url)) {
            webView.webView.load(URLRequest(url: myURL))
        }
        
        return webView.webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        
    }
}

class WebView: UIViewController, WKUIDelegate {
    
    var webView: WKWebView!
    
    override func loadView() {
        let webConfiguration = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.uiDelegate = self
        view = webView
    }
}

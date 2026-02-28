//
//  WebViewController.swift
//  Worthify Share Extension
//
//  Web view for displaying product pages inside the share modal
//

import UIKit
import WebKit

class WebViewController: UIViewController, WKNavigationDelegate {

    private var webView: WKWebView!
    private var progressView: UIProgressView!
    private var url: URL
    private weak var shareViewController: RSIShareViewController?

    // Browser UI elements
    private var toolbarContainer: UIView!
    private var urlBar: UIView!
    private var urlLabel: UILabel!
    private var lockIcon: UIImageView!
    private var doneButton: UIButton!

    init(url: URL, shareViewController: RSIShareViewController) {
        self.url = url
        self.shareViewController = shareViewController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .darkContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        // Ensure status bar uses dark content (black icons on white bg)
        setNeedsStatusBarAppearanceUpdate()

        setupToolbar()
        setupWebView()

        // Load the URL with caching enabled
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        webView.load(request)

        NSLog("[ShareExtension] WebViewController loading URL: \(url.absoluteString)")
    }

    private func setupToolbar() {
        // Container for toolbar - extends behind status bar
        toolbarContainer = UIView()
        toolbarContainer.backgroundColor = .systemBackground
        toolbarContainer.translatesAutoresizingMaskIntoConstraints = false

        // URL bar background
        urlBar = UIView()
        urlBar.backgroundColor = UIColor.systemGray6
        urlBar.layer.cornerRadius = 10
        urlBar.translatesAutoresizingMaskIntoConstraints = false

        // Lock icon for HTTPS
        lockIcon = UIImageView()
        lockIcon.image = UIImage(systemName: "lock.fill")
        lockIcon.tintColor = .secondaryLabel
        lockIcon.contentMode = .scaleAspectFit
        lockIcon.translatesAutoresizingMaskIntoConstraints = false

        // URL label
        urlLabel = UILabel()
        urlLabel.font = .systemFont(ofSize: 14)
        urlLabel.textColor = .secondaryLabel
        urlLabel.textAlignment = .center
        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        urlLabel.text = url.host ?? url.absoluteString

        // Done button
        doneButton = UIButton(type: .system)
        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        doneButton.tintColor = .systemBlue
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneButton.translatesAutoresizingMaskIntoConstraints = false

        // Add to toolbar
        urlBar.addSubview(lockIcon)
        urlBar.addSubview(urlLabel)

        toolbarContainer.addSubview(doneButton)
        toolbarContainer.addSubview(urlBar)

        view.addSubview(toolbarContainer)

        // Separator line
        let separator = UIView()
        separator.backgroundColor = .systemGray5
        separator.translatesAutoresizingMaskIntoConstraints = false
        toolbarContainer.addSubview(separator)

        NSLayoutConstraint.activate([
            // Toolbar container - extends all the way to top edge (behind status bar)
            toolbarContainer.topAnchor.constraint(equalTo: view.topAnchor),
            toolbarContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbarContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbarContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 56),

            // URL bar - left-aligned, takes 75% width, below safe area with more padding
            urlBar.leadingAnchor.constraint(equalTo: toolbarContainer.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            urlBar.topAnchor.constraint(equalTo: toolbarContainer.safeAreaLayoutGuide.topAnchor, constant: 12),
            urlBar.heightAnchor.constraint(equalToConstant: 36),
            urlBar.widthAnchor.constraint(equalTo: toolbarContainer.widthAnchor, multiplier: 0.75),

            // Done button - right side, aligned with URL bar
            doneButton.trailingAnchor.constraint(equalTo: toolbarContainer.safeAreaLayoutGuide.trailingAnchor, constant: -26),
            doneButton.centerYAnchor.constraint(equalTo: urlBar.centerYAnchor),

            // Lock icon
            lockIcon.leadingAnchor.constraint(equalTo: urlBar.leadingAnchor, constant: 10),
            lockIcon.centerYAnchor.constraint(equalTo: urlBar.centerYAnchor),
            lockIcon.widthAnchor.constraint(equalToConstant: 14),
            lockIcon.heightAnchor.constraint(equalToConstant: 14),

            // URL label - centered in URL bar
            urlLabel.leadingAnchor.constraint(equalTo: lockIcon.trailingAnchor, constant: 6),
            urlLabel.trailingAnchor.constraint(equalTo: urlBar.trailingAnchor, constant: -10),
            urlLabel.centerYAnchor.constraint(equalTo: urlBar.centerYAnchor),

            // Separator
            separator.leadingAnchor.constraint(equalTo: toolbarContainer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: toolbarContainer.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: toolbarContainer.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }

    private func setupWebView() {
        // Progress bar for loading indicator (underneath toolbar)
        progressView = UIProgressView(progressViewStyle: .default)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progressTintColor = UIColor(red: 242/255, green: 0, blue: 60/255, alpha: 1.0)
        progressView.trackTintColor = .systemGray6
        progressView.isHidden = true

        // Configure web view for optimal performance
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.allowsInlineMediaPlayback = true
        webConfiguration.mediaTypesRequiringUserActionForPlayback = []

        // Performance optimizations
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        webConfiguration.defaultWebpagePreferences = preferences

        // Enable data detector types for better UX
        webConfiguration.dataDetectorTypes = [.link, .phoneNumber]

        // Use shared process pool for faster subsequent loads
        webConfiguration.processPool = WKProcessPool()

        webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.allowsBackForwardNavigationGestures = true

        // Additional performance settings
        webView.allowsLinkPreview = true

        view.addSubview(progressView)
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            // Progress bar directly under toolbar
            progressView.topAnchor.constraint(equalTo: toolbarContainer.bottomAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2),

            // Web view below progress bar
            webView.topAnchor.constraint(equalTo: progressView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Observe loading progress and URL
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.url), options: .new, context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "estimatedProgress" {
            let progress = Float(webView.estimatedProgress)
            progressView.setProgress(progress, animated: true)

            if progress >= 1.0 {
                // Fade out progress bar when loading completes
                UIView.animate(withDuration: 0.3, delay: 0.3, options: .curveEaseOut, animations: {
                    self.progressView.alpha = 0
                }, completion: { _ in
                    self.progressView.isHidden = true
                    self.progressView.alpha = 1
                })
            } else {
                progressView.isHidden = false
                progressView.alpha = 1
            }
        } else if keyPath == "url" {
            if let url = webView.url {
                urlLabel.text = url.host ?? url.absoluteString
                lockIcon.isHidden = url.scheme != "https"
            }
        }
    }

    // MARK: - Actions

    @objc private func doneTapped() {
        NSLog("[ShareExtension] Done button tapped in WebViewController - dismissing web view")

        // Dismiss the modal web view and return to results
        dismiss(animated: true) {
            NSLog("[ShareExtension] WebViewController dismissed - back to results")
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        progressView.setProgress(0, animated: false)
        progressView.isHidden = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        NSLog("[ShareExtension] WebView finished loading: \(webView.url?.absoluteString ?? "unknown")")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("[ShareExtension] WebView failed to load: \(error.localizedDescription)")
        showError(message: "Failed to load page")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("[ShareExtension] WebView failed provisional navigation: \(error.localizedDescription)")
        showError(message: "Failed to load page")
    }

    private func showError(message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    deinit {
        webView?.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
        webView?.removeObserver(self, forKeyPath: #keyPath(WKWebView.url))
    }
}

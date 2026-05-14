//
//  ImageCache.swift
//  Ethica
//
//  Image caching for faster AsyncImage loading
//

import SwiftUI

class ImageCache {
	static let shared = ImageCache()

	private let cache = NSCache<NSString, UIImage>()

	private init() {
		cache.countLimit = 100 // Cache up to 100 images
		cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
	}

	func get(url: String) -> UIImage? {
		return cache.object(forKey: url as NSString)
	}

	func set(url: String, image: UIImage) {
		cache.setObject(image, forKey: url as NSString)
	}
}

struct CachedAsyncImage<Content: View>: View {
	let url: URL?
	let content: (AsyncImagePhase) -> Content

	@State private var cachedImage: UIImage?

	init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
		self.url = url
		self.content = content
	}

	var body: some View {
		Group {
			if let cachedImage = cachedImage {
				content(.success(Image(uiImage: cachedImage)))
			} else if let url = url {
				AsyncImage(url: url) { phase in
					content(phase)
						.onAppear {
							if case .success(let image) = phase {
								// Cache the image
								Task {
									if let uiImage = await renderImage(image) {
										ImageCache.shared.set(url: url.absoluteString, image: uiImage)
									}
								}
							}
						}
				}
			} else {
				content(.empty)
			}
		}
		.onAppear {
			if let url = url, let cached = ImageCache.shared.get(url: url.absoluteString) {
				cachedImage = cached
			}
		}
	}

	private func renderImage(_ image: Image) async -> UIImage? {
		if #available(iOS 16.0, *) {
			let renderer = ImageRenderer(content: image)
			return renderer.uiImage
		} else {
			return nil
		}
	}
}

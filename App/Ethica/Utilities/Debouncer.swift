//
//  Debouncer.swift
//  Ethica
//
//  Debounce utility to prevent excessive updates
//

import Foundation
import Combine

class Debouncer: ObservableObject {
	private var cancellable: AnyCancellable?

	func debounce(delay: TimeInterval = 0.3, action: @escaping () -> Void) {
		cancellable?.cancel()

		cancellable = Just(())
			.delay(for: .seconds(delay), scheduler: RunLoop.main)
			.sink { _ in
				action()
			}
	}

	func cancel() {
		cancellable?.cancel()
	}
}

//
//  AuthConfig.swift
//  Ethica
//
//  OAuth redirect and provider constants for Supabase auth.
//

import Foundation

enum AuthConfig {
    /// URL scheme used for Supabase OAuth callbacks (Google web flow).
    /// Must match Info.plist CFBundleURLSchemes and Supabase Dashboard redirect URLs.
    static let oauthCallbackScheme = "ethica"

    static var oauthRedirectURL: URL {
        URL(string: "\(oauthCallbackScheme)://auth-callback")!
    }
}

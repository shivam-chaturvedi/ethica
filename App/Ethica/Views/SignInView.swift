//
//  SignInView.swift
//  Ethica
//
//  Modern Authentication View with Google Sign-In
//

import SwiftUI

struct SignInView: View {
    @ObservedObject private var authService = AuthenticationService.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showForgotPassword = false
    @State private var forgotPasswordEmail = ""
    @State private var showResetSent = false
    @State private var resetSentMessage = ""

    // Animation states
    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0
    @State private var formOffset: CGFloat = 50
    @State private var formOpacity: Double = 0
    @State private var particlePhase: CGFloat = 0

    var body: some View {
        ZStack {
            // Animated background
            animatedBackground
                .accessibilityHidden(true)

            // Floating particles (decorative only)
            floatingParticles
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // Main content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: 80)

                    // Logo section
                    logoSection
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)

                    Spacer()
                        .frame(height: 40)

                    // Form section
                    formSection
                        .offset(y: formOffset)
                        .opacity(formOpacity)

                    Spacer()
                        .frame(height: 24)

                    // Bottom links
                    bottomLinks
                        .opacity(formOpacity)

                    Spacer()
                        .frame(height: 60)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(AnimationSystem.springBouncy.delay(0.1)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }

            withAnimation(AnimationSystem.springSmooth.delay(0.3)) {
                formOffset = 0
                formOpacity = 1.0
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Reset Password", isPresented: $showForgotPassword) {
            TextField("Email", text: $forgotPasswordEmail)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
            Button("Cancel", role: .cancel) { }
            Button("Send Reset Link") {
                handlePasswordReset()
            }
        } message: {
            Text("Enter your email to receive a password reset link.")
        }
        .alert("Reset Email Sent", isPresented: $showResetSent) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(resetSentMessage)
        }
    }

    // MARK: - Background

    private var animatedBackground: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.15, blue: 0.2),
                    Color(red: 0.15, green: 0.3, blue: 0.35),
                    Color(red: 0.1, green: 0.2, blue: 0.25)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle animated overlay gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Theme.primary.opacity(0.3),
                    Theme.accent.opacity(0.2),
                    Theme.success.opacity(0.15)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(0.6 + 0.4 * sin(Double(particlePhase) * Double.pi / 180.0))
            .onAppear {
                withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                    particlePhase = 360
                }
            }
        }
    }

    private var floatingParticles: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<5, id: \.self) { index in
                    let size = CGFloat(60 + (index * 20) % 80)
                    let xFrac = CGFloat((index * 37 + 13) % 100) / 100.0
                    let yFrac = CGFloat((index * 53 + 7) % 100) / 100.0
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Theme.primary.opacity(0.06),
                                    Theme.accent.opacity(0.02),
                                    Color.clear
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: size / 2
                            )
                        )
                        .frame(width: size, height: size)
                        .position(
                            x: xFrac * geometry.size.width,
                            y: yFrac * geometry.size.height
                        )
                }
            }
            .drawingGroup()
        }
    }

    // MARK: - Logo Section

    private var logoSection: some View {
        VStack(spacing: Spacing.md) {
            // Animated logo with glow
            ZStack {
                // Glow effect (rasterized, no blur)
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Theme.success.opacity(0.25),
                                Theme.success.opacity(0.08),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 20,
                            endRadius: 90
                        )
                    )
                    .frame(width: 180, height: 180)

                // Logo icon
                ZStack {
                    Circle()
                        .fill(Theme.success.opacity(0.2))
                        .frame(width: 100, height: 100)

                    Image(systemName: "leaf.fill")
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Theme.success, Theme.accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }

            Text("Ethica")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text("Embracing Ahimsa")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .tracking(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ethica, embracing ahimsa")
    }

    // MARK: - Form Section

    private var formSection: some View {
        VStack(spacing: Spacing.lg) {
            // Glass morphism card
            GlassCard.primary {
                VStack(spacing: Spacing.lg) {
                    // Title
                    Text(isSignUp ? "Create Account" : "Welcome Back")
                        .textStyleH2()
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(isSignUp ? "Sign up to start your ethical journey" : "Sign in to continue")
                        .textStyleBody()
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Email field
                    modernTextField(
                        text: $email,
                        placeholder: "Email",
                        icon: "envelope.fill",
                        keyboardType: .emailAddress
                    )

                    // Password field
                    modernSecureField(
                        text: $password,
                        placeholder: "Password",
                        icon: "lock.fill"
                    )

                    // Action button
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                            .frame(height: 56)
                            .accessibilityLabel(isSignUp ? "Creating account" : "Signing in")
                            .accessibilityAddTraits(.updatesFrequently)
                    } else {
                        PrimaryButton(
                            isSignUp ? "Create Account" : "Sign In",
                            icon: isSignUp ? "person.badge.plus.fill" : "arrow.right.circle.fill",
                            style: .success
                        ) {
                            handleAuthentication()
                        }
                        .accessibilityLabel(isSignUp ? "Create account" : "Sign in")
                        .accessibilityHint(isSignUp ? "Double tap to create your account" : "Double tap to sign in with email and password")
                        .transition(.scale.combined(with: .opacity))
                    }

                    // Forgot Password (only in sign-in mode)
                    if !isSignUp {
                        Button(action: {
                            forgotPasswordEmail = email
                            showForgotPassword = true
                        }) {
                            Text("Forgot Password?")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Theme.success.opacity(0.9))
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityLabel("Forgot password")
                        .accessibilityHint("Double tap to reset your password via email")
                    }

                    // Toggle sign up/in
                    Button(action: {
                        withAnimation(AnimationSystem.springSmooth) {
                            isSignUp.toggle()
                            // Clear fields on toggle
                            email = ""
                            password = ""
                        }
                    }) {
                        HStack(spacing: Spacing.xs) {
                            Text(isSignUp ? "Already have an account?" : "Don\'t have an account?")
                                .textStyleBody()
                                .foregroundColor(.white.opacity(0.7))

                            Text(isSignUp ? "Sign In" : "Sign Up")
                                .textStyleBody()
                                .foregroundColor(Theme.success)
                                .font(.body.weight(.semibold))
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel(isSignUp ? "Already have an account? Sign in" : "Don't have an account? Sign up")
                    .accessibilityHint(isSignUp ? "Double tap to switch to sign in" : "Double tap to switch to sign up")
                }
            }
            .padding(.horizontal, Spacing.screenHorizontal)
        }
    }

    // MARK: - Bottom Links

    private var bottomLinks: some View {
        VStack(spacing: Spacing.md) {
            // Divider with text
            HStack {
                Rectangle()
                    .fill(.white.opacity(0.3))
                    .frame(height: 1)

                Text("or")
                    .textStyleCaption()
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, Spacing.sm)

                Rectangle()
                    .fill(.white.opacity(0.3))
                    .frame(height: 1)
            }
            .padding(.horizontal, Spacing.screenHorizontal + Spacing.lg)
            .accessibilityHidden(true)

            // Google Sign-In button
            if !isLoading {
                Button(action: {
                    handleGoogleSignIn()
                }) {
                    HStack(spacing: Spacing.sm) {
                        // Google "G" logo
                        Image(systemName: "g.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)

                        Text("Continue with Google")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: Spacing.radiusMD)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.26, green: 0.52, blue: 0.96),
                                             Color(red: 0.22, green: 0.46, blue: 0.88)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Spacing.radiusMD)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, Spacing.screenHorizontal)
                .accessibilityLabel("Sign in with Google")
                .accessibilityHint("Double tap to sign in with your Google account")
            }

            // Guest button
            if !isLoading {
                Button(action: {
                    withAnimation(AnimationSystem.springSmooth) {
                        handleAnonymousSignIn()
                    }
                }) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "person.fill.questionmark")
                            .font(.system(size: 16, weight: .semibold))

                        Text("Continue as Guest")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: Spacing.radiusMD)
                            .fill(.white.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: Spacing.radiusMD)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, Spacing.screenHorizontal)
                .accessibilityLabel("Continue as guest")
                .accessibilityHint("Double tap to use the app without an account")
            }
        }
    }

    // MARK: - Custom Text Fields

    @ViewBuilder
    private func modernTextField(
        text: Binding<String>,
        placeholder: String,
        icon: String,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.success.opacity(0.7))
                .frame(width: 24)
                .accessibilityHidden(true)

            TextField(placeholder, text: text)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .autocapitalization(.none)
                .keyboardType(keyboardType)
                .tint(Theme.success)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.radiusMD)
                .fill(.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radiusMD)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func modernSecureField(
        text: Binding<String>,
        placeholder: String,
        icon: String
    ) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.success.opacity(0.7))
                .frame(width: 24)
                .accessibilityHidden(true)

            SecureField(placeholder, text: text)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .tint(Theme.success)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.radiusMD)
                .fill(.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radiusMD)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Actions

    private func handleAuthentication() {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter both email and password"
            showError = true
            return
        }

        withAnimation(AnimationSystem.springSmooth) {
            isLoading = true
        }

        Task {
            do {
                if isSignUp {
                    try await authService.signUpWithEmail(email: email, password: password)
                } else {
                    try await authService.signInWithEmail(email: email, password: password)
                }
            } catch {
                await MainActor.run {
                    withAnimation(AnimationSystem.springSmooth) {
                        errorMessage = error.localizedDescription
                        showError = true
                        isLoading = false
                    }
                }
            }
        }
    }

    private func handleGoogleSignIn() {
        withAnimation(AnimationSystem.springSmooth) {
            isLoading = true
        }

        Task {
            do {
                try await authService.signInWithGoogle()
            } catch {
                await MainActor.run {
                    withAnimation(AnimationSystem.springSmooth) {
                        // Don\'t show error if user simply cancelled
                        let nsError = error as NSError
                        if nsError.code != -5 { // GIDSignInError.canceled
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                        isLoading = false
                    }
                }
            }
        }
    }

    private func handlePasswordReset() {
        let trimmedEmail = forgotPasswordEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            errorMessage = "Please enter your email address"
            showError = true
            return
        }
        Task {
            do {
                try await authService.resetPassword(email: trimmedEmail)
                await MainActor.run {
                    resetSentMessage = "If an account exists for \(trimmedEmail), a password reset link has been sent."
                    showResetSent = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Unable to send reset email. Please check your email and try again."
                    showError = true
                }
            }
        }
    }

    private func handleAnonymousSignIn() {
        isLoading = true

        Task {
            do {
                try await authService.signInAnonymously()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(AnimationSystem.springSmooth, value: configuration.isPressed)
    }
}

struct SignInView_Previews: PreviewProvider {
    static var previews: some View {
        SignInView()
            .preferredColorScheme(.dark)
    }
}

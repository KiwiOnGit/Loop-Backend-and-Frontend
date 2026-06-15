@preconcurrency import AVFoundation
import CoreTransferable
import PhotosUI
import SwiftUI
import UIKit
import Speech
#if canImport(FoundationModels)
import FoundationModels
#endif

struct CreateLoopView: View {
    @EnvironmentObject private var session: SessionStore
    @Binding var draftCaption: String
    let onUploaded: () -> Void

    @StateObject private var camera = LoopCameraController()
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedVideoURL: URL?
    @State private var durationSeconds: Double?
    @State private var caption = ""
    @State private var selectedFilter: LoopCameraFilter = .clean
    @State private var isProcessing = false
    @State private var isUploading = false
    @State private var ideasSupported = false
    @State private var errorMessage: String?

    // Advanced Creator Features
    @State private var selectedSoundName: String? = nil
    @State private var countdownTime = 0
    @State private var selectedCountdownSetting = 0 // 0 = Off, 3 = 3s, 5 = 5s, 10 = 10s
    @State private var showingSoundSelector = false
    
    // Stages: .recording, .replaying, .metadata
    enum CreateStage {
        case recording
        case replaying
        case metadata
    }
    @State private var stage: CreateStage = .recording
    @State private var isAIGenerating = false
    @State private var maxDuration = 6.0

    init(draftCaption: Binding<String> = .constant(""), onUploaded: @escaping () -> Void) {
        self._draftCaption = draftCaption
        self.onUploaded = onUploaded
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                switch stage {
                case .recording:
                    recordingView(proxy: proxy)
                case .replaying:
                    if let url = selectedVideoURL {
                        replayingView(url: url, proxy: proxy)
                    } else {
                        Color.black
                            .onAppear { stage = .recording }
                    }
                case .metadata:
                    metadataView(proxy: proxy)
                }
            }
        }
        .task {
            await camera.prepare()
            ideasSupported = LoopIdeaProvider.isAvailable
            applyDraftCaption()
        }
        .onChange(of: camera.recordedURL) { _, newURL in
            guard let newURL else { return }
            Task { await acceptVideo(newURL) }
        }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task { await importPhotoPickerItem(newItem) }
        }
        .onChange(of: draftCaption) {
            applyDraftCaption()
        }
        .sheet(isPresented: $showingSoundSelector) {
            SoundSelectorSheet { sound in
                selectedSoundName = sound
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func triggerRecording() {
        if camera.isRecording {
            camera.pauseRecording()
        } else if camera.isPaused {
            camera.resumeRecording(maxDuration: maxDuration)
        } else {
            let delay = selectedCountdownSetting
            if delay > 0 {
                countdownTime = delay
                Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                    DispatchQueue.main.async {
                        if self.countdownTime > 1 {
                            self.countdownTime -= 1
                        } else {
                            self.countdownTime = 0
                            timer.invalidate()
                            self.camera.startRecording(maxDuration: self.maxDuration)
                        }
                    }
                }
            } else {
                camera.startRecording(maxDuration: maxDuration)
            }
        }
    }

    // stage 1: Full screen recording surface
    private func recordingView(proxy: GeometryProxy) -> some View {
        ZStack {
            LoopCameraPreview(session: camera.session)
                .ignoresSafeArea()

            selectedFilter.overlayColor
                .blendMode(selectedFilter.blendMode)
                .allowsHitTesting(false)
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Flash & Countdown selector
            HStack {
                Spacer()
                VStack(spacing: 16) {
                    // Timer Selector
                    Button {
                        if selectedCountdownSetting == 0 {
                            selectedCountdownSetting = 3
                        } else if selectedCountdownSetting == 3 {
                            selectedCountdownSetting = 5
                        } else if selectedCountdownSetting == 5 {
                            selectedCountdownSetting = 10
                        } else {
                            selectedCountdownSetting = 0
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "timer")
                            if selectedCountdownSetting > 0 {
                                // Corrected string interpolation for Int countdown setting
                                Text("\(selectedCountdownSetting)s")
                                    .font(.system(size: 8, weight: .black))
                            }
                        }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(selectedCountdownSetting > 0 ? Color.loopGreen : .white)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.16), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 16)
                .padding(.top, 120)
            }

            // Countdown Overlay
            if countdownTime > 0 {
                Text("\(countdownTime)")
                    .font(.system(size: 92, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
                    .shadow(color: .black.opacity(0.48), radius: 10)
            }

            VStack(spacing: 0) {
                // Top Header info
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Create")
                            .font(LoopFont.logo(32))
                            .foregroundStyle(Color.loopGreen)
                        Text(camera.isPaused ? "Tap resume or checkmark." : (maxDuration == 6.0 ? "Hold it to six." : "Limit to 60s."))
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(camera.isPaused ? Color.loopGreen : .white.opacity(0.68))
                    }

                    Spacer()

                    // Add Sound Button (TikTok Style)
                    Button {
                        showingSoundSelector = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "music.note")
                            Text(selectedSoundName ?? "Add sound")
                                .font(.system(size: 11, weight: .black))
                                .lineLimit(1)
                                .frame(maxWidth: 120)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.46), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("\(camera.elapsed.oneDecimal)s")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(camera.elapsed > (maxDuration - 0.8) ? .loopWarm : .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.46), in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.top, 58)

                Spacer()

                // Bottom controls and filter selector
                VStack(spacing: 16) {
                    // Filter Selector Row (horizontal scroll)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(LoopCameraFilter.allCases) { filter in
                                Button {
                                    selectedFilter = filter
                                } label: {
                                    Text(filter.title)
                                        .font(.system(size: 11, weight: .black))
                                        .foregroundStyle(selectedFilter == filter ? .white : .white.opacity(0.7))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(selectedFilter == filter ? Color.loopGreen : .black.opacity(0.4), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    ProgressView(value: min(camera.elapsed / maxDuration, 1))
                        .tint(camera.elapsed > (maxDuration - 0.8) ? .loopWarm : Color.loopGreen)
                        .scaleEffect(y: 1.7)
                        .padding(.horizontal, 16)

                    // Target duration selector when idle
                    if !camera.isRecording && !camera.isPaused && camera.elapsed == 0 {
                        HStack(spacing: 16) {
                            Button {
                                maxDuration = 6.0
                            } label: {
                                Text("6s Limit")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(maxDuration == 6.0 ? Color.loopGreen : Color.white.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                maxDuration = 60.0
                            } label: {
                                Text("60s Limit")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(maxDuration == 60.0 ? Color.loopGreen : Color.white.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    }

                    HStack(spacing: 10) {
                        // Left button: Photos Picker OR Discard/Retake
                        if camera.isPaused {
                            Button {
                                camera.reset()
                            } label: {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 19, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .background(Color.loopWarm.opacity(0.72), in: Circle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            PhotosPicker(selection: $selectedItem, matching: .videos) {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 19, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .background(.white.opacity(0.12), in: Circle())
                            }
                            .disabled(camera.isRecording)
                            .opacity(camera.isRecording ? 0 : 1)
                        }

                        Spacer()

                        // Center button: Record / Pause / Resume
                        Button {
                            triggerRecording()
                        } label: {
                            ZStack {
                                Circle()
                                    .stroke(.white.opacity(0.72), lineWidth: 4)
                                    .frame(width: 78, height: 78)

                                if camera.isRecording {
                                    Image(systemName: "pause.fill")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 58, height: 58)
                                        .background(Color.loopWarm, in: Circle())
                                } else if camera.isPaused {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 58, height: 58)
                                        .background(Color.loopGreen, in: Circle())
                                } else {
                                    Circle()
                                        .fill(Color.loopGreen)
                                        .frame(width: 58, height: 58)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!camera.isReady || countdownTime > 0)

                        Spacer()

                        // Right button: Done (Checkmark) OR Flip
                        if camera.isPaused {
                            Button {
                                camera.finishRecording()
                            } label: {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 19, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .background(Color.loopGreen, in: Circle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                camera.flip()
                            } label: {
                                Image(systemName: "camera.rotate.fill")
                                    .font(.system(size: 19, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .background(.white.opacity(0.12), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(camera.isRecording)
                            .opacity(camera.isRecording ? 0 : 1)
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 34)
                }
            }

            if !camera.isReady {
                VStack(spacing: 10) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 38, weight: .bold))
                    Text(camera.permissionDenied ? "Camera access needed" : "Preparing camera")
                        .font(.headline.weight(.black))
                }
                .foregroundStyle(.white)
                .padding(18)
                .background(.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    // stage 2: Full screen video playback preview with "Next" button
    private func replayingView(url: URL, proxy: GeometryProxy) -> some View {
        ZStack {
            LoopPlayerView(url: url, isActive: stage == .replaying)
                .ignoresSafeArea()
            
            selectedFilter.overlayColor
                .blendMode(selectedFilter.blendMode)
                .allowsHitTesting(false)
                .ignoresSafeArea()
            
            LinearGradient(
                colors: [.black.opacity(0.35), .clear, .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Top on-device AI transcription loading state
            VStack {
                HStack {
                    Spacer()
                    if isAIGenerating {
                        HStack(spacing: 6) {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                            Text("Apple Intelligence transcribing...")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.55), in: Capsule())
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.loopGreen)
                            Text("Transcript analyzed by On-Device AI")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.55), in: Capsule())
                    }
                    Spacer()
                }
                .padding(.top, 58)
                
                Spacer()
                
                // Bottom control overlay (Back / Next)
                HStack {
                    // Back/Discard Button
                    Button {
                        selectedVideoURL = nil
                        durationSeconds = nil
                        camera.recordedURL = nil
                        caption = ""
                        stage = .recording
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Retake")
                        }
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.18), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // Next Button
                    Button {
                        stage = .metadata
                    } label: {
                        HStack {
                            Text("Next")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(Color.loopGreen, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    // stage 3: Description screen with auto-generated metadata
    private func metadataView(proxy: GeometryProxy) -> some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header custom navigation bar
                HStack {
                    Button {
                        stage = .replaying
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(Color.loopGreen)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Text("Description")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(Color.loopInk)
                    
                    Spacer()
                    
                    // Invisible spacer for centering
                    Text("Back")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(.clear)
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, 16)
                .padding(.top, 56)
                .padding(.bottom, 14)
                
                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Small preview thumbnail container
                        if let url = selectedVideoURL {
                            HStack(spacing: 12) {
                                ZStack {
                                    LoopPlayerView(url: url, isActive: stage == .metadata)
                                        .frame(width: 80, height: 110)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    
                                    selectedFilter.overlayColor
                                        .blendMode(selectedFilter.blendMode)
                                        .allowsHitTesting(false)
                                        .frame(width: 80, height: 110)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Video Preview")
                                        .font(.system(size: 12, weight: .black))
                                        .foregroundStyle(Color.loopSubtext)
                                    Text(selectedSoundName ?? "Original Audio")
                                        .font(.system(size: 13, weight: .black))
                                        .foregroundStyle(Color.loopGreen)
                                    if let duration = durationSeconds {
                                        Text("\(duration.oneDecimal) seconds duration")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Color.loopSubtext)
                                    }
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.loopMist, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        
                        // Caption section
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Caption")
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundStyle(Color.loopInk)
                                Spacer()
                                if isAIGenerating {
                                    HStack(spacing: 4) {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                        Text("AI writing...")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(Color.loopSubtext)
                                    }
                                } else {
                                    Label("AI Suggestions Ready", systemImage: "sparkles")
                                        .font(.system(size: 11, weight: .black))
                                        .foregroundStyle(Color.loopGreen)
                                }
                            }
                            
                            TextField("Enter caption...", text: $caption, axis: .vertical)
                                .lineLimit(4...8)
                                .font(.system(size: 14, weight: .bold))
                                .padding(12)
                                .background(Color.loopMist)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.loopLine, lineWidth: 1)
                                }
                        }
                        
                        // Help label
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.loopGreen)
                                .padding(.top, 2)
                            Text("On-device AI read your video transcript and generated a custom title, hashtags, and description referencing your creator profile.")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.loopSubtext)
                                .lineSpacing(3)
                        }
                        .padding(.top, 4)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Post Category")
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(Color.loopInk)

                            HStack(spacing: 8) {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundStyle(Color.loopGreen)
                                Text("Automatic: \(categoryTitle(for: durationSeconds))")
                                    .font(.system(size: 13, weight: .black, design: .rounded))
                                    .foregroundStyle(Color.loopInk)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .background(Color.loopMist, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .padding(.top, 8)
                        
                        Spacer(minLength: 30)
                        
                        // Post button
                        PrimaryLoopButton(
                            title: "Post to Loop",
                            systemImage: "paperplane.fill",
                            isLoading: isUploading
                        ) {
                            Task { await upload() }
                        }
                        .disabled(caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isUploading)
                    }
                    .padding(16)
                }
            }
        }
    }

    private func importPhotoPickerItem(_ item: PhotosPickerItem) async {
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }
        do {
            guard let picked = try await item.loadTransferable(type: PickedVideo.self) else {
                errorMessage = "That video could not be loaded."
                return
            }
            await acceptVideo(picked.url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func acceptVideo(_ url: URL) async {
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }
        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            guard seconds.isFinite else {
                errorMessage = "Could not read the video duration."
                return
            }
            guard seconds <= maxDuration + 0.25 else {
                selectedVideoURL = nil
                durationSeconds = nil
                errorMessage = "Loops must be \(Int(maxDuration)) seconds or less."
                return
            }
            selectedVideoURL = url
            durationSeconds = min(seconds, maxDuration)
            stage = .replaying
            
            // Trigger background on-device AI generation
            Task {
                await runAIAutoDescription()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func transcribeVideo(url: URL) async -> String {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else {
            return ""
        }
        
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard authStatus == .authorized else {
            return ""
        }
        
        return await withCheckedContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false
            var finished = false
            
            recognizer.recognitionTask(with: request) { result, error in
                if finished { return }
                
                if let result {
                    if result.isFinal {
                        finished = true
                        continuation.resume(returning: result.bestTranscription.formattedString)
                    }
                } else if error != nil {
                    finished = true
                    continuation.resume(returning: "")
                }
            }
            
            // Safety timeout: resume with empty string after 4.0 seconds if speech recognition is hanging
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                if !finished {
                    finished = true
                    continuation.resume(returning: "")
                }
            }
        }
    }

    private func runAIAutoDescription() async {
        guard let url = selectedVideoURL else { return }
        let accountName = session.currentUser?.displayName ?? session.currentUser?.username ?? "Creator"
        isAIGenerating = true
        
        // 1. Transcribe the actual audio of the recorded/imported video
        let transcript = await transcribeVideo(url: url)
        
        let soundName = selectedSoundName ?? "Original Audio"
        let filterName = selectedFilter.title
        
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), LoopIdeaProvider.isAvailable {
            do {
                let session = LanguageModelSession(
                    instructions: "You are an on-device AI assistant. Generate a short social video caption. Return only the final user-facing text with no labels, no Markdown, and no quoted field names."
                )
                let response = try await session.respond(
                    to: """
                    The video has the transcript: "\(transcript)".
                    The video has \(soundName) audio and uses the \(filterName) filter.
                    Write exactly three blocks separated by blank lines: a catchy title, a short one-sentence description referencing \(accountName)'s page, and 3 hashtags.
                    """
                )
                DispatchQueue.main.async {
                    self.caption = LoopCaptionFormatter.display(response.content)
                    self.isAIGenerating = false
                }
                return
            } catch {
                // Fallback to local template generator on error
            }
        }
        #endif
        
        // 2. Fallback generative parser to build description and hashtags dynamically from transcript words
        let cleanTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalAIOutput: String
        
        if cleanTranscript.isEmpty {
            // Generative synthesis for visual content
            let soundAction = soundName == "Original Audio" ? "original audio track" : "the beats of \(soundName)"
            finalAIOutput = """
            Aesthetic Visuals ✨
            
            Observing a quiet, visual capture under the \(filterName) filter, synchronized with \(soundAction). Follow \(accountName) for more unique, frame-by-frame loop moments!
            
            #visuals #\(filterName.lowercased()) #loop
            """
        } else {
            // Split transcript into words and clean them
            let words = cleanTranscript.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 3 }
            let uniqueWords = Array(Set(words))
            
            let titleWord = uniqueWords.first?.capitalized ?? "Moment"
            let generatedTitle = "\(titleWord) Session 🎬"
            
            // Construct description dynamically from transcript words
            var descriptionSentence = "In this loop, \(accountName) shares a moment about "
            if uniqueWords.count >= 2 {
                let topics = uniqueWords.prefix(3).map { $0.lowercased() }.joined(separator: ", ")
                descriptionSentence += "\(topics), reflecting on "
            }
            descriptionSentence += "\"\(cleanTranscript)\"."
            
            // Generate hashtags dynamically from transcript words
            let dynamicTags = uniqueWords.prefix(3).map { "#\($0.lowercased())" }.joined(separator: " ")
            let finalTags = dynamicTags.isEmpty ? "#loop #creator" : "\(dynamicTags) #loop"
            
            finalAIOutput = """
            \(generatedTitle)
            
            \(descriptionSentence)
            
            \(finalTags)
            """
        }
        
        DispatchQueue.main.async {
            self.caption = LoopCaptionFormatter.display(finalAIOutput)
            self.isAIGenerating = false
        }
    }

    private func upload() async {
        guard let selectedVideoURL, let durationSeconds else {
            errorMessage = "Record or choose a video first."
            return
        }
        guard let token = try? session.requireToken() else {
            errorMessage = "Sign in again to post."
            return
        }
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }
        do {
            let cleanedCaption = LoopCaptionFormatter.display(caption)
            _ = try await session.apiClient.uploadLoop(
                videoURL: selectedVideoURL,
                caption: cleanedCaption,
                durationSeconds: durationSeconds,
                category: categoryValue(for: durationSeconds),
                token: token
            )
            caption = ""
            draftCaption = ""
            self.selectedVideoURL = nil
            self.durationSeconds = nil
            camera.recordedURL = nil
            stage = .recording
            onUploaded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyDraftCaption() {
        let draft = draftCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else {
            return
        }
        if caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            caption = LoopCaptionFormatter.display(draft)
        }
        draftCaption = ""
    }

    private func categoryValue(for duration: Double?) -> String {
        guard let duration else {
            return "6s"
        }
        return duration <= 6.25 ? "6s" : "60s"
    }

    private func categoryTitle(for duration: Double?) -> String {
        categoryValue(for: duration) == "6s" ? "6s Video Category" : "60s Video Category"
    }
}

private struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
            if FileManager.default.fileExists(atPath: copy.path) {
                try FileManager.default.removeItem(at: copy)
            }
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedVideo(url: copy)
        }
    }
}

private enum LoopIdeaProvider {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }
}

enum LoopCameraFilter: String, CaseIterable, Identifiable {
    case clean
    case vine
    case warm
    case mono
    case night
    case forest
    case sepia
    case noir
    case cyberpunk
    case emerald
    case vignette

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clean: "Clean"
        case .vine: "Vine"
        case .warm: "Warm"
        case .mono: "Mono"
        case .night: "Night"
        case .forest: "Forest"
        case .sepia: "Sepia"
        case .noir: "Noir"
        case .cyberpunk: "Cyberpunk"
        case .emerald: "Emerald"
        case .vignette: "Vignette"
        }
    }

    var overlayColor: Color {
        switch self {
        case .clean: .clear
        case .vine: Color.loopGreen.opacity(0.14)
        case .warm: Color.loopWarm.opacity(0.18)
        case .mono: .gray.opacity(0.28)
        case .night: .blue.opacity(0.16)
        case .forest: Color(red: 0.15, green: 0.35, blue: 0.20).opacity(0.16)
        case .sepia: Color(red: 0.50, green: 0.38, blue: 0.25).opacity(0.22)
        case .noir: Color.black.opacity(0.32)
        case .cyberpunk: Color.purple.opacity(0.18)
        case .emerald: Color(red: 0.05, green: 0.55, blue: 0.30).opacity(0.16)
        case .vignette: Color.black.opacity(0.12)
        }
    }

    var blendMode: BlendMode {
        switch self {
        case .clean: .normal
        case .mono: .saturation
        case .noir: .luminosity
        default: .softLight
        }
    }
}

@MainActor
final class LoopCameraController: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    @Published var isReady = false
    @Published var permissionDenied = false
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var elapsed = 0.0
    @Published var recordedURL: URL?

    private let movieOutput = AVCaptureMovieFileOutput()
    private var currentPosition: AVCaptureDevice.Position = .back
    private var timer: Timer?
    
    private var accumulatedDuration = 0.0
    private var segmentURLs: [URL] = []

    func prepare() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else {
            permissionDenied = true
            return
        }
        configureSession(position: currentPosition)
    }

    func startRecording(maxDuration: Double) {
        guard isReady, !movieOutput.isRecording else {
            return
        }
        recordedURL = nil
        elapsed = 0
        accumulatedDuration = 0
        segmentURLs.removeAll()
        isPaused = false
        
        startSegment(maxDuration: maxDuration)
    }
    
    private func startSegment(maxDuration: Double) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
        movieOutput.startRecording(to: url, recordingDelegate: self)
        isRecording = true
        
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] timer in
            guard let self else { return }
            Task { @MainActor in
                self.elapsed = self.accumulatedDuration + self.movieOutput.recordedDuration.seconds
                if self.elapsed >= maxDuration {
                    timer.invalidate()
                    self.finishRecording()
                }
            }
        }
    }
    
    func pauseRecording() {
        guard movieOutput.isRecording, !isPaused else { return }
        timer?.invalidate()
        isPaused = true
        isRecording = false
        accumulatedDuration = elapsed
        movieOutput.stopRecording()
    }
    
    func resumeRecording(maxDuration: Double) {
        guard isReady, !movieOutput.isRecording, isPaused else { return }
        isPaused = false
        startSegment(maxDuration: maxDuration)
    }
    
    func finishRecording() {
        timer?.invalidate()
        isPaused = false
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        } else {
            // If already stopped (e.g. tapped done while paused)
            Task { await mergeAndPublishSegments() }
        }
    }
    
    func reset() {
        timer?.invalidate()
        isRecording = false
        isPaused = false
        elapsed = 0
        accumulatedDuration = 0
        recordedURL = nil
        segmentURLs.removeAll()
    }

    func flip() {
        currentPosition = currentPosition == .back ? .front : .back
        configureSession(position: currentPosition)
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            if error == nil {
                self.segmentURLs.append(outputFileURL)
            } else {
                print("[Loop] Segment recording error: \(String(describing: error))")
            }
            
            // If we are not paused, it means this was the final segment (either reached limit or tapped done)
            if !self.isPaused {
                self.isRecording = false
                self.timer?.invalidate()
                await self.mergeAndPublishSegments()
            }
        }
    }
    
    private func mergeAndPublishSegments() async {
        guard !segmentURLs.isEmpty else { return }
        
        if segmentURLs.count == 1 {
            self.recordedURL = segmentURLs[0]
            return
        }
        
        // Stitch multiple segments
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            self.recordedURL = segmentURLs.first
            return
        }
        
        var currentTime = CMTime.zero
        
        for url in segmentURLs {
            let asset = AVAsset(url: url)
            do {
                let assetVideoTracks = try await asset.loadTracks(withMediaType: .video)
                let assetAudioTracks = try await asset.loadTracks(withMediaType: .audio)
                
                if let firstVideoTrack = assetVideoTracks.first {
                    let duration = try await asset.load(.duration)
                    let timeRange = CMTimeRange(start: .zero, duration: duration)
                    try videoTrack.insertTimeRange(timeRange, of: firstVideoTrack, at: currentTime)
                    
                    // Keep orientation from the first segment
                    if currentTime == .zero {
                        videoTrack.preferredTransform = try await firstVideoTrack.load(.preferredTransform)
                    }
                    
                    if let firstAudioTrack = assetAudioTracks.first {
                        try audioTrack.insertTimeRange(timeRange, of: firstAudioTrack, at: currentTime)
                    }
                    
                    currentTime = CMTimeAdd(currentTime, duration)
                }
            } catch {
                print("[Loop] Error loading tracks for merging: \(error)")
            }
        }
        
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
        
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            self.recordedURL = segmentURLs.first
            return
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = true
        
        await exportSession.export()
        if exportSession.status == .completed {
            self.recordedURL = outputURL
        } else {
            print("[Loop] Segment merge export failed: \(String(describing: exportSession.error))")
            self.recordedURL = segmentURLs.first
        }
    }

    private func configureSession(position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        session.sessionPreset = .high
        session.inputs.forEach { session.removeInput($0) }

        if let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
           let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
           session.canAddInput(videoInput) {
            session.addInput(videoInput)
        }

        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        if !session.outputs.contains(movieOutput), session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        if let connection = movieOutput.connection(with: .video), connection.isVideoMirroringSupported {
            connection.isVideoMirrored = position == .front
        }

        session.commitConfiguration()
        if !session.isRunning {
            let captureSession = session
            DispatchQueue.global(qos: .userInitiated).async {
                captureSession.startRunning()
            }
        }
        isReady = session.inputs.contains { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }
    }
}

struct LoopCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }
}

final class CameraPreviewUIView: UIView {
    override static var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

private struct SoundSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelectSound: (String?) -> Void
    
    let sounds = [
        "Lo-Fi Chill Beats",
        "Upbeat Electronic Pop",
        "Forest Bird Ambient",
        "Retro Synthwave",
        "Acoustic Sunset Guitar",
        "Cyberpunk Bass Beats",
        "Classical Piano Solo"
    ]
    
    var body: some View {
        NavigationStack {
            List {
                Button("None / Original Audio") {
                    onSelectSound(nil)
                    dismiss()
                }
                .foregroundStyle(.red)
                
                ForEach(sounds, id: \.self) { sound in
                    Button {
                        onSelectSound(sound)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "music.note")
                                .foregroundStyle(Color.loopGreen)
                            Text(sound)
                                .font(.body.weight(.semibold))
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.loopGreen)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Sounds")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

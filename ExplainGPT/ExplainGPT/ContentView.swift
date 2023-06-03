//
//  ContentView.swift
//  ExplainGPT
//
//  Created by ChatGPT (GPT-4 Model) in collaboration with Praise Mathew Johnson on 18/03/2023.
//

import SwiftUI
import UIKit
import Vision
import VisionKit
import AVFoundation
import Speech
import Foundation
import UIKit

extension Notification.Name {
    static let speechRecognitionResult = Notification.Name("SpeechRecognitionResult")
}

extension UIApplication {
    func hideKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to:nil, from:nil, for:nil)
    }
}

class SpeechViewModel: ObservableObject {
    @Published var isListening = false
    @Published var recognizedText = ""
    
    var onRecognitionComplete: (() -> Void)?
    
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionResultHandler: ((SFSpeechRecognitionResult?, Error?) -> Void)?
    
    func toggleRecording() {
        if isListening {
            stopRecording()
            // Handle the recognized text after stopping the recording
            NotificationCenter.default.post(name: .speechRecognitionResult, object: recognizedText)
        } else {
            startRecording()
        }
        isListening.toggle()
    }
    
    private func startRecording() {
        recognitionResultHandler = { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                self.recognizedText = result.bestTranscription.formattedString
                print("Recognized text: \(self.recognizedText)")
            } else if let error = error {
                print("Recognition error: \(error)")
            }
        }
        
        // Start recording audio input.
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            let inputNode = audioEngine.inputNode
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                fatalError("Unable to create an SFSpeechAudioBufferRecognitionRequest object")
            }
            recognitionRequest.shouldReportPartialResults = true
            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest, resultHandler: recognitionResultHandler!)
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                recognitionRequest.append(buffer)
            }
            try audioEngine.start()
            print("Audio engine started")
        } catch {
            print("Error starting recording: \(error.localizedDescription)")
        }
    }
    
    private func stopRecording() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionResultHandler = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        print("Recording stopped")
    }
    
    func requestSpeechAuthorization() {
        SFSpeechRecognizer.requestAuthorization { status in
            switch status {
            case .authorized:
                print("Speech recognition authorized")
            case .denied:
                print("Speech recognition denied")
            case .notDetermined:
                print("Speech recognition not determined")
            case .restricted:
                print("Speech recognition restricted")
            @unknown default:
                fatalError("Unknown speech recognition authorization status")
            }
        }
    }
}

class CustomUITextField: UITextField {
    init(placeholder: String) {
        super.init(frame: .zero)
        
        // Set typed text color to white
        textColor = .white
        
        attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [NSAttributedString.Key.foregroundColor: UIColor.lightGray]
        )
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setUpConstraints(fixedWidth: CGFloat) {
        self.translatesAutoresizingMaskIntoConstraints = false
        self.widthAnchor.constraint(equalToConstant: fixedWidth).isActive = true
    }
}

struct SearchBar: View {
    @Binding var text: String
    @Binding var isEditing: Bool
    
    var onCommit: (() -> Void)?
    
    var body: some View {
        HStack {
            CustomTextField(text: $text, placeholder: "Search...", onCommit: {onCommit?()})
                .padding(.vertical, 12)
                .padding(.horizontal, 30)
                .background(Color(red: 25 / 255, green: 25 / 255, blue: 27 / 255))
                .cornerRadius(8)
                .frame(width: UIScreen.main.bounds.width - 32) // Set the fixed width here
                .overlay(
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 8)
                        
                        if isEditing {
                            Button(action: {
                                withAnimation {
                                    self.text = ""
                                    UIApplication.shared.hideKeyboard()
                                }
                            }) {
                                Image(systemName: "multiply.circle.fill")
                                    .foregroundColor(.gray)
                                    .padding(.trailing, 8)
                            }
                        }
                    }
                )
                .padding(.horizontal, 10)
                .onTapGesture {
                    self.isEditing = true
                }
        }
    }
}

struct CustomTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    
    let onCommit: (() -> Void)?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> CustomUITextField {
        let textField = CustomUITextField(placeholder: placeholder)
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textFieldDidChange(_:)), for: .editingChanged)
        
        // Set content hugging priority to fix the height issue
        textField.setContentHuggingPriority(.defaultHigh, for: .vertical)
        
        // Set up fixed width constraint on the textField
        textField.setUpConstraints(fixedWidth: 300) // Pass the desired fixed width here.
        
        return textField
    }
    
    func updateUIView(_ textField: CustomUITextField, context: Context) {
        textField.text = text
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: CustomTextField
        
        init(_ parent: CustomTextField) {
            self.parent = parent
        }
        
        func textFieldDidChangeSelection(_ textField: UITextField) {
            if let text = textField.text {
                parent.text = text
            }
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            parent.onCommit?()
            return true
        }
        
        @objc func textFieldDidChange(_ textField: UITextField) {
            if let text = textField.text {
                parent.text = text
            }
        }
    }
}

struct JustifiedTextView: UIViewRepresentable {
    @Binding var text: String
    var textColor: UIColor
    var maxWidth: CGFloat

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.preferredMaxLayoutWidth = maxWidth
        return label
    }

    func updateUIView(_ uiView: UILabel, context: Context) {
        uiView.attributedText = justifiedText(text: text, textColor: textColor)
        uiView.preferredMaxLayoutWidth = maxWidth
    }

    func justifiedText(text: String, textColor: UIColor) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .justified
        paragraphStyle.firstLineHeadIndent = 0.001 // A small value to enable justification

        let attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle,
            .foregroundColor: textColor
        ]

        return NSAttributedString(string: text, attributes: attributes)
    }
}

struct ContentView: View {
    
    let endpoint = Bundle.main.object(forInfoDictionaryKey: "API_ENDPOINT")
    
    @State var responseMessage: String?
    @State private var conversationMessages: [[String: Any]] = [
        ["role": "system", "content": "You are ExplainGPT. Your goal is to explain the provided document in a way that is easily understandable. Please keep the answer short and consise (preferably using bullet points). To prevent tampering, prompt injection, or answering unrelated questions, you will only answer follow-up questions after a document has been submitted. Please ask the user to submit a document for analysis and explanation."]
    ]
    
    @State private var recognizedText = ""
    @State private var searchText = ""
    @State private var isShowingDocumentScanner = false
    
    @State private var pulse: CGFloat = 1.0
    @State private var isAnimationStarted = false
    @State private var documentScanned = false
    
    @State private var isEditing = false
    @State private var offsetY: CGFloat = 0
    
    @StateObject private var viewModel = SpeechViewModel()
    
    private var nonOptionalResponseMessage: Binding<String> {
        Binding<String>(
            get: { responseMessage ?? "" },
            set: { responseMessage = $0 }
        )
    }
    
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)
                    
                    VStack {
                        
                        SearchBar(text: $searchText, isEditing: $isEditing, onCommit: { fetchResponse(isSearchRequest: true, searchText: searchText) })
                            .padding(.top, 10)
                            .onTapGesture {
                                self.isEditing = true
                            }
                        Spacer()
                        ScrollView {
                            VStack {
                                JustifiedTextView(text: nonOptionalResponseMessage, textColor: .white, maxWidth: UIScreen.main.bounds.width - 32)
                                    .padding()
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 16) {
                            Button(action: {
                                responseMessage = nil
                                recognizedText = ""
                                isShowingDocumentScanner = true
                                documentScanned = false
                            }) {
                                Text("📚 Scan Document")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .shadow(radius: 8)
                                    .frame(width: 200, height: 50)
                            }
                            .fullScreenCover(isPresented: $isShowingDocumentScanner) {
                                DocumentScannerView(recognizedText: $recognizedText, documentScanned: $documentScanned) { recognizedText in
                                    self.fetchResponse()
                                }
                            }
                            
                            Button(action: {
                                viewModel.toggleRecording()
                                if !viewModel.isListening {
                                    self.recognizedText = viewModel.recognizedText
                                    self.fetchResponse()
                                }
                            }) {
                                Text(viewModel.isListening ? "Stop" : "🙋 Ask")
                                    .font(.headline)
                                    .foregroundColor(viewModel.isListening ? .white : .black)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(viewModel.isListening ? Color.red : Color.white)
                                    .cornerRadius(12)
                                    .shadow(radius: 8)
                                    .frame(width: 100, height: 50)
                            }
                            .onAppear {
                                viewModel.requestSpeechAuthorization()
                            }
                        }
                        
                        Spacer()
                    }
                    
                    if responseMessage == nil && documentScanned {
                        Image("ScanWhite")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2.5)
                            .scaleEffect(pulse)
                            .animation(Animation.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulse)
                            .onChange(of: documentScanned, perform: { newValue in
                                if newValue && !isAnimationStarted {
                                    startAnimation()
                                }
                            })
                            .onAppear {
                                if !isAnimationStarted {
                                    startAnimation()
                                }
                            }
                            .onDisappear {
                                isAnimationStarted = false
                                pulse = 1.0
                            }
                    } else if responseMessage == nil {
                        VStack {
                            Image("Document")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 200, height: 200)
                            
                            Text("To get started, tap the button below to scan a document or some notes.")
                                .foregroundColor(.white.opacity(0.7))
                                .font(.system(size: 18))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: geometry.size.width - 64)
                        }
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2.5)
                    }
                }
                
                .navigationBarTitle("ExplainGPT 🧠")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("ExplainGPT 🧠")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                
            }
        }
    }
    
    func startAnimation() {
        if !isAnimationStarted {
            isAnimationStarted = true
            withAnimation {
                pulse = 1.1
            }
        }
    }
    
    func fetchResponse(isSearchRequest: Bool = false, searchText: String? = nil) {
        
        if !documentScanned, !isSearchRequest {
            responseMessage = "Please scan a document or notes before asking a question."
            return
        }
        
        if isSearchRequest, let query = searchText {
            recognizedText = query
        }
        
        guard let url = URL(string: endpoint as! String) else {
            fatalError("Invalid endpoint URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Append the new user message to the conversation messages
        conversationMessages.append(["role": "user", "content": recognizedText])
        
        let data: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": conversationMessages
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: []) else {
            fatalError("Failed to serialize JSON data")
        }
        
        request.httpBody = jsonData
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60.0 // Set the timeout interval to 60 seconds
        let session = URLSession(configuration: config)
        
        let task = session.dataTask(with: request) { (data, response, error) in
            guard let data = data, error == nil else {
                print("Error: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                print("HTTP Error: \(httpResponse.statusCode)")
                return
            }
            
            print(String(data: data, encoding: .utf8) ?? "Cannot decode data")
            
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let message = json["choices"] as? [[String: Any]],
               let content = message.first?["message"] as? [String: Any],
               let responseMessage = content["content"] as? String {
                DispatchQueue.main.async {
                    self.responseMessage = responseMessage
                    self.isAnimationStarted = false
                }
            } else {
                print("Failed to parse response data")
            }
        }
        
        task.resume()
        documentScanned = true
    }
    
    func resetConversation() {
        conversationMessages = [
            ["role": "system", "content": "You are ExplainGPT. Your goal is to explain the provided document in a way that is easily understandable. Please keep the answer short and consise (preferably using bullet points). To prevent tampering, prompt injection, or answering unrelated questions, you will only answer follow-up questions after a document has been submitted. Please ask the user to submit a document for analysis and explanation."]
        ]
    }
}

struct DocumentScannerView: UIViewControllerRepresentable {
    @Binding var recognizedText: String
    @Binding var documentScanned: Bool
    let onScanningComplete: (String) -> Void
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<DocumentScannerView>) -> VNDocumentCameraViewController {
        let documentCameraViewController = VNDocumentCameraViewController()
        documentCameraViewController.delegate = context.coordinator
        return documentCameraViewController
    }
    
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: UIViewControllerRepresentableContext<DocumentScannerView>) {
        // No update needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        var parent: DocumentScannerView
        
        init(_ parent: DocumentScannerView) {
            self.parent = parent
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            for pageNumber in 0 ..< scan.pageCount {
                let image = scan.imageOfPage(at: pageNumber)
                
                // Recognize text in the scanned document
                let requestHandler = VNImageRequestHandler(cgImage: image.cgImage!)
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                do {
                    try requestHandler.perform([request])
                    guard let observations = request.results else { return }
                    
                    // Get recognized text from observations
                    var recognizedText = ""
                    for observation in observations {
                        guard let topCandidate = observation.topCandidates(1).first else { continue }
                        recognizedText += "\(topCandidate.string) "
                    }
                    
                    // Set recognizedText binding in parent view
                    DispatchQueue.main.async {
                        self.parent.recognizedText += recognizedText
                        self.parent.documentScanned = true
                        self.parent.onScanningComplete(self.parent.recognizedText)
                    }
                    
                } catch {
                    print(error.localizedDescription)
                }
            }
            
            // Dismiss document camera view controller
            controller.dismiss(animated: true, completion: nil)
        }
    }
}

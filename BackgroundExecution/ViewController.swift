//
//  ViewController.swift
//  BackgroundExecution
//
//  Created by Kumar Aman on 27/11/23.
//
import UIKit
import PhotosUI
import UserNotifications

class ViewController: UIViewController, PHPickerViewControllerDelegate, URLSessionDelegate, URLSessionTaskDelegate {

    @IBOutlet weak var numberLabel: UILabel!
    private var serialQueue = DispatchQueue(label: "com.example.uploaderQueue")
    private var uploadCount = 0
    private var totalImagesToUpload = 0
    private var responseData = [Int: Data]()
    private var backgroundSession: URLSession!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupBackgroundSession()
        requestNotificationPermission()
    }
    
    @IBAction func onStartPressed(_ sender: UIButton) {
        resetUploadCount()
        presentImagePicker()
    }
    
    private func setupBackgroundSession() {
        let config = URLSessionConfiguration.background(withIdentifier: "com.example.backgroundUploader")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        backgroundSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    private func resetUploadCount() {
        uploadCount = 0
        DispatchQueue.main.async {
            self.numberLabel.text = "0"
        }
    }
    
    private func presentImagePicker() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 0  // 0 for unlimited selection
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        totalImagesToUpload = results.count
        results.forEach { processPickerResult($0) }
    }
    
    private func processPickerResult(_ result: PHPickerResult) {
        result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, error in
            guard let self = self, let url = url, error == nil else { return }
            self.uploadImage(from: url)
        }
    }

    private func uploadImage(from url: URL) {
        var request = URLRequest(url: URL(string: "https://v2.convertapi.com/upload")!)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")

        let task = backgroundSession.uploadTask(with: request, fromFile: url)
        task.resume()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.handleUploadCompletion(for: task, error: error)
        }
    }
    
    private func handleUploadCompletion(for task: URLSessionTask, error: Error?) {
        if let error = error {
            numberLabel.text = "X"
            print("Upload failed: \(error.localizedDescription)")
            return
        }

        if let httpResponse = task.response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            uploadCount += 1
            numberLabel.text = String(uploadCount)
            
            if uploadCount == totalImagesToUpload {
                print("All uploads complete")
                clearCache()
                scheduleUploadCompletionNotification()
            }
        } else {
            numberLabel.text = "X"
            print("Upload failed: \(String(describing: task.response))")
        }
    }
    
    private func scheduleUploadCompletionNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Upload Complete"
        content.body = "All images uploaded successfully."
        content.sound = UNNotificationSound.default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "uploadComplete", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("Notification permission granted.")
            } else if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    private func clearCache() {
        guard let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        do {
            let fileNames = try FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path)
            for fileName in fileNames {
                let filePath = cacheDirectory.appendingPathComponent(fileName).path
                try FileManager.default.removeItem(atPath: filePath)
            }
            print("Cache cleared successfully.")
        } catch {
            print("Error clearing cache: \(error)")
        }
    }
}



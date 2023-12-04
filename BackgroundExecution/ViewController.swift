//
//  ViewController.swift
//  BackgroundExecution
//
//  Created by Kumar Aman on 27/11/23.
//
import UIKit
import PhotosUI

class ViewController: UIViewController, UIImagePickerControllerDelegate, PHPickerViewControllerDelegate, UINavigationControllerDelegate, URLSessionDelegate, URLSessionTaskDelegate {

    @IBOutlet weak var numberLabel: UILabel!
        var serialQueue: DispatchQueue!
        var uploadCount: Int!
        var fileUrls: [URL]!
        var mediaCount: Int!
        var responseData = [Int: Data]()
        var backgroundSession: URLSession!
        var backgroundSessionCompletionHandler: (() -> Void)?
        var backgroundTask: UIBackgroundTaskIdentifier!
        override func viewDidLoad() {
            super.viewDidLoad()
            requestNotificationPermission()
            clearCache()
            serialQueue = DispatchQueue(label: "UploaderQueue")
            uploadCount = 0
            mediaCount = 0
            fileUrls = []

            // Initialize the background URLSession
            let config = URLSessionConfiguration.background(withIdentifier: "com.yourapp.backgroundsession")
            config.isDiscretionary = false
            config.sessionSendsLaunchEvents = true
            backgroundSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        }
    
    @IBAction func onStartPressed(_ sender: UIButton) {
        self.uploadCount = 0
        DispatchQueue.main.async {
            self.numberLabel.text = String(self.uploadCount)
        }
        presentImagePicker()
    }
    
    func queueTest() {
        DispatchQueue.global().async {
            for i in 1...10 {
                print("Background Task \(i)")
            }
        }
        
        for i in 1...10 {
            print("Foreground Task \(i)")
        }
    }
    
    func useCustomQueues() {
        let serialQueue = DispatchQueue(label: "com.example.mySerialQueue")
        let concurrentQueue = DispatchQueue(label: "com.example.myConcurrentQueue", attributes: .concurrent)
        
        serialQueue.async {
            print("Task 1 started on serial queue")
            for i in 1...10 {
                print("SerialQueueTask1: \(i)")
            }
            print("Task 1 completed on serial queue")
        }
        
        serialQueue.async {
            print("Task 2 started on serial queue")
            for i in 1...10 {
                print("SerialQueueTask2: \(i)")
            }
            print("Task 2 completed on serial queue")
        }
        
        concurrentQueue.async {
            print("Task 3 started on concurrent queue")
            for i in 1...10 {
                print("ConcurrentQueueTask: \(i)")
            }
            print("Task 3 completed on concurrent queue")
        }
    }
    
    func dispatchAsync() {
        DispatchQueue.global(qos: .background).async {
            for _ in 0...1000 {
                
            }
            print("Background task")
            DispatchQueue.main.async {
                // Update UI here
                print("UI update on main queue")
            }
        }
    }
    
    func dispatchSync() {
        let customQueue = DispatchQueue(label: "com.example.customQueue")
        customQueue.sync {
            // Task that current thread needs to wait for
            for _ in 0...1000 {
                print("Background task")
            }
        }
        print("Task on custom queue completed")
    }
    
    func fetchData() {
        self.numberLabel.text = "0"
        var backgroundTask: UIBackgroundTaskIdentifier = .invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask {
            // End the task if time expires
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        DispatchQueue.global(qos: .background).async {
            sleep(5)
            print("Fetching data ...")
            //Simulate a network call
            sleep(2) //Simulates a network delay
            print("Data Fetched ...")
            let data = "1"
            
            DispatchQueue.main.async {
                self.numberLabel.text = data
                
                // End the background task
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid

            }
        }
    }
    
    func openImagePicker() {
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        imagePicker.sourceType = .photoLibrary
        present(imagePicker, animated: true)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)

        if let url = info[.imageURL] as? URL {
            // Use the url here
            uploadImage(selectedFile: url)
        }
    }
    
    func presentImagePicker() {
            var configuration = PHPickerConfiguration()
            configuration.selectionLimit = 0  // Set to 0 for unlimited selection, or a specific number
            configuration.filter = .images    // Only show images

            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            present(picker, animated: true)
        }

        // PHPickerViewControllerDelegate method
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            backgroundTask = UIApplication.shared.beginBackgroundTask {
                // End the task if time expires
                UIApplication.shared.endBackgroundTask(self.backgroundTask)
                self.backgroundTask = .invalid
            }
            for result in results {
                let itemProvider = result.itemProvider
                if itemProvider.canLoadObject(ofClass: UIImage.self) {
                    itemProvider.loadObject(ofClass: UIImage.self) { (object, error) in
                        guard let image = object as? UIImage else { return }
                        let fileURL = self.saveImageToTemporaryFile(image: image)
                        self.mediaCount = results.count
                        self.fileUrls.append(fileURL)
                        DispatchQueue.global(qos: .background).async {
                            self.serialQueue.async {
                                self.uploadImage(selectedFile: fileURL)
                            }
                        }
                    }
                }
            }
        }

    
    func saveImageToTemporaryFile(image: UIImage) -> URL {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
        let fileName = UUID().uuidString + ".jpg"
        let fileURL = tempDirectory.appendingPathComponent(fileName)

        if let data = image.jpegData(compressionQuality: 1.0) {
            try? data.write(to: fileURL)
        }

        return fileURL
    }

    
    func uploadImage(selectedFile: URL) {
        guard let url = URL(string: "https://v2.convertapi.com/upload") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")

        let task = backgroundSession.uploadTask(with: request, fromFile: selectedFile)
        task.taskDescription = selectedFile.path
        task.resume()
    }

    // URLSession delegate methods for handling responses
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("Upload failed with error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.numberLabel.text = "X"
            }
        } else if let httpResponse = task.response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            // Successfully uploaded
            self.uploadCount += 1
            DispatchQueue.main.async {
                self.numberLabel.text = String(self.uploadCount)
                
                if self.mediaCount == self.uploadCount {
                    // All uploads are complete
                    print("All uploads complete")
                    self.scheduleUploadCompletionNotification()
                    // End the background task
                    UIApplication.shared.endBackgroundTask(self.backgroundTask)
                    self.backgroundTask = .invalid
                }
            }

            // Example of how to handle response data
            if let data = responseData[task.taskIdentifier], let responseBody = String(data: data, encoding: .utf8) {
                    print("UploadSuccess: \(responseBody)")
            }
        } else {
            // Handle other HTTP responses
            DispatchQueue.main.async {
                self.numberLabel.text = "X"
            }
            print("Upload failed: \(String(describing: task.response))")
        }
        // Clean-up
        responseData.removeValue(forKey: task.taskIdentifier)
        if let selectedFilePath = task.taskDescription {
            let selectedFileURL = URL(fileURLWithPath: selectedFilePath)
                self.deleteTemporaryFiles(selectedFileURL)
        }
    }

    
    func deleteTemporaryFiles(_ fileURL: URL) {
        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(at: fileURL)
            print("Deleted temporary file: \(fileURL)")
        } catch {
            print("Failed to delete temporary file: \(error)")
        }
    }
    
    func clearCache() {
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        if let cacheDirectory = cacheDirectory {
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
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            if let completionHandler = self.backgroundSessionCompletionHandler {
                self.backgroundSessionCompletionHandler = nil
                completionHandler()
            }
            // Perform any other finalization work
        }
    }
    
    // Schedule a notification
    func scheduleUploadCompletionNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Upload Complete"
        content.body = "Your images have been successfully uploaded."
        content.sound = UNNotificationSound.default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "uploadComplete", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error)")
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

}


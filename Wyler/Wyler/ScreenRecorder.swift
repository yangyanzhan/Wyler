//
//  ScreenRecorder.swift
//  Wyler
//
//  Created by Cesar Vargas on 10.04.20.
//  Copyright © 2020 Cesar Vargas. All rights reserved.
//

import Foundation
import ReplayKit
import Photos
import AVFoundation
import CoreMedia

public enum WylerError: Error {
  case photoLibraryAccessNotGranted
}

final public class ScreenRecorder {
    public static let shared = ScreenRecorder()
    
  private var videoOutputURL: URL?
  private var videoWriter: AVAssetWriter?
  private var videoWriterInput: AVAssetWriterInput?
  private var micAudioWriterInput: AVAssetWriterInput?
  private var appAudioWriterInput: AVAssetWriterInput?
  private var saveToCameraRoll = false
  let recorder = RPScreenRecorder.shared()

  public init() {
    recorder.isMicrophoneEnabled = false
  }

  /**
   Starts recording the content of the application screen. It works together with stopRecording

  - Parameter outputURL: The output where the video will be saved. If nil, it saves it in the documents directory.
  - Parameter size: The size of the video. If nil, it will use the app screen size.
  - Parameter saveToCameraRoll: Whether to save it to camera roll. False by default.
  - Parameter errorHandler: Called when an error is found
  */
  public func startRecording(to outputURL: URL? = nil,
                             size: CGSize? = nil,
                             saveToCameraRoll: Bool = false,
                             errorHandler: @escaping (Error) -> Void,
                             permissionHandler: @escaping (Error?) -> Void) {
    createVideoWriter(in: outputURL, error: errorHandler)
    addVideoWriterInput(size: size)
    self.micAudioWriterInput = createAndAddAudioInput()
    self.appAudioWriterInput = createAndAddAudioInput()
    startCapture(error: errorHandler, permissionHandler: permissionHandler)
  }

  private func checkPhotoLibraryAuthorizationStatus() {
    let status = PHPhotoLibrary.authorizationStatus()
    if status == .notDetermined {
      PHPhotoLibrary.requestAuthorization({ _ in })
    }
  }

  private func createVideoWriter(in outputURL: URL? = nil, error: (Error) -> Void) {
    let newVideoOutputURL: URL

    if let passedVideoOutput = outputURL {
      self.videoOutputURL = passedVideoOutput
      newVideoOutputURL = passedVideoOutput
    } else {
      let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
      newVideoOutputURL = URL(fileURLWithPath: documentsPath.appendingPathComponent("OkTalk.mp4"))
      self.videoOutputURL = newVideoOutputURL
    }

    do {
      try FileManager.default.removeItem(at: newVideoOutputURL)
    } catch {}

    do {
      try videoWriter = AVAssetWriter(outputURL: newVideoOutputURL, fileType: AVFileType.mp4)
    } catch let writerError as NSError {
      error(writerError)
      videoWriter = nil
      return
    }
  }

  private func addVideoWriterInput(size: CGSize?) {
    let passingSize: CGSize = size ?? UIScreen.main.bounds.size

    let videoSettings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                                        AVVideoWidthKey: passingSize.width,
                                        AVVideoHeightKey: passingSize.height]

    let newVideoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)

    self.videoWriterInput = newVideoWriterInput
    newVideoWriterInput.expectsMediaDataInRealTime = true
    videoWriter?.add(newVideoWriterInput)
  }
  
  private func createAndAddAudioInput() -> AVAssetWriterInput {
    let settings = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM) as AnyObject,
        AVSampleRateKey: 16000 as AnyObject,
        AVNumberOfChannelsKey: 1 as AnyObject,
        AVLinearPCMBitDepthKey: 16 as AnyObject,
        AVLinearPCMIsBigEndianKey: false as AnyObject,
        AVLinearPCMIsFloatKey: false as AnyObject,
        AVLinearPCMIsNonInterleaved: false as AnyObject
    ]

    let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)

    audioInput.expectsMediaDataInRealTime = true
    videoWriter?.add(audioInput)
    
    return audioInput
  }

  private func startCapture(error: @escaping (Error) -> Void, permissionHandler: @escaping (Error?) -> Void) {
    recorder.startCapture(handler: { (sampleBuffer, sampleType, passedError) in
      if let passedError = passedError {
        error(passedError)
        return
      }

      switch sampleType {
      case .video:
        self.handleSampleBuffer(sampleBuffer: sampleBuffer)
      case .audioApp:
//        self.add(sample: sampleBuffer, to: self.appAudioWriterInput)
          break
      case .audioMic:
//        self.add(sample: sampleBuffer, to: self.micAudioWriterInput)
          break
      default:
        break
      }
    }) { error in
        permissionHandler(error)
    }
  }
    
    public func feedAppAudio(_ pcmBuffer: AVAudioPCMBuffer) {
        if self.appAudioWriterInput == nil {
            return
        }
        if let sampleBuffer = Converter.configureSampleBuffer(pcmBuffer: pcmBuffer) {
            add(sample: sampleBuffer, to: self.appAudioWriterInput)
        }
    }
    
    public func feedMicAudio(_ pcmBuffer: AVAudioPCMBuffer) {
        if self.micAudioWriterInput == nil {
            return
        }
        if let sampleBuffer = Converter.configureSampleBuffer(pcmBuffer: pcmBuffer) {
            add(sample: sampleBuffer, to: self.micAudioWriterInput)
        }
    }

  private func handleSampleBuffer(sampleBuffer: CMSampleBuffer) {
    if self.videoWriter?.status == AVAssetWriter.Status.unknown {
      self.videoWriter?.startWriting()
      self.videoWriter?.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    } else if self.videoWriter?.status == AVAssetWriter.Status.writing &&
      self.videoWriterInput?.isReadyForMoreMediaData == true {
      self.videoWriterInput?.append(sampleBuffer)
    }
  }
  
  private func add(sample: CMSampleBuffer, to writerInput: AVAssetWriterInput?) {
      if self.videoWriter?.status == AVAssetWriter.Status.writing && writerInput?.isReadyForMoreMediaData ?? false {
      writerInput?.append(sample)
    }
  }

  /**
   Stops recording the content of the application screen, after calling startRecording

  - Parameter errorHandler: Called when an error is found
  */
  public func stopRecording(completionHandler: @escaping (URL?, Error?) -> Void) {
      RPScreenRecorder.shared().stopCapture( handler: { error in
          debugPrint("[RPScreenRecorder Error]: \(String(describing: error))")
      })
      self.videoWriterInput?.markAsFinished()
      self.micAudioWriterInput?.markAsFinished()
      self.appAudioWriterInput?.markAsFinished()
      self.videoWriter?.finishWriting {
          completionHandler(self.videoOutputURL, nil)
      }
//    self.videoWriterInput?.markAsFinished()
//    self.micAudioWriterInput?.markAsFinished()
//    self.appAudioWriterInput?.markAsFinished()
//    self.videoWriter?.finishWriting {
//      self.saveVideoToCameraRollAfterAuthorized(errorHandler: errorHandler)
//    }
  }

  private func saveVideoToCameraRollAfterAuthorized(errorHandler: @escaping (Error) -> Void) {
    if PHPhotoLibrary.authorizationStatus() == .authorized {
        self.saveVideoToCameraRoll(errorHandler: errorHandler)
    } else {
        PHPhotoLibrary.requestAuthorization({ (status) in
            if status == .authorized {
                self.saveVideoToCameraRoll(errorHandler: errorHandler)
            } else {
              errorHandler(WylerError.photoLibraryAccessNotGranted)
          }
        })
    }
  }

  private func saveVideoToCameraRoll(errorHandler: @escaping (Error) -> Void) {
    guard let videoOutputURL = self.videoOutputURL else {
      return
    }

    PHPhotoLibrary.shared().performChanges({
      PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoOutputURL)
    }, completionHandler: { _, error in
      if let error = error {
        errorHandler(error)
      }
    })
  }
}

class Converter {
    static func configureSampleBuffer(pcmBuffer: AVAudioPCMBuffer) -> CMSampleBuffer? {
        let audioBufferList = pcmBuffer.mutableAudioBufferList
        let asbd = pcmBuffer.format.streamDescription

        var sampleBuffer: CMSampleBuffer? = nil
        var format: CMFormatDescription? = nil
        
        var status = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                                         asbd: asbd,
                                                   layoutSize: 0,
                                                       layout: nil,
                                                       magicCookieSize: 0,
                                                       magicCookie: nil,
                                                       extensions: nil,
                                                       formatDescriptionOut: &format);
        if (status != noErr) { return nil; }
        
        var timing: CMSampleTimingInfo = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(asbd.pointee.mSampleRate)),
                                                            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                                            decodeTimeStamp: CMTime.invalid)
        status = CMSampleBufferCreate(allocator: kCFAllocatorDefault,
                                      dataBuffer: nil,
                                      dataReady: false,
                                      makeDataReadyCallback: nil,
                                      refcon: nil,
                                      formatDescription: format,
                                      sampleCount: CMItemCount(pcmBuffer.frameLength),
                                      sampleTimingEntryCount: 1,
                                      sampleTimingArray: &timing,
                                      sampleSizeEntryCount: 0,
                                      sampleSizeArray: nil,
                                      sampleBufferOut: &sampleBuffer);
        if (status != noErr) { NSLog("CMSampleBufferCreate returned error: \(status)"); return nil }
        
        status = CMSampleBufferSetDataBufferFromAudioBufferList(sampleBuffer!,
                                                                blockBufferAllocator: kCFAllocatorDefault,
                                                                blockBufferMemoryAllocator: kCFAllocatorDefault,
                                                                flags: 0,
                                                                bufferList: audioBufferList);
        if (status != noErr) { NSLog("CMSampleBufferSetDataBufferFromAudioBufferList returned error: \(status)"); return nil; }
        
        return sampleBuffer
    }
}

// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

// TODO: Put public facing types in this file.

library resumable.base;

import 'dart:async';
import 'dart:html';

typedef String IdGenerator();
typedef void MaxFilesErrorCallback(List<File> files, num errorCount);
typedef void FileTypeErrorCallback(File file, num errorCount);
/// A specific file was completed.
typedef void FileSuccess(ResumableFile file);
/// Uploading progressed for a specific file.
typedef void FileProgress(ResumableFile file);
/// A new file was added.
typedef void FileAdded(ResumableFile file);
/// Something went wrong during upload of a specific file, uploading is being retried.
typedef void FileRetry(ResumableFile file);
/// An error occured during upload of a specific file.
typedef void FileError(ResumableFile file, String message);
///.complete() Uploading completed.
typedef void Complete();
/// Uploading progress.
typedef void Progress();
/// An error, including fileError, occured.
typedef void Error(String message, ResumableFile file);
/// Uploading was paused.
typedef void Pause();
/// Uploading was canceled.
typedef void Cancel();
///.catchAll(event, ...) Listen to all the events listed above with the same callback function.

/// Checks if you are awesome. Spoiler: you are.
class Resumable {
  static const num DEFAULT_CHUNK_SIZE = 1 * 1024 * 1024;
  /// The target URL for the multipart POST request
  String target = '/';
  /// The size in bytes of each uploaded chunk of data
  num chunkSize = DEFAULT_CHUNK_SIZE;
  /// Number of simultaneous uploads
  num simultaneousUploads = 3;
  /// The name of the multipart POST parameter to use for the file chunk
  String fileParameterName = 'file';
  /// Extra parameters to include in the multipart POST with data. This can be an Map<String,String> or a function. If
  /// a function, it will be passed a ResumableFile object
  dynamic query = const <String,String>{};
  /// Extra headers to include in the multipart POST with data
  Map<String,String> headers = const <String,String>{};
  /// Prioritize first and last chunks of all files. This can be handy if you can determine if a file is valid for
  /// your service from only the first or last chunk. For example, photo or video meta data is usually located in the
  /// first part of a file, making it easy to test support from only the first chunk.
  bool prioritizeFirstAndLastChunk = false;
  /// Make a GET request to the server for each chunks to see if it already exists. If implemented on the server-side,
  /// this will allow for upload resumes even after a browser crash or even a computer restart.
  bool testChunks = true;
  /// Override the function that generates unique identifiers for each file.
  IdGenerator generateUniqueIdentifier = null;
  /// Indicates how many files can be uploaded in a single session. Valid values are any positive integer -1 for no
  /// limit.
  num maxFiles = -1;
  /// A function which displays the please upload n file(s) at a time message. (Default: displays an alert box with
  /// the message Please n one file(s) at a time.)
  MaxFilesErrorCallback maxFilesErrorCallback = (files, errorCount) => window.alert('Please upload $maxFiles file${maxFiles == 1 ? '' : 's'} at a time.');
  /// A function which displays the file types do not match message.  (Default displays an alert box with the message
  /// Please select only files with filetypes.)
  FileTypeErrorCallback fileTypeErrorCallback = (file, errorCount) => window.alert('Please select only files with extensions ${fileTypes.join(', ')}.');

  /// A list of file extensions to accept for upload
  List<String> fileTypes = const [];
  Resumable({
             this.target
            ,this.chunkSize
            ,this.simultaneousUploads
            ,this.fileParameterName
            ,this.query
            ,this.headers });

  bool get support => true;

  List<ResumableFile> get files => const [];

  /// Assign a browse action to one DOM nodes. Pass in true to isDirectory to allow directories to be selected (Chrome
  /// only).
  void assignBrowseElement(Element domNode, {bool isDirectory : false}) {
    assignBrowseElements([domNode], isDirectory: isDirectory);
  }

  /// Assign a browse action to one or more DOM nodes. Pass in true to isDirectory to allow directories to be selected
  /// (Chrome only).
  void assignBrowseElements(List<Element> domNodes, {bool isDirectory : false}) {
    for (var domNode in domNodes) {
      InputElement input;
      if (domNode is InputElement && domNode.type == 'file') {
        input = domNode;
      } else {
        input = new InputElement(type: 'file');
        input.style.display = 'none';
        domNode.onClick.listen((e) {
          input.style.opacity = '0';
          input.style.display = 'block';
          input.focus();
          input.click();
          input.style.display = 'none';
        });
        domNode.append(input);
      }
      input.multiple = maxFiles != 1;
      input.directory = isDirectory;
      input.onChange.listen((e) {
        InputElement target = e.target;
        appendFilesFromFileList(target.files,e);
        target.value = '';
      });
    }
  }

  /// Assign one DOM nodes as a drop target.
  void assignDropElement(Element domNode) {
    assignDropElements([domNode]);
  }

  /// Assign one or more DOM nodes as a drop target.
  void assignDropElements(List<Element> domNodes) {

  }

  /// Start or resume uploading.
  void upload();

  /// Pause uploading.
  void pause();

  /// Cancel upload of all ResumableFile objects and remove them from the list.
  void cancel();

  /// Returns a float between 0 and 1 indicating the current upload progress of all files.
  num get progress => 0;

  /// Returns a boolean indicating whether or not the instance is currently uploading anything.
  bool get uploading => false;

  /// Cancel upload of a specific ResumableFile object on the list from the list.
  void removeFile(ResumableFile file) {

  }

  /// Look up a ResumableFile object by its unique identifier.
  ResumableFile getFromUniqueIdentifier(String uniqueIdentifier) {
    return null;
  }

  /// Returns the total size of the upload in bytes.
  num get size => 0;

  // Internal

  bool appendFilesFromFileList(List<File> filesList, Event event) {
    // check for uploading too many files
    var errorCount = 0;
    if (maxFiles != -1 && maxFiles < (filesList.length + this.files.length)) {
      // if single-file upload, file is already added, and trying to add 1 new file, simply replace the already-added file
      if (maxFiles == 1 && this.files.length == 1 && filesList.length == 1) {
        this.files.removeAt(0);
      } else {
        maxFilesErrorCallback(filesList, errorCount++);
        return false;
      }
    }

    var files = [];
    for (var file in filesList) {
      var filename = file.name;
      if (fileTypes.isNotEmpty) {
        if (!fileTypes.map((_) => _.startsWith('.') ? _ : ".$_").any((extension) => filename.endsWith(extension))) {
          fileTypeErrorCallback(file, errorCount++);
          return false;
        }
      }
    }

    // min and max file size checks.
//    // check for uploading too many files
//    var errorCount = 0;
//    var o = $.getOpt(['maxFiles', 'minFileSize', 'maxFileSize', 'maxFilesErrorCallback', 'minFileSizeErrorCallback', 'maxFileSizeErrorCallback', 'fileType', 'fileTypeErrorCallback']);
//    if (typeof(o.maxFiles)!=='undefined' && o.maxFiles<(fileList.length+$.files.length)) {
//  // if single-file upload, file is already added, and trying to add 1 new file, simply replace the already-added file
//  if (o.maxFiles===1 && $.files.length===1 && fileList.length===1) {
//  $.removeFile($.files[0]);
//  } else {
//  o.maxFilesErrorCallback(fileList, errorCount++);
//  return false;
//  }
//  }
//  var files = [];
//  $h.each(fileList, function(file){
//    var fileName = file.name;
//    if(o.fileType.length > 0){
//      var fileTypeFound = false;
//      for(var index in o.fileType){
//        var extension = '.' + o.fileType[index];
//        if(fileName.indexOf(extension, fileName.length - extension.length) !== -1){
//          fileTypeFound = true;
//          break;
//        }
//      }
//      if (!fileTypeFound) {
//        o.fileTypeErrorCallback(file, errorCount++);
//        return false;
//      }
//    }
//
//    if (typeof(o.minFileSize)!=='undefined' && file.size<o.minFileSize) {
//      o.minFileSizeErrorCallback(file, errorCount++);
//      return false;
//    }
//    if (typeof(o.maxFileSize)!=='undefined' && file.size>o.maxFileSize) {
//      o.maxFileSizeErrorCallback(file, errorCount++);
//      return false;
//    }
//
//    function addFile(uniqueIdentifier){
//      if (!$.getFromUniqueIdentifier(uniqueIdentifier)) {(function(){
//      file.uniqueIdentifier = uniqueIdentifier;
//      var f = new ResumableFile($, file, uniqueIdentifier);
//      $.files.push(f);
//      files.push(f);
//      f.container = (typeof event != 'undefined' ? event.srcElement : null);
//      window.setTimeout(function(){
//      $.fire('fileAdded', f, event)
//      },0);
//      })()};
//    }
//    // directories have size == 0
//    var uniqueIdentifier = $h.generateUniqueIdentifier(file)
//    if(uniqueIdentifier && typeof uniqueIdentifier.done === 'function' && typeof uniqueIdentifier.fail === 'function'){
//      uniqueIdentifier
//      .done(function(uniqueIdentifier){
//      addFile(uniqueIdentifier);
//      })
//      .fail(function(){
//      addFile();
//      });
//    }else{
//      addFile(uniqueIdentifier);
//    }
//
//  });
//  window.setTimeout(function(){
//    $.fire('filesAdded', files)
//  },0);
  }

  // Events

  StreamController<FileSuccessEvent> _fileSuccessController = new StreamController<FileSuccessEvent>();
  Stream<FileSuccessEvent> get onFileSuccess => _fileSuccessController.stream;

  StreamController<FileProgressEvent> _fileProgressController = new StreamController<FileProgressEvent>();
  Stream<FileProgressEvent> get onFileProgress => _fileProgressController.stream;

}

class ResumableFile {
  Resumable _resumable;
  File _file;
  String _uniqueIdentifier;
  List<ResumableChunk> _resumableChunks = [];

  ResumableFile(this._resumable, this._file, this._uniqueIdentifier);

  File get file => _file;
  String get filename => _file.name;
  String get relativePath => _file.relativePath;
  String get uniqueIdentifier => _uniqueIdentifier;
  num get size => _file.size;
  List<ResumableChunk> get resumableChunks => new List<ResumableChunk>.unmodifiable(_resumableChunks);
}

class ResumableChunk {
  Resumable _resumable;
  ResumableFile _resumableFile;
  var _offset;
  var _callback;

  ResumableChunk(this._resumable, this._resumableFile, this._offset, this._callback);


}

class ResumableEvent {}

abstract class FileEvent extends ResumableEvent {
  ResumableFile _resumableFile;

  FileEvent(this._resumableFile);

  ResumableFile get resumableFile => _resumableFile;
}

class FileSuccessEvent extends FileEvent{
  FileSuccessEvent(ResumableFile resumableFile) : super(resumableFile);
}

class FileProgressEvent extends FileEvent{
  FileProgressEvent(ResumableFile resumableFile) : super(resumableFile);
}

class FileErrorEvent extends FileEvent{

  String _message;

  FileErrorEvent(ResumableFile resumableFile, this._message) : super(resumableFile);

  String get message => _message;
}




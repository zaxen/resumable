// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

// TODO: Put public facing types in this file.

library resumable.base;

import 'dart:async';
import 'dart:collection';
import 'dart:core';
import 'dart:html';

typedef String IdGenerator(File file);
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
  final String target = '/';
  /// The size in bytes of each uploaded chunk of data
  final num chunkSize = DEFAULT_CHUNK_SIZE;
  /// Number of simultaneous uploads
  final num simultaneousUploads = 3;
  /// The name of the multipart POST parameter to use for the file chunk
  final String fileParameterName = 'file';
  /// Extra parameters to include in the multipart POST with data. This can be an Map<String,String> or a function. If
  /// a function, it will be passed a ResumableFile object
  final dynamic query = const <String,String>{};
  /// Extra headers to include in the multipart POST with data
  final Map<String,String> headers = const <String,String>{};
  /// Prioritize first and last chunks of all files. This can be handy if you can determine if a file is valid for
  /// your service from only the first or last chunk. For example, photo or video meta data is usually located in the
  /// first part of a file, making it easy to test support from only the first chunk.
  final bool prioritizeFirstAndLastChunk = false;
  /// Make a GET request to the server for each chunks to see if it already exists. If implemented on the server-side,
  /// this will allow for upload resumes even after a browser crash or even a computer restart.
  final bool testChunks = true;
  /// Override the function that generates unique identifiers for each file.
  final IdGenerator generateUniqueIdentifier = null;
  /// Indicates how many files can be uploaded in a single session. Valid values are any positive integer, null for no
  /// limit.
  final num maxFiles = null;
  /// Indicates the minimum file size to upload. Valid values are any positive integer, null for no
  /// limit.
  final num minFileSize = null;
  /// Indicates the maximum file size to upload. Valid values are any positive integer, null for no
  /// limit.
  final num maxFileSize = null;

  /// A list of file extensions to accept for upload
  List<String> fileTypes = const [];
  Resumable({
             this.target
            ,this.chunkSize
            ,this.simultaneousUploads
            ,this.fileParameterName
            ,this.query
            ,this.headers
            ,this.minFileSize
            ,this.maxFileSize
            ,this.maxFiles
            });

  bool get support => true;

  List<ResumableFile> get files => const [];
  Map<String,ResumableFile> _fileMap = new Map<String,ResumableFile>();

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
        appendFilesFromFileStream(new Stream.fromIterable(new List.from(target.files)));
        target.value = '';
      });
    }
  }

  /// Assign one DOM nodes as a drop target.
  void assignDropElement(Element domNode) {
    assignDropElements([domNode]);
  }

  var _preventDefault = (Event event) => event.preventDefault();

  void _onDrop(MouseEvent event) {
    event.preventDefault();
    if (event.dataTransfer != null) {
      final items = event.dataTransfer.items;
      final files = event.dataTransfer.files;
      Stream<File> fileStream;
      if (items != null) {
        var itemList = <DataTransferItem>[];
        for (var i=0; i < items.length; ++i) {
          itemList[i] = items[i];
        }
        fileStream = _loadDataTransferItems(itemList);
      } else if (files != null) {
        fileStream = new Stream.fromIterable(files);
      } else {
        fileStream = new Stream<File>.fromIterable([]);
      }
      appendFilesFromFileStream(fileStream);
    }
  }

  Stream<File> _loadDataTransferItems(List<DataTransferItem> items) async* {
    for (DataTransferItem item in items) {
      Entry entry = item.getAsEntry();
      if (entry != null) {
        if (entry.isFile) {
          FileEntry fileEntry = entry;
          yield await fileEntry.file();
        } else if (entry.isDirectory) {
          yield* _loadDirEntry(entry);
        }
      }
    }
  }

  Stream<File> _loadDirEntry(DirectoryEntry dirEntry) async* {
    DirectoryReader reader = dirEntry.createReader();
    List<Entry> dirEntries = await reader.readEntries();
    for (Entry entry in dirEntries) {
      if (entry.isFile) {
        FileEntry fe = entry;
        yield await fe.file();
      } else if (entry.isDirectory) {
        yield* _loadDirEntry(entry);
      }
    }
  }

  /// Assign one or more DOM nodes as a drop target.
  void assignDropElements(List<Element> domNodes) {
    for (var domNode in domNodes) {
      domNode.addEventListener("dragover", _preventDefault);
      domNode.addEventListener("dragenter", _preventDefault);
      domNode.addEventListener("drop", _onDrop);
    }
  }

  void unassignDropElements(List<Element> domNodes) {
    for (var domNode in domNodes) {
      domNode.removeEventListener("dragover", _preventDefault);
      domNode.removeEventListener("dragenter", _preventDefault);
      domNode.removeEventListener("drop", _onDrop);
    }
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
    _fileMap.remove(file.uniqueIdentifier);
    files.remove(file);
  }

  /// Look up a ResumableFile object by its unique identifier.
  ResumableFile getFromUniqueIdentifier(String uniqueIdentifier) {
    return _fileMap[uniqueIdentifier];
  }

  /// Returns the total size of the upload in bytes.
  num get size => files.fold(0, (v, e) => v += e.file.size);

  // Internal

  bool _fireEvent(StreamController<ResumableEvent> controller, ResumableEvent event) {
    if (controller.hasListener) {
      controller.add(event);
      return true;
    } else {
      window.console.warn("$controller has no listener for $event");
      return false;
    }
  }

  final _uniqueIdRegExp = new RegExp(r"[^0-9a-zA-Z_-]", multiLine: true, caseSensitive: true);
  String _generateUniqueIdentifier(File file) {
    if (generateUniqueIdentifier != null) {
      return generateUniqueIdentifier(file);
    } else {
      final relativePath = file.relativePath;
      final size = file.size;

      return "$size - ${relativePath.replaceAll(_uniqueIdRegExp, '')}";
    }
  }

  Future appendFilesFromFileStream(Stream<File> fileStream/*, Event event*/) async {

    //var files = <ResumableFile>[];
    await for (File file in fileStream) {
      var filename = file.name;
      if (fileTypes.isNotEmpty) {
        if (!fileTypes.map((_) => _.startsWith('.') ? _ : ".$_").any((extension) => filename.endsWith(extension))) {
          _fireEvent(_fileAddedErrorController, new InvalidFileTypeEvent(file));
          continue;
        }
      }

      if (minFileSize != null && minFileSize > file.size) {
        _fireEvent(_fileAddedErrorController, new FileTooSmallEvent(file));
        continue;
      }
      if (maxFileSize != null && maxFileSize < file.size) {
        _fireEvent(_fileAddedErrorController, new FileTooLargeEvent(file));
        continue;
      }

      var uniqueIdentifier = _generateUniqueIdentifier(file);
      if (getFromUniqueIdentifier(uniqueIdentifier) == null) {

        // going to add this file, so check if it will exceed max files
        if (this.files.length >= maxFiles) {
          _fireEvent(_fileAddedController, new TooManyFilesEvent(file));
          continue;
        }

        var f = new ResumableFile(this, file, uniqueIdentifier);

        //if (event != null) f.container = event.target;
        //files.add(f);
        this.files.add(f);
        this._fileMap[uniqueIdentifier] = f;
        _fireEvent(_fileAddedController, new FileAddedEvent(f));
      }
    }
  }

  // Events

  StreamController<FileAddedEvent> _fileAddedController = new StreamController<FileAddedEvent>.broadcast();
  Stream<FileAddedEvent> get onFileAdded => _fileAddedController.stream;

  StreamController<FileAddErrorEvent> _fileAddedErrorController = new StreamController<FileAddErrorEvent>.broadcast();
  Stream<FileAddErrorEvent> get onFileAddedError => _fileAddedErrorController.stream;

  StreamController<FileSuccessEvent> _fileSuccessController = new StreamController<FileSuccessEvent>.broadcast();
  Stream<FileSuccessEvent> get onFileSuccess => _fileSuccessController.stream;

  StreamController<FileProgressEvent> _fileProgressController = new StreamController<FileProgressEvent>.broadcast();
  Stream<FileProgressEvent> get onFileProgress => _fileProgressController.stream;

}

class ResumableFile {
  final Resumable _resumable;
  final File _file;
  final String _uniqueIdentifier;
  List<ResumableChunk> _resumableChunks = [];
  var container;

  ResumableFile(this._resumable, this._file, this._uniqueIdentifier) {
    _resumableChunks = _generateChunks();
  }

  List<ResumableChunk> _generateChunks() {
    var chunks = (_file.size / _resumable.chunkSize).floor() + 1;
    var result = new List<ResumableChunk>(chunks);
    for (int i = 0; i < chunks; ++i) {
      result[i] = new ResumableChunk(_resumable, this, _resumable.chunkSize * i);
    }
    return result;
  }

  File get file => _file;
  String get filename => _file.name;
  String get relativePath => _file.relativePath;
  String get uniqueIdentifier => _uniqueIdentifier;
  num get size => _file.size;

  List<ResumableChunk> get resumableChunks => new UnmodifiableListView(_resumableChunks);
}

class ResumableChunk {
  final Resumable _resumable;
  final ResumableFile _resumableFile;
  final num _offset;

  bool tested = false;

  ResumableChunk(this._resumable, this._resumableFile, this._offset);

  void upload() {
    if (_resumable.testChunks && !tested) {

    }
  }

  Future<bool> test() async {
    HttpRequest request = new HttpRequest();


    request.onError.single;
    await for (ProgressEvent e in request.onReadyStateChange) {
      if (request.readyState == HttpRequest.DONE) {

      }
    }
  }
}

class ResumableEvent {}

abstract class FileEvent extends ResumableEvent {
  final ResumableFile resumableFile;

  FileEvent(this.resumableFile);
}

class FileSuccessEvent extends FileEvent {
  FileSuccessEvent(ResumableFile resumableFile) : super(resumableFile);
}

class FileProgressEvent extends FileEvent {
  FileProgressEvent(ResumableFile resumableFile) : super(resumableFile);
}

abstract class FileAddErrorEvent extends ResumableEvent {
  final File file;
  FileAddErrorEvent(this.file);
}

class FileTooLargeEvent extends FileAddErrorEvent {
  FileTooLargeEvent(File file) : super(file);
}

class FileTooSmallEvent extends FileAddErrorEvent {
  FileTooSmallEvent(File file) : super(file);
}

class TooManyFilesEvent extends FileAddErrorEvent {
  TooManyFilesEvent(File file) : super(file);
}

class InvalidFileTypeEvent extends FileAddErrorEvent {
  InvalidFileTypeEvent(File file) : super(file);
}

class FileAddedEvent extends FileEvent {
  FileAddedEvent(ResumableFile resumableFile) : super(resumableFile);
}

class FileErrorEvent extends FileEvent {
  final String message;

  FileErrorEvent(ResumableFile resumableFile, this.message) : super(resumableFile);
}




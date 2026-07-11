import 'dart:typed_data';

class BinaryReader {
  factory BinaryReader(Uint8List bytes) {
    final offset = bytes.offsetInBytes;
    final len = bytes.lengthInBytes ~/ 8;

    return BinaryReader._(
      bytes.buffer.asFloat64List(offset, len),
      bytes.buffer.asInt64List(offset, len),
    );
  }

  BinaryReader._(this._floats, this._ints);

  final Float64List _floats;
  final Int64List _ints;
  int _offset = 0;

  double readDouble() => _floats[_offset++];

  int readInt() => _ints[_offset++];

  bool readBool() => _ints[_offset++] == 1;

  Float64List readDoubleList() {
    final len = _ints[_offset++];
    final list = Float64List.sublistView(_floats, _offset, _offset + len);
    _offset += len;
    return list;
  }

  Int64List readIntList() {
    final len = _ints[_offset++];
    final list = Int64List.sublistView(_ints, _offset, _offset + len);
    _offset += len;
    return list;
  }

  /// Reads 8-byte-aligned data and returns a Uint8List.
  Uint8List readAlignedBytes() {
    final len = _ints[_offset++];
    final list = Float64List.sublistView(_floats, _offset, _offset + len);
    _offset += len;
    return Uint8List.view(list.buffer, list.offsetInBytes, list.lengthInBytes);
  }
}

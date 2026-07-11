import 'dart:typed_data';

class BinaryWriter {
  factory BinaryWriter(int lengthIn64Bits) {
    final floats = Float64List(lengthIn64Bits);
    final ints = floats.buffer.asInt64List();
    return BinaryWriter._(floats, ints);
  }

  BinaryWriter._(this._floats, this._ints);

  final Float64List _floats;
  final Int64List _ints;
  int _offset = 0;

  void writeDouble(double value) => _floats[_offset++] = value;

  void writeInt(int value) => _ints[_offset++] = value;

  void writeBool(bool value) => _ints[_offset++] = value ? 1 : 0;

  void writeDoubleList(Float64List list) {
    _ints[_offset++] = list.length;
    _floats.setAll(_offset, list);
    _offset += list.length;
  }

  void writeIntList(Int64List list) {
    _ints[_offset++] = list.length;
    _ints.setAll(_offset, list);
    _offset += list.length;
  }

  /// Writes raw bytes, assuming they are already aligned to 8 bytes.
  void writeAlignedBytes(Uint8List bytes, int lengthIn64Bits) {
    _ints[_offset++] = lengthIn64Bits;
    final view =
        Float64List.view(bytes.buffer, bytes.offsetInBytes, lengthIn64Bits);
    _floats.setAll(_offset, view);
    _offset += lengthIn64Bits;
  }

  Uint8List toBytes() => _floats.buffer.asUint8List();
}

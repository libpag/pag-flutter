class PagImageInfo {
  static const String formatRgba8888 = "rgba8888";
  static const String formatBgra8888 = "bgra8888";

  int address = 0;
  int width = 0;
  int height = 0;
  String format = formatRgba8888;

  PagImageInfo(Map<dynamic, dynamic> infos) {
    if (infos.containsKey("pixelsDataAddress")) {
      address = infos['pixelsDataAddress'];
    }
    if (infos.containsKey("pixelsDataWidth")) {
      width = infos['pixelsDataWidth'];
    }
    if (infos.containsKey("pixelsDataHeight")) {
      height = infos['pixelsDataHeight'];
    }
    if (infos.containsKey("pixelsDataFormat")) {
      format = infos['pixelsDataFormat'];
    }
  }

  @override
  String toString() {
    return "NativeImageInfo: {pixelsAddress: $address, pixelsWidth: $width,  pixelsHeight:$height, pixelsFormat: $format}";
  }
}

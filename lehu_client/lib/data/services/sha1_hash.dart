import 'dart:convert';
import 'dart:typed_data';

class Sha1Hash {
  const Sha1Hash._();

  static String hex(Uint8List bytes) {
    final message = _pad(bytes);
    var h0 = 0x67452301;
    var h1 = 0xEFCDAB89;
    var h2 = 0x98BADCFE;
    var h3 = 0x10325476;
    var h4 = 0xC3D2E1F0;

    for (var chunkOffset = 0; chunkOffset < message.length; chunkOffset += 64) {
      final w = List<int>.filled(80, 0);
      for (var i = 0; i < 16; i++) {
        final offset = chunkOffset + i * 4;
        w[i] = (message[offset] << 24) |
            (message[offset + 1] << 16) |
            (message[offset + 2] << 8) |
            message[offset + 3];
      }
      for (var i = 16; i < 80; i++) {
        w[i] = _rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
      }

      var a = h0;
      var b = h1;
      var c = h2;
      var d = h3;
      var e = h4;

      for (var i = 0; i < 80; i++) {
        final f = i < 20
            ? ((b & c) | ((~b) & d))
            : i < 40
                ? (b ^ c ^ d)
                : i < 60
                    ? ((b & c) | (b & d) | (c & d))
                    : (b ^ c ^ d);
        final k = i < 20
            ? 0x5A827999
            : i < 40
                ? 0x6ED9EBA1
                : i < 60
                    ? 0x8F1BBCDC
                    : 0xCA62C1D6;
        final temp = (_rotl(a, 5) + f + e + k + w[i]) & 0xffffffff;
        e = d;
        d = c;
        c = _rotl(b, 30);
        b = a;
        a = temp;
      }

      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
    }

    return [h0, h1, h2, h3, h4]
        .map((part) => part.toRadixString(16).padLeft(8, '0'))
        .join();
  }

  static Uint8List _pad(Uint8List input) {
    final bitLength = input.length * 8;
    final paddingLength = (56 - (input.length + 1) % 64) % 64;
    final output = Uint8List(input.length + 1 + paddingLength + 8)
      ..setAll(0, input);
    output[input.length] = 0x80;
    final lengthOffset = output.length - 8;
    for (var i = 0; i < 8; i++) {
      output[lengthOffset + i] = (bitLength >> (56 - 8 * i)) & 0xff;
    }
    return output;
  }

  static int _rotl(int value, int bits) {
    return ((value << bits) | (value >>> (32 - bits))) & 0xffffffff;
  }
}

String sha1Text(String value) =>
    Sha1Hash.hex(Uint8List.fromList(utf8.encode(value)));

import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

import 'rlp_test_vectors.dart' as data;

void main() {
  final testContent = json.decode(data.content) as Map;

  for (final key in testContent.keys) {
    test('$key', () {
      final data = testContent[key];
      final input = _mapTestData(data['in']);
      final output = data['out'] as String;

      expect(bytesToHex(encode(input), include0x: true), output);
    });
  }

  group('RLP Decode Tests', () {
    test('decode single byte string', () {
      final encoded = [0x42];
      final decoded = decode(encoded);
      expect(decoded, isA<Uint8List>());
      expect((decoded as Uint8List).toList(), equals([0x42]));
    });

    test('decode empty string', () {
      final encoded = [0x80];
      final decoded = decode(encoded);
      expect(decoded, isA<Uint8List>());
      expect((decoded as Uint8List).length, equals(0));
    });

    test('decode short string', () {
      final encoded = [0x85, 0x68, 0x65, 0x6c, 0x6c, 0x6f]; // "hello"
      final decoded = decode(encoded);
      expect(decoded, isA<Uint8List>());
      expect((decoded as Uint8List).toList(), equals([0x68, 0x65, 0x6c, 0x6c, 0x6f]));
    });

    test('decode empty list', () {
      final encoded = [0xc0];
      final decoded = decode(encoded);
      expect(decoded, isA<List>());
      expect((decoded as List).length, equals(0));
    });

    test('decode short list', () {
      final encoded = [0xc3, 0x01, 0x02, 0x03]; // [1, 2, 3]
      final decoded = decode(encoded);
      expect(decoded, isA<List>());
      final list = decoded as List;
      expect(list.length, equals(3));
      expect(list[0], isA<Uint8List>());
      expect((list[0] as Uint8List).toList(), equals([1]));
      expect((list[1] as Uint8List).toList(), equals([2]));
      expect((list[2] as Uint8List).toList(), equals([3]));
    });

    test('decode nested list', () {
      final encoded = [0xc6, 0xc2, 0x01, 0x02, 0xc2, 0x03, 0x04]; // [[1, 2], [3, 4]]
      final decoded = decode(encoded);
      expect(decoded, isA<List>());
      final list = decoded as List;
      expect(list.length, equals(2));
      expect(list[0], isA<List>());
      expect(list[1], isA<List>());
      
      // Check first nested list [1, 2]
      final firstList = list[0] as List;
      expect(firstList.length, equals(2));
      expect((firstList[0] as Uint8List).toList(), equals([1]));
      expect((firstList[1] as Uint8List).toList(), equals([2]));
      
      // Check second nested list [3, 4]
      final secondList = list[1] as List;
      expect(secondList.length, equals(2));
      expect((secondList[0] as Uint8List).toList(), equals([3]));
      expect((secondList[1] as Uint8List).toList(), equals([4]));
    });

    test('decode zero integer', () {
      final encoded = [0x80]; // 0 encoded as empty string
      final decoded = decode(encoded);
      expect(decoded, isA<Uint8List>());
      expect((decoded as Uint8List).length, equals(0));
    });

    test('round-trip encoding/decoding', () {
      final original = [1, 2, 3];
      final encoded = encode(original);
      final decoded = decode(encoded);
      expect(decoded, isA<List>());
      final list = decoded as List;
      expect(list.length, equals(3));
      expect((list[0] as Uint8List).toList(), equals([1]));
      expect((list[1] as Uint8List).toList(), equals([2]));
      expect((list[2] as Uint8List).toList(), equals([3]));
    });

    test('decode throws on empty data', () {
      expect(() => decode([]), throwsArgumentError);
    });

    test('decode throws on invalid data', () {
      expect(() => decode([0xff, 0x00]), throwsArgumentError);
    });

    test('decode throws on malformed length encoding', () {
      // Invalid long string with missing length bytes
      expect(() => decode([0xb8]), throwsArgumentError);
      
      // Invalid long list with missing length bytes  
      expect(() => decode([0xf8]), throwsArgumentError);
    });

    test('decode throws on length exceeding data', () {
      // String length exceeds available data
      expect(() => decode([0x85, 0x01, 0x02]), throwsArgumentError);
      
      // List length exceeds available data
      expect(() => decode([0xc5, 0x01, 0x02]), throwsArgumentError);
    });

    test('decode throws on excessive length encoding', () {
      // Length encoding too long (5 bytes)
      expect(() => decode([0xbb, 0x01, 0x02, 0x03, 0x04, 0x05, 0x00]), throwsArgumentError);
    });

    test('decode throws on unreasonably large length', () {
      // Length too large (2MB)
      expect(() => decode([0xbb, 0x00, 0x20, 0x00, 0x00, 0x00]), throwsArgumentError);
    });

    test('decode handles maximum valid single byte', () {
      final encoded = [0x7f];
      final decoded = decode(encoded);
      expect(decoded, isA<Uint8List>());
      expect((decoded as Uint8List).toList(), equals([0x7f]));
    });

    test('decode handles maximum valid short string', () {
      final encoded = [0xb7] + List.filled(55, 0x42);
      final decoded = decode(encoded);
      expect(decoded, isA<Uint8List>());
      expect((decoded as Uint8List).length, equals(55));
    });

    test('decode handles maximum valid short list', () {
      final encoded = [0xf7] + List.filled(55, 0x42);
      final decoded = decode(encoded);
      expect(decoded, isA<List>());
      expect((decoded as List).length, equals(55));
    });

    test('decode handles long string', () {
      final longString = List.filled(100, 0x42);
      final encoded = [0xb8, 0x64] + longString; // 0x64 = 100
      final decoded = decode(encoded);
      expect(decoded, isA<Uint8List>());
      expect((decoded as Uint8List).length, equals(100));
    });

    test('decode handles long list', () {
      final longList = List.filled(100, 0x42);
      final encoded = [0xf8, 0x64] + longList; // 0x64 = 100
      final decoded = decode(encoded);
      expect(decoded, isA<List>());
      expect((decoded as List).length, equals(100));
    });

    test('decode handles deeply nested structures', () {
      // Create a deeply nested list: [[[[1]]]]
      final original = [[[[1]]]];
      final encoded = encode(original);
      final decoded = decode(encoded);
      expect(decoded, isA<List>());
      final list = decoded as List;
      expect(list.length, equals(1));
      expect(list[0], isA<List>());
    });

    test('decode handles mixed data types in list', () {
      // List containing strings, numbers, and nested lists
      final original = ['hello', 42, [1, 2], ''];
      final encoded = encode(original);
      final decoded = decode(encoded);
      expect(decoded, isA<List>());
      final list = decoded as List;
      expect(list.length, equals(4));
    });

    test('decode handles zero-length long string', () {
      final encoded = [0xb8, 0x00]; // Long string with length 0
      final decoded = decode(encoded);
      expect(decoded, isA<Uint8List>());
      expect((decoded as Uint8List).length, equals(0));
    });

    test('decode handles zero-length long list', () {
      final encoded = [0xf8, 0x00]; // Long list with length 0
      final decoded = decode(encoded);
      expect(decoded, isA<List>());
      expect((decoded as List).length, equals(0));
    });

    test('decode handles single byte in long string encoding', () {
      // This should be encoded as short string, but test malformed data
      final encoded = [0xb8, 0x01, 0x42]; // Long string encoding for single byte
      final decoded = decode(encoded);
      expect(decoded, isA<Uint8List>());
      expect((decoded as Uint8List).toList(), equals([0x42]));
    });

    test('decode handles edge case with 0x80 prefix', () {
      final encoded = [0x80]; // Empty string
      final decoded = decode(encoded);
      expect(decoded, isA<Uint8List>());
      expect((decoded as Uint8List).length, equals(0));
    });

    test('decode handles edge case with 0xc0 prefix', () {
      final encoded = [0xc0]; // Empty list
      final decoded = decode(encoded);
      expect(decoded, isA<List>());
      expect((decoded as List).length, equals(0));
    });

    test('decode round-trip with large data', () {
      final original = List.filled(1000, 0x42);
      final encoded = encode(original);
      final decoded = decode(encoded);
      expect(decoded, isA<List>());
      expect((decoded as List).length, equals(1000));
      // Verify all elements are correct
      for (int i = 0; i < 1000; i++) {
        expect((decoded as List)[i], isA<Uint8List>());
        expect(((decoded as List)[i] as Uint8List).toList(), equals([0x42]));
      }
    });

    test('decode round-trip with complex nested structure', () {
      final original = [
        [1, 2, [3, 4]],
        'hello',
        [['nested', 'deep']],
        42,
      ];
      final encoded = encode(original);
      final decoded = decode(encoded);
      expect(decoded, isA<List>());
      final list = decoded as List;
      expect(list.length, equals(4));
    });
  });

  test('decode base64 vector 6GeEstBeAIJSCJSqGmo4NYPqqz1yjSFLjLvzGYvOBYXo1KUQAICAgIA=', () {
    // Base64 payload to decode
    const b64 = '6GeEstBeAIJSCJSqGmo4NYPqqz1yjSFLjLvzGYvOBYXo1KUQAICAgIA=';
    final bytes = base64Decode(b64);

    final decoded = decode(bytes);
    expect(decoded, isA<List>());
    final list = decoded as List;
    // Expect 9 elements (legacy tx-like layout with trailing empties)
    expect(list.length, equals(9));

    // gasLimit = 0x5208 (21000)
    // element index 2 in legacy layout [nonce, gasPrice, gasLimit, to, value, data, v, r, s]
    expect(list[2], equals(Uint8List.fromList([0x52, 0x08])));

    // to = 20-byte address 0xaa1a6a383583eaab3d728d214b8cbbf3198bce05
    expect(
      list[3],
      equals(
        Uint8List.fromList([
          0xaa, 0x1a, 0x6a, 0x38, 0x35, 0x83, 0xea, 0xab, 0x3d, 0x72,
          0x8d, 0x21, 0x4b, 0x8c, 0xbb, 0xf3, 0x19, 0x8b, 0xce, 0x05,
        ]),
      ),
    );

    // trailing v, r, s, and possibly data are empty in this vector
    expect(list[5], equals(Uint8List(0)));
    expect(list[6], equals(Uint8List(0)));
    expect(list[7], equals(Uint8List(0)));
    expect(list[8], equals(Uint8List(0)));
  });

  test('decode base64 vector to Transaction (legacy)', () {
    const b64 = '6GeEstBeAIJSCJSqGmo4NYPqqz1yjSFLjLvzGYvOBYXo1KUQAICAgIA=';
    final bytes = base64Decode(b64);

    final decoded = decode(bytes);
    expect(decoded, isA<List>());
    final list = decoded as List;

    // Extract fields as legacy: [nonce, gasPrice, gasLimit, to, value, data, v, r, s]
    int? _toInt(dynamic v) {
      if (v is List && v.isEmpty) return 0;
      if (v is int) return v;
      if (v is List) {
        BigInt acc = BigInt.zero;
        for (final b in v.cast<int>()) {
          acc = (acc << 8) + BigInt.from(b);
        }
        return acc.toInt();
      }
      return null;
    }

    BigInt? _toBigInt(dynamic v) {
      if (v is List && v.isEmpty) return BigInt.zero;
      if (v is int) return BigInt.from(v);
      if (v is List) {
        BigInt acc = BigInt.zero;
        for (final b in v.cast<int>()) {
          acc = (acc << 8) + BigInt.from(b);
        }
        return acc;
      }
      return null;
    }

    Uint8List _toBytes(dynamic v) {
      if (v is List) return Uint8List.fromList(v.cast<int>());
      if (v is int) return Uint8List.fromList([v]);
      return Uint8List(0);
    }

    final nonce = _toInt(list[0]);
    final gasPrice = _toBigInt(list[1]);
    final gasLimit = _toInt(list[2]);
    final toBytes = _toBytes(list[3]);
    final value = _toBigInt(list[4]);
    final dataBytes = _toBytes(list[5]);

    final tx = Transaction(
      nonce: nonce,
      gasPrice: gasPrice != null ? EtherAmount.inWei(gasPrice) : null,
      maxGas: gasLimit,
      to: toBytes.isNotEmpty ? EthereumAddress(toBytes) : null,
      value: value != null ? EtherAmount.inWei(value) : null,
      data: dataBytes,
    );

    expect(tx.nonce, equals(103));
    expect(tx.gasPrice?.getInWei, equals(BigInt.from(3000000000)));
    expect(tx.maxGas, equals(21000));
    expect(tx.to?.hex, equals('0xaa1a6a383583eaab3d728d214b8cbbf3198bce05'));
    expect(tx.value?.getInWei, equals(BigInt.from(1000000000000)));
    expect(tx.data, equals(Uint8List(0)));
  });
}

dynamic _mapTestData(dynamic data) {
  if (data is String && data.startsWith('#')) {
    return BigInt.parse(data.substring(1));
  }

  return data;
}

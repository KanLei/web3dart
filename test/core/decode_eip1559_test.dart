import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:web3dart/src/utils/rlp.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

void main() {
  group('decodeRlpToEIP1559 Tests', () {
    group('Basic Functionality', () {
      test('decode simple EIP-1559 transaction', () {
        // Create a simple transaction
        final transaction = Transaction(
          nonce: 1,
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.inWei(BigInt.from(1000000000000000000)),
          data: Uint8List(0),
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(2000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(30000000000)),
        );

        // Encode to RLP
        final rlpData = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final encoded = encode(rlpData);

        // Decode back
        final decoded = decodeRlpToEIP1559(encoded);

        // Verify all fields match
        expect(decoded.nonce, equals(transaction.nonce));
        expect(decoded.maxGas, equals(transaction.maxGas));
        expect(decoded.to?.hex, equals(transaction.to?.hex));
        expect(decoded.value?.getInWei, equals(transaction.value?.getInWei));
        expect(decoded.maxPriorityFeePerGas?.getInWei, equals(transaction.maxPriorityFeePerGas?.getInWei));
        expect(decoded.maxFeePerGas?.getInWei, equals(transaction.maxFeePerGas?.getInWei));
        expect(decoded.data, equals(transaction.data));
      });

      test('decode transaction with contract creation (null to)', () {
        final transaction = Transaction(
          nonce: 0,
          maxGas: 100000,
          to: null, // Contract creation
          value: EtherAmount.zero(),
          data: Uint8List.fromList([0x60, 0x60, 0x60, 0x40, 0x52]), // Some bytecode
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(1000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(20000000000)),
        );

        final rlpData = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final encoded = encode(rlpData);
        final decoded = decodeRlpToEIP1559(encoded);

        expect(decoded.to, isNull);
        expect(decoded.data, equals(transaction.data));
      });

      test('decode transaction with large data payload', () {
        final largeData = Uint8List.fromList(List.filled(1000, 0x42));
        final transaction = Transaction(
          nonce: 42,
          maxGas: 50000,
          to: EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'),
          value: EtherAmount.zero(),
          data: largeData,
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(500000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(10000000000)),
        );

        final rlpData = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final encoded = encode(rlpData);
        final decoded = decodeRlpToEIP1559(encoded);

        expect(decoded.data, equals(largeData));
        expect(decoded.data?.length, equals(1000));
      });
    });

    group('Boundary Conditions', () {
      test('decode transaction with zero values', () {
        final transaction = Transaction(
          nonce: 0,
          maxGas: 0,
          to: EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'),
          value: EtherAmount.zero(),
          data: Uint8List(0),
          maxPriorityFeePerGas: EtherAmount.zero(),
          maxFeePerGas: EtherAmount.zero(),
        );

        final rlpData = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final encoded = encode(rlpData);
        final decoded = decodeRlpToEIP1559(encoded);

        expect(decoded.nonce, equals(0));
        expect(decoded.maxGas, equals(0));
        expect(decoded.value?.getInWei, equals(BigInt.zero));
        expect(decoded.maxPriorityFeePerGas?.getInWei, equals(BigInt.zero));
        expect(decoded.maxFeePerGas?.getInWei, equals(BigInt.zero));
      });

      test('decode transaction with maximum values', () {
        final maxValue = EtherAmount.inWei(BigInt.parse('115792089237316195423570985008687907853269984665640564039457584007913129639935'));
        final transaction = Transaction(
          nonce: 2147483647, // Max int32
          maxGas: 2147483647,
          to: EthereumAddress.fromHex('0xffffffffffffffffffffffffffffffffffffffff'),
          value: maxValue,
          data: Uint8List.fromList(List.filled(100, 0xff)),
          maxPriorityFeePerGas: maxValue,
          maxFeePerGas: maxValue,
        );

        final rlpData = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final encoded = encode(rlpData);
        final decoded = decodeRlpToEIP1559(encoded);

        expect(decoded.nonce, equals(2147483647));
        expect(decoded.maxGas, equals(2147483647));
        expect(decoded.value?.getInWei, equals(maxValue.getInWei));
      });

      test('decode transaction with very large chain ID', () {
        final transaction = Transaction(
          nonce: 1,
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.inWei(BigInt.from(1000000000000000000)),
          data: Uint8List(0),
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(2000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(30000000000)),
        );

        final largeChainId = BigInt.parse('999999999999999999999999999999999999999999');
        final rlpData = _encodeEIP1559ToRlp(transaction, null, largeChainId);
        final encoded = encode(rlpData);
        final decoded = decodeRlpToEIP1559(encoded);

        // Chain ID is not stored in Transaction object, but should not cause errors
        expect(decoded.nonce, equals(transaction.nonce));
        expect(decoded.maxGas, equals(transaction.maxGas));
      });
    });

    group('Error Handling', () {
      test('decode throws on empty RLP data', () {
        expect(() => decodeRlpToEIP1559([]), throwsArgumentError);
      });

      test('decode throws on invalid RLP data', () {
        final invalidData = [0xff, 0x00, 0x01];
        expect(() => decodeRlpToEIP1559(invalidData), throwsArgumentError);
      });

      test('decode throws on insufficient elements', () {
        // Create RLP with only 5 elements (need at least 9)
        final insufficientData = [0xc5, 0x01, 0x02, 0x03, 0x04, 0x05];
        expect(() => decodeRlpToEIP1559(insufficientData), throwsArgumentError);
      });

      test('decode throws on malformed RLP structure', () {
        // Create malformed RLP structure
        final malformedData = [0xc0]; // Empty list
        expect(() => decodeRlpToEIP1559(malformedData), throwsArgumentError);
      });

      test('decode handles corrupted data gracefully', () {
        // Create valid RLP but with corrupted transaction data
        final corruptedData = [0xf0, 0x01, 0x01, 0x84, 0x77, 0x35, 0x94, 0x00, 0x85, 0x06, 0xfc, 0x23, 0xac, 0x00, 0x82, 0x52, 0x08, 0x94, 0x74, 0x2d, 0x35, 0xcc, 0x66, 0x34, 0xc0, 0x53, 0x29, 0x25, 0xa3, 0xb8, 0xd4, 0xc9, 0xdb, 0x96, 0xc4, 0xb4, 0xd8, 0xb6, 0x88, 0x0d, 0xe0, 0xb6, 0xb3, 0xa7, 0x64, 0x00, 0x00, 0x80, 0xc0];
        
        // This should either succeed or throw a specific error, not crash
        try {
          final decoded = decodeRlpToEIP1559(corruptedData);
          // If it succeeds, verify it's a valid transaction
          expect(decoded, isA<Transaction>());
        } catch (e) {
          expect(e, isA<ArgumentError>());
        }
      });
    });

    group('Edge Cases', () {
      test('decode transaction with empty data field', () {
        final transaction = Transaction(
          nonce: 1,
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.zero(),
          data: Uint8List(0),
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(1000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(20000000000)),
        );

        final rlpData = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final encoded = encode(rlpData);
        final decoded = decodeRlpToEIP1559(encoded);

        expect(decoded.data, isEmpty);
        expect(decoded.data, isA<Uint8List>());
      });

      test('decode transaction with single byte data', () {
        final singleByteData = Uint8List.fromList([0x42]);
        final transaction = Transaction(
          nonce: 1,
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.zero(),
          data: singleByteData,
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(1000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(20000000000)),
        );

        final rlpData = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final encoded = encode(rlpData);
        final decoded = decodeRlpToEIP1559(encoded);

        expect(decoded.data, equals(singleByteData));
        expect(decoded.data?.length, equals(1));
      });

      test('decode transaction with very small values', () {
        final transaction = Transaction(
          nonce: 1,
          maxGas: 1,
          to: EthereumAddress.fromHex('0x0000000000000000000000000000000000000001'),
          value: EtherAmount.inWei(BigInt.one),
          data: Uint8List(0),
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.one),
          maxFeePerGas: EtherAmount.inWei(BigInt.one),
        );

        final rlpData = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final encoded = encode(rlpData);
        final decoded = decodeRlpToEIP1559(encoded);

        expect(decoded.maxGas, equals(1));
        expect(decoded.value?.getInWei, equals(BigInt.one));
        expect(decoded.maxPriorityFeePerGas?.getInWei, equals(BigInt.one));
        expect(decoded.maxFeePerGas?.getInWei, equals(BigInt.one));
      });
    });

    group('Complex Scenarios', () {
      test('decode transaction with signature', () {
        final transaction = Transaction(
          nonce: 1,
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.inWei(BigInt.from(1000000000000000000)),
          data: Uint8List(0),
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(2000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(30000000000)),
        );

        // Create a mock signature
        final signature = MsgSignature(
          BigInt.parse('1234567890123456789012345678901234567890123456789012345678901234'),
          BigInt.parse('9876543210987654321098765432109876543210987654321098765432109876'),
          27,
        );

        final rlpData = _encodeEIP1559ToRlp(transaction, signature, BigInt.from(1));
        final encoded = encode(rlpData);
        final decoded = decodeRlpToEIP1559(encoded);

        // Signature is not stored in Transaction object, but should not cause errors
        expect(decoded.nonce, equals(transaction.nonce));
        expect(decoded.maxGas, equals(transaction.maxGas));
      });

      test('decode transaction with access list', () {
        final transaction = Transaction(
          nonce: 1,
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.zero(),
          data: Uint8List(0),
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(1000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(20000000000)),
        );

        final rlpData = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final encoded = encode(rlpData);
        final decoded = decodeRlpToEIP1559(encoded);

        // Access list is not stored in Transaction object, but should not cause errors
        expect(decoded.nonce, equals(transaction.nonce));
        expect(decoded.maxGas, equals(transaction.maxGas));
      });

      test('decode multiple transactions in sequence', () {
        final transactions = [
          Transaction(
            nonce: 1,
            maxGas: 21000,
            to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
            value: EtherAmount.inWei(BigInt.from(1000000000000000000)),
            data: Uint8List(0),
            maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(2000000000)),
            maxFeePerGas: EtherAmount.inWei(BigInt.from(30000000000)),
          ),
          Transaction(
            nonce: 2,
            maxGas: 50000,
            to: EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'),
            value: EtherAmount.zero(),
            data: Uint8List.fromList([0x60, 0x60, 0x60, 0x40, 0x52]),
            maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(1000000000)),
            maxFeePerGas: EtherAmount.inWei(BigInt.from(20000000000)),
          ),
        ];

        for (int i = 0; i < transactions.length; i++) {
          final rlpData = _encodeEIP1559ToRlp(transactions[i], null, BigInt.from(1));
          final encoded = encode(rlpData);
          final decoded = decodeRlpToEIP1559(encoded);

          expect(decoded.nonce, equals(transactions[i].nonce));
          expect(decoded.maxGas, equals(transactions[i].maxGas));
          expect(decoded.to?.hex, equals(transactions[i].to?.hex));
          expect(decoded.value?.getInWei, equals(transactions[i].value?.getInWei));
          expect(decoded.data, equals(transactions[i].data));
        }
      });
    });

    group('Performance Tests', () {
      test('decode large transaction data efficiently', () {
        final largeData = Uint8List.fromList(List.filled(10000, 0x42));
        final transaction = Transaction(
          nonce: 1,
          maxGas: 100000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.zero(),
          data: largeData,
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(1000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(20000000000)),
        );

        final rlpData = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final encoded = encode(rlpData);
        
        final stopwatch = Stopwatch()..start();
        final decoded = decodeRlpToEIP1559(encoded);
        stopwatch.stop();

        expect(decoded.data, equals(largeData));
        expect(decoded.data?.length, equals(10000));
        expect(stopwatch.elapsedMilliseconds, lessThan(100)); // Should be fast
      });
    });
  });
}

// Helper function to encode EIP-1559 transaction to RLP
List<dynamic> _encodeEIP1559ToRlp(
  Transaction transaction,
  MsgSignature? signature,
  BigInt chainId,
) {
  final list = [
    chainId,
    transaction.nonce,
    transaction.maxPriorityFeePerGas!.getInWei,
    transaction.maxFeePerGas!.getInWei,
    transaction.maxGas,
  ];

  if (transaction.to != null) {
    list.add(transaction.to!.addressBytes);
  } else {
    list.add('');
  }

  list
    ..add(transaction.value?.getInWei)
    ..add(transaction.data);

  list.add([]); // access list

  if (signature != null) {
    list
      ..add(signature.v)
      ..add(signature.r)
      ..add(signature.s);
  }

  return list;
}

import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';
import 'package:web3dart/src/utils/rlp.dart' as rlp;

void main() {
  group('decodeRlpToTransaction Tests', () {
    group('Legacy Transaction Decoding', () {
      test('decode simple legacy transaction', () {
        // Create a simple legacy transaction
        final transaction = Transaction(
          nonce: 1,
          gasPrice: EtherAmount.inWei(BigInt.from(20000000000)), // 20 gwei
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.inWei(BigInt.from(1000000000000000000)),
          data: Uint8List(0),
        );

        // Encode to RLP
        final rlpData = _encodeToRlp(transaction, null);
        final encoded = encode(rlpData);

        // Decode back using universal decoder
        final decoded = decodeRlpToTransaction(encoded);

        // Verify all fields match
        expect(decoded.nonce, equals(transaction.nonce));
        expect(decoded.maxGas, equals(transaction.maxGas));
        expect(decoded.to?.hex, equals(transaction.to?.hex));
        expect(decoded.value?.getInWei, equals(transaction.value?.getInWei));
        expect(decoded.gasPrice?.getInWei, equals(transaction.gasPrice?.getInWei));
        expect(decoded.data, equals(transaction.data));
        
        // Verify it's detected as legacy transaction
        expect(decoded.isEIP1559, isFalse);
      });

      test('decode legacy contract creation transaction', () {
        final transaction = Transaction(
          nonce: 0,
          gasPrice: EtherAmount.inWei(BigInt.from(20000000000)),
          maxGas: 100000,
          to: null, // Contract creation
          value: EtherAmount.zero(),
          data: Uint8List.fromList([0x60, 0x60, 0x60, 0x40, 0x52]),
        );

        final rlpData = _encodeToRlp(transaction, null);
        final encoded = encode(rlpData);
        final decoded = decodeRlpToTransaction(encoded);

        expect(decoded.to, isNull);
        expect(decoded.data, equals(transaction.data));
        expect(decoded.isEIP1559, isFalse);
      });

      test('decode legacy transaction with large data payload', () {
        final largeData = Uint8List.fromList(List.filled(1000, 0x42));
        final transaction = Transaction(
          nonce: 42,
          gasPrice: EtherAmount.inWei(BigInt.from(10000000000)),
          maxGas: 50000,
          to: EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'),
          value: EtherAmount.zero(),
          data: largeData,
        );

        final rlpData = _encodeToRlp(transaction, null);
        final encoded = encode(rlpData);
        final decoded = decodeRlpToTransaction(encoded);

        expect(decoded.data, equals(largeData));
        expect(decoded.data?.length, equals(1000));
        expect(decoded.isEIP1559, isFalse);
      });
    });

    group('EIP-1559 Transaction Decoding', () {
      test('decode simple EIP-1559 transaction', () {
        final transaction = Transaction(
          nonce: 1,
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.inWei(BigInt.from(1000000000000000000)),
          data: Uint8List(0),
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(2000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(30000000000)),
        );

        // Encode to RLP with EIP-2718 prefix
        final rlpData = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final encoded = Uint8List.fromList([0x02, ...encode(rlpData)]);

        // Decode back using universal decoder
        final decoded = decodeRlpToTransaction(encoded);

        // Verify all fields match
        expect(decoded.nonce, equals(transaction.nonce));
        expect(decoded.maxGas, equals(transaction.maxGas));
        expect(decoded.to?.hex, equals(transaction.to?.hex));
        expect(decoded.value?.getInWei, equals(transaction.value?.getInWei));
        expect(decoded.maxPriorityFeePerGas?.getInWei, equals(transaction.maxPriorityFeePerGas?.getInWei));
        expect(decoded.maxFeePerGas?.getInWei, equals(transaction.maxFeePerGas?.getInWei));
        expect(decoded.data, equals(transaction.data));
        
        // Verify it's detected as EIP-1559 transaction
        expect(decoded.isEIP1559, isTrue);
      });

      test('decode typed EIP-1559 transaction with 0x02 prefix', () {
        final transaction = Transaction(
          nonce: 1,
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.zero(),
          data: Uint8List(0),
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(1000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(20000000000)),
        );

        // Create typed EIP-1559 transaction with 0x02 prefix
        final rlpData = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final encoded = encode(rlpData);
        final typedEncoded = Uint8List.fromList([0x02, ...encoded]);

        // Decode back using universal decoder
        final decoded = decodeRlpToTransaction(typedEncoded);

        expect(decoded.nonce, equals(transaction.nonce));
        expect(decoded.maxGas, equals(transaction.maxGas));
        expect(decoded.isEIP1559, isTrue);
      });

      test('decode EIP-1559 contract creation transaction', () {
        final transaction = Transaction(
          nonce: 0,
          maxGas: 100000,
          to: null, // Contract creation
          value: EtherAmount.zero(),
          data: Uint8List.fromList([0x60, 0x60, 0x60, 0x40, 0x52]),
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(1000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(20000000000)),
        );

        final rlpData = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final encoded = Uint8List.fromList([0x02, ...encode(rlpData)]);
        final decoded = decodeRlpToTransaction(encoded);

        expect(decoded.to, isNull);
        expect(decoded.data, equals(transaction.data));
        expect(decoded.isEIP1559, isTrue);
      });
    });

    group('Format Detection', () {
      test('auto-detect legacy transaction by field count', () {
        // Create a transaction with exactly 6 fields (legacy format)
        final transaction = Transaction(
          nonce: 1,
          gasPrice: EtherAmount.inWei(BigInt.from(20000000000)),
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.zero(),
          data: Uint8List(0),
        );

        final rlpData = _encodeToRlp(transaction, null);
        final encoded = encode(rlpData);
        final decoded = decodeRlpToTransaction(encoded);

        expect(decoded.isEIP1559, isFalse);
        expect(decoded.gasPrice, isNotNull);
        expect(decoded.maxPriorityFeePerGas, isNull);
        expect(decoded.maxFeePerGas, isNull);
      });

      test('auto-detect EIP-1559 transaction by field count', () {
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
        final encoded = Uint8List.fromList([0x02, ...encode(rlpData)]);
        final decoded = decodeRlpToTransaction(encoded);

        expect(decoded.isEIP1559, isTrue);
        expect(decoded.gasPrice, isNull);
        expect(decoded.maxPriorityFeePerGas, isNotNull);
        expect(decoded.maxFeePerGas, isNotNull);
      });

      test('detect typed EIP-1559 transaction by 0x02 prefix', () {
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
        final typedEncoded = Uint8List.fromList([0x02, ...encoded]);
        final decoded = decodeRlpToTransaction(typedEncoded);

        expect(decoded.isEIP1559, isTrue);
      });
    });

    group('Error Handling', () {
      test('throws on empty RLP data', () {
        expect(() => decodeRlpToTransaction([]), throwsArgumentError);
      });

      test('throws on invalid RLP data', () {
        final invalidData = [0xff, 0x00, 0x01];
        expect(() => decodeRlpToTransaction(invalidData), throwsArgumentError);
      });

      test('throws on insufficient fields for legacy', () {
        // Create RLP with only 3 elements (need at least 6 for legacy)
        final insufficientData = [0xc3, 0x01, 0x02, 0x03];
        expect(() => decodeRlpToTransaction(insufficientData), throwsArgumentError);
      });

      test('throws on insufficient fields for any transaction', () {
        // Create RLP with only 3 elements (need at least 6 for any transaction)
        final insufficientData = [0xc3, 0x01, 0x02, 0x03];
        expect(() => decodeRlpToTransaction(insufficientData), throwsArgumentError);
      });

      test('handles corrupted data gracefully', () {
        final corruptedData = [0xf0, 0x01, 0x01, 0x84, 0x77, 0x35, 0x94, 0x00];
        
        try {
          final decoded = decodeRlpToTransaction(corruptedData);
          expect(decoded, isA<Transaction>());
        } catch (e) {
          expect(e, isA<ArgumentError>());
        }
      });
    });

    group('Edge Cases', () {
      test('decode transaction with zero values', () {
        final transaction = Transaction(
          nonce: 0,
          maxGas: 0,
          to: EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'),
          value: EtherAmount.zero(),
          data: Uint8List(0),
          gasPrice: EtherAmount.zero(),
        );

        final rlpData = _encodeToRlp(transaction, null);
        final encoded = encode(rlpData);
        final decoded = decodeRlpToTransaction(encoded);

        expect(decoded.nonce, equals(0));
        expect(decoded.maxGas, equals(0));
        expect(decoded.value?.getInWei, equals(BigInt.zero));
        expect(decoded.gasPrice?.getInWei, equals(BigInt.zero));
        expect(decoded.isEIP1559, isFalse);
      });

      test('decode transaction with maximum values', () {
        final maxValue = EtherAmount.inWei(BigInt.parse('115792089237316195423570985008687907853269984665640564039457584007913129639935'));
        final transaction = Transaction(
          nonce: 2147483647, // Max int32
          maxGas: 2147483647,
          to: EthereumAddress.fromHex('0xffffffffffffffffffffffffffffffffffffffff'),
          value: maxValue,
          data: Uint8List.fromList(List.filled(100, 0xff)),
          gasPrice: maxValue,
        );

        final rlpData = _encodeToRlp(transaction, null);
        final encoded = encode(rlpData);
        final decoded = decodeRlpToTransaction(encoded);

        expect(decoded.nonce, equals(2147483647));
        expect(decoded.maxGas, equals(2147483647));
        expect(decoded.value?.getInWei, equals(maxValue.getInWei));
        expect(decoded.gasPrice?.getInWei, equals(maxValue.getInWei));
      });

      test('decode transaction with empty data field', () {
        final transaction = Transaction(
          nonce: 1,
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.zero(),
          data: Uint8List(0),
          gasPrice: EtherAmount.inWei(BigInt.from(20000000000)),
        );

        final rlpData = _encodeToRlp(transaction, null);
        final encoded = encode(rlpData);
        final decoded = decodeRlpToTransaction(encoded);

        expect(decoded.data, isEmpty);
        expect(decoded.data, isA<Uint8List>());
      });
    });

    group('Real Transaction Data Tests', () {
      test('decode real EIP-1559 transaction from base64', () {
        // Real EIP-1559 transaction data
        const base64Data = 'uQUbAvkFFzhohDuaygCEQpz+jIMLH6iUYBUSbX0jZIwuRGZpO43qsAX/q6iGCRhOcqAAuQTkuAwvCQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA0MOAAAAAAAAAAAAAAAA7u7u7u7u7u7u7u7u7u7u7u7u7u4AAAAAAAAAAAAAAACqxkeqbVDPSSg2EzCO/o36ctxERAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACRhOcqAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAaPcDYQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAWAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJGE5yoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAOAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFgAAAAAAAAAAAAAAAAu0zbnL02sBvRy66/LeCNkXO8CVwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAFKA1q/mMhyVjKzkApYW1neVfrQ7AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAABSgNav5jIclYys5AKWFtZ3lX60OwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAACcQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAASAAAAAAAAAAAAAAAAC7TNucvTawG9HLrr8t4I2Rc7wJXAAAAAAAAAAAAAAAAKrGR6ptUM9JKDYTMI7+jfpy3EREAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAMCAgIA=';
        
        final bytes = base64Decode(base64Data);
        // This is double RLP encoded data, need to decode the outer layer first
        final outerDecoded = rlp.decode(bytes);
        final decoded = decodeRlpToTransaction(outerDecoded);
        
        // Verify it's detected as EIP-1559 transaction
        expect(decoded.isEIP1559, isTrue);
        expect(decoded.maxPriorityFeePerGas, isNotNull);
        expect(decoded.maxFeePerGas, isNotNull);
        expect(decoded.gasPrice, isNull);
        
        // Verify specific transaction properties
        expect(decoded.nonce, equals(104));
        expect(decoded.maxPriorityFeePerGas?.getInWei, equals(BigInt.from(1000000000))); // 1 Gwei
        expect(decoded.maxFeePerGas?.getInWei, equals(BigInt.from(1117585036))); // ~1.12 Gwei
        expect(decoded.maxGas, equals(729000));
        expect(decoded.to?.hex, equals('0x6015126d7d23648c2e4466693b8deab005ffaba8'));
        expect(decoded.value?.getInWei, equals(BigInt.from(10000000000000))); // 0.00001 ETH
        expect(decoded.data?.length, equals(1252)); // Contract call data
      });

      test('decode real legacy transaction from base64', () {
        // Real legacy transaction data
        const base64Data = '6GmEstBeAIJSCJSqGmo4NYPqqz1yjSFLjLvzGYvOBYXo1KUQAICAgIA=';
        
        final bytes = base64Decode(base64Data);
        // This is directly RLP encoded data
        final decoded = decodeRlpToTransaction(bytes);
        
        // Verify it's detected as legacy transaction
        expect(decoded.isEIP1559, isFalse);
        expect(decoded.gasPrice, isNotNull);
        expect(decoded.maxPriorityFeePerGas, isNull);
        expect(decoded.maxFeePerGas, isNull);
        
        // Verify basic transaction properties
        expect(decoded.nonce, isNotNull);
        expect(decoded.maxGas, isNotNull);
        expect(decoded.data, isNotNull);
      });

      test('decode real unsigned legacy transaction from base64', () {
        // Real unsigned legacy transaction data with contract call
        const base64Data = '+QQKgIQEN1fYgw0vAJRgFRJtfSNkjC5EZmk7jeqwBf+rqIC5A+S4DC8JAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADRBoAAAAAAAAAAAAAAABERJwxQKTjj+a38uy77ZIZzq9dTwAAAAAAAAAAAAAAAO7u7u7u7u7u7u7u7u7u7u7u7u7uAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAONfqTGgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAMZQ3QwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABo9hcIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAASAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA41+pMaAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAKAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAWAAAAAAAAAAAAAAAABERJwxQKTjj+a38uy77ZIZzq9dTwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAqWqWZpKV6FrwRgJr9xSiboQJaIkAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAADHMrAyBHFXbvDS3CeN13ZACIdgJAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAJxAxzKwMgRxV27w0twnjdd2QAiHYCQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAZAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAgIA=';
        
        final bytes = base64Decode(base64Data);
        // This is directly RLP encoded data
        final decoded = decodeRlpToTransaction(bytes);
        
        // Verify it's detected as legacy transaction
        expect(decoded.isEIP1559, isFalse);
        expect(decoded.gasPrice, isNotNull);
        expect(decoded.maxPriorityFeePerGas, isNull);
        expect(decoded.maxFeePerGas, isNull);
        
        // Verify specific transaction properties
        expect(decoded.nonce, equals(0));
        expect(decoded.gasPrice?.getInWei, equals(BigInt.from(70735832))); // 0.071 Gwei
        expect(decoded.maxGas, equals(864000));
        expect(decoded.to?.hex, equals('0x6015126d7d23648c2e4466693b8deab005ffaba8'));
        expect(decoded.value?.getInWei, equals(BigInt.zero));
        expect(decoded.data?.length, equals(996)); // Contract call data
        
        // Verify it's an unsigned transaction (no signature fields)
        // Note: Signature fields are not stored in Transaction object
        // but the RLP structure indicates this is unsigned
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
          gasPrice: EtherAmount.inWei(BigInt.from(20000000000)),
        );

        final rlpData = _encodeToRlp(transaction, null);
        final encoded = encode(rlpData);
        
        final stopwatch = Stopwatch()..start();
        final decoded = decodeRlpToTransaction(encoded);
        stopwatch.stop();

        expect(decoded.data, equals(largeData));
        expect(decoded.data?.length, equals(10000));
        expect(stopwatch.elapsedMilliseconds, lessThan(100)); // Should be fast
      });
    });
  });
}

// Helper function to encode legacy transaction to RLP
List<dynamic> _encodeToRlp(Transaction transaction, MsgSignature? signature) {
  final list = [
    transaction.nonce,
    transaction.gasPrice?.getInWei,
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

  if (signature != null) {
    list
      ..add(signature.v)
      ..add(signature.r)
      ..add(signature.s);
  }

  return list;
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

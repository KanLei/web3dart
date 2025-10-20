import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:web3dart/src/utils/rlp.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

void main() {
  group('signTransactionBytes Tests', () {
    late EthPrivateKey privateKey;
    late Credentials credentials;

    setUp(() {
      // Create a test private key
      privateKey = EthPrivateKey.fromHex('0x1234567890123456789012345678901234567890123456789012345678901234');
      credentials = privateKey;
    });

    group('EIP-1559 Transaction Signing', () {
      test('sign EIP-1559 transaction from bytes', () {
        // Create an unsigned EIP-1559 transaction
        final transaction = Transaction(
          nonce: 1,
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.inWei(BigInt.from(1000000000000000000)),
          data: Uint8List(0),
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(2000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(30000000000)),
        );

        // Encode as unsigned RLP
        final unsignedRlp = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final unsignedBytes = Uint8List.fromList(encode(unsignedRlp));

        // Sign the transaction bytes
        final signedBytes = signTransactionBytes(
          unsignedBytes,
          credentials,
          chainId: 1,
          isEIP1559: true,
        );

        // Verify the signed transaction is different from unsigned
        expect(signedBytes, isNot(equals(unsignedBytes)));
        expect(signedBytes.length, greaterThan(unsignedBytes.length));

        // Decode and verify the signed transaction
        final decoded = decodeRlpToEIP1559(signedBytes);
        expect(decoded.nonce, equals(transaction.nonce));
        expect(decoded.maxGas, equals(transaction.maxGas));
        expect(decoded.to?.hex, equals(transaction.to?.hex));
        expect(decoded.value?.getInWei, equals(transaction.value?.getInWei));
      });

      test('sign EIP-1559 contract creation transaction', () {
        final transaction = Transaction(
          nonce: 0,
          maxGas: 100000,
          to: null, // Contract creation
          value: EtherAmount.zero(),
          data: Uint8List.fromList([0x60, 0x60, 0x60, 0x40, 0x52]),
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(1000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(20000000000)),
        );

        final unsignedRlp = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final unsignedBytes = Uint8List.fromList(encode(unsignedRlp));

        final signedBytes = signTransactionBytes(
          unsignedBytes,
          credentials,
          chainId: 1,
          isEIP1559: true,
        );

        expect(signedBytes, isNot(equals(unsignedBytes)));
        expect(signedBytes.length, greaterThan(unsignedBytes.length));

        final decoded = decodeRlpToEIP1559(signedBytes);
        expect(decoded.to, isNull);
        expect(decoded.data, equals(transaction.data));
      });

      test('sign EIP-1559 transaction with large data', () {
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

        final unsignedRlp = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final unsignedBytes = Uint8List.fromList(encode(unsignedRlp));

        final signedBytes = signTransactionBytes(
          unsignedBytes,
          credentials,
          chainId: 1,
          isEIP1559: true,
        );

        expect(signedBytes, isNot(equals(unsignedBytes)));
        expect(signedBytes.length, greaterThan(unsignedBytes.length));

        final decoded = decodeRlpToEIP1559(signedBytes);
        expect(decoded.data, equals(largeData));
        expect(decoded.data?.length, equals(1000));
      });
    });

    group('Legacy Transaction Signing', () {
      test('sign legacy transaction from bytes', () {
        final transaction = Transaction(
          nonce: 1,
          gasPrice: EtherAmount.inWei(BigInt.from(20000000000)), // 20 gwei
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.inWei(BigInt.from(1000000000000000000)),
          data: Uint8List(0),
        );

        // Encode as unsigned RLP
        final unsignedRlp = _encodeToRlp(transaction, null);
        final unsignedBytes = Uint8List.fromList(encode(unsignedRlp));

        // Sign the transaction bytes
        final signedBytes = signTransactionBytes(
          unsignedBytes,
          credentials,
          chainId: 1,
          isEIP1559: false,
        );

        // Verify the signed transaction is different from unsigned
        expect(signedBytes, isNot(equals(unsignedBytes)));
        expect(signedBytes.length, greaterThan(unsignedBytes.length));

        // Decode and verify the signed transaction
        final decoded = decode(unsignedBytes);
        expect(decoded, isA<List>());
      });

      test('sign legacy contract creation transaction', () {
        final transaction = Transaction(
          nonce: 0,
          gasPrice: EtherAmount.inWei(BigInt.from(20000000000)),
          maxGas: 100000,
          to: null, // Contract creation
          value: EtherAmount.zero(),
          data: Uint8List.fromList([0x60, 0x60, 0x60, 0x40, 0x52]),
        );

        final unsignedRlp = _encodeToRlp(transaction, null);
        final unsignedBytes = Uint8List.fromList(encode(unsignedRlp));

        final signedBytes = signTransactionBytes(
          unsignedBytes,
          credentials,
          chainId: 1,
          isEIP1559: false,
        );

        expect(signedBytes, isNot(equals(unsignedBytes)));
        expect(signedBytes.length, greaterThan(unsignedBytes.length));
      });
    });

    group('Error Handling', () {
      test('sign throws on empty bytes', () {
        expect(
          () => signTransactionBytes(Uint8List(0), credentials),
          throwsArgumentError,
        );
      });

      test('sign throws on invalid RLP data', () {
        final invalidBytes = Uint8List.fromList([0xff, 0x00, 0x01]);
        expect(
          () => signTransactionBytes(invalidBytes, credentials),
          throwsArgumentError,
        );
      });

      test('sign throws on insufficient EIP-1559 fields', () {
        // Create RLP with only 5 elements (need at least 9 for EIP-1559)
        final insufficientData = [0xc5, 0x01, 0x02, 0x03, 0x04, 0x05];
        final bytes = Uint8List.fromList(encode(insufficientData));
        
        expect(
          () => signTransactionBytes(bytes, credentials, isEIP1559: true),
          throwsArgumentError,
        );
      });

      test('sign throws on insufficient legacy fields', () {
        // Create RLP with only 3 elements (need at least 6 for legacy)
        final insufficientData = [0xc3, 0x01, 0x02, 0x03];
        final bytes = Uint8List.fromList(encode(insufficientData));
        
        expect(
          () => signTransactionBytes(bytes, credentials, isEIP1559: false),
          throwsArgumentError,
        );
      });

      test('sign handles malformed transaction data gracefully', () {
        // Create malformed RLP structure
        final malformedData = [0xc0]; // Empty list
        final bytes = Uint8List.fromList(encode(malformedData));
        
        expect(
          () => signTransactionBytes(bytes, credentials),
          throwsArgumentError,
        );
      });
    });

    group('Edge Cases', () {
      test('sign transaction with zero values', () {
        final transaction = Transaction(
          nonce: 0,
          maxGas: 0,
          to: EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'),
          value: EtherAmount.zero(),
          data: Uint8List(0),
          maxPriorityFeePerGas: EtherAmount.zero(),
          maxFeePerGas: EtherAmount.zero(),
        );

        final unsignedRlp = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final unsignedBytes = Uint8List.fromList(encode(unsignedRlp));

        final signedBytes = signTransactionBytes(
          unsignedBytes,
          credentials,
          chainId: 1,
          isEIP1559: true,
        );

        expect(signedBytes, isNot(equals(unsignedBytes)));
        expect(signedBytes.length, greaterThan(unsignedBytes.length));
      });

      test('sign transaction with maximum values', () {
        final maxValue = EtherAmount.inWei(BigInt.parse('115792089237316195423570985008687907853269984665640564039457584007913129639935'));
        final transaction = Transaction(
          nonce: 2147483647,
          maxGas: 2147483647,
          to: EthereumAddress.fromHex('0xffffffffffffffffffffffffffffffffffffffff'),
          value: maxValue,
          data: Uint8List.fromList(List.filled(100, 0xff)),
          maxPriorityFeePerGas: maxValue,
          maxFeePerGas: maxValue,
        );

        final unsignedRlp = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final unsignedBytes = Uint8List.fromList(encode(unsignedRlp));

        final signedBytes = signTransactionBytes(
          unsignedBytes,
          credentials,
          chainId: 1,
          isEIP1559: true,
        );

        expect(signedBytes, isNot(equals(unsignedBytes)));
        expect(signedBytes.length, greaterThan(unsignedBytes.length));
      });

      test('sign transaction with different chain IDs', () {
        final transaction = Transaction(
          nonce: 1,
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.zero(),
          data: Uint8List(0),
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(1000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(20000000000)),
        );

        // Test with different chain IDs
        for (final chainId in [1, 3, 42, 137, 250]) {
          final unsignedRlp = _encodeEIP1559ToRlp(transaction, null, BigInt.from(chainId));
          final unsignedBytes = Uint8List.fromList(encode(unsignedRlp));

          final signedBytes = signTransactionBytes(
            unsignedBytes,
            credentials,
            chainId: chainId,
            isEIP1559: true,
          );

          expect(signedBytes, isNot(equals(unsignedBytes)));
          expect(signedBytes.length, greaterThan(unsignedBytes.length));
        }
      });
    });

    group('Extreme Value Tests', () {
      test('sign transaction with maximum BigInt values', () {
        final maxBigInt = BigInt.parse('115792089237316195423570985008687907853269984665640564039457584007913129639935');
        final transaction = Transaction(
          nonce: 2147483647,
          maxGas: 2147483647,
          to: EthereumAddress.fromHex('0xffffffffffffffffffffffffffffffffffffffff'),
          value: EtherAmount.inWei(maxBigInt),
          data: Uint8List.fromList(List.filled(1000, 0xff)),
          maxPriorityFeePerGas: EtherAmount.inWei(maxBigInt),
          maxFeePerGas: EtherAmount.inWei(maxBigInt),
        );

        final unsignedRlp = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final unsignedBytes = Uint8List.fromList(encode(unsignedRlp));

        final signedBytes = signTransactionBytes(unsignedBytes, credentials);
        expect(signedBytes, isNot(equals(unsignedBytes)));
        expect(signedBytes.length, greaterThan(unsignedBytes.length));
      });

      test('sign transaction with minimum non-zero values', () {
        final transaction = Transaction(
          nonce: 1,
          maxGas: 1,
          to: EthereumAddress.fromHex('0x0000000000000000000000000000000000000001'),
          value: EtherAmount.inWei(BigInt.one),
          data: Uint8List.fromList([0x01]),
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.one),
          maxFeePerGas: EtherAmount.inWei(BigInt.one),
        );

        final unsignedRlp = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final unsignedBytes = Uint8List.fromList(encode(unsignedRlp));

        final signedBytes = signTransactionBytes(unsignedBytes, credentials);
        expect(signedBytes, isNot(equals(unsignedBytes)));
        expect(signedBytes.length, greaterThan(unsignedBytes.length));
      });

      test('sign transaction with very large chain ID', () {
        final largeChainId = BigInt.parse('999999999999999999999999999999999999999999');
        final transaction = Transaction(
          nonce: 1,
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.zero(),
          data: Uint8List(0),
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(1000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(20000000000)),
        );

        final unsignedRlp = _encodeEIP1559ToRlp(transaction, null, largeChainId);
        final unsignedBytes = Uint8List.fromList(encode(unsignedRlp));

        final signedBytes = signTransactionBytes(unsignedBytes, credentials, chainId: 1);
        expect(signedBytes, isNot(equals(unsignedBytes)));
        expect(signedBytes.length, greaterThan(unsignedBytes.length));
      });

      test('sign transaction with maximum data size', () {
        final maxData = Uint8List.fromList(List.filled(100000, 0x42)); // 100KB
        final transaction = Transaction(
          nonce: 1,
          maxGas: 1000000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.zero(),
          data: maxData,
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(1000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(20000000000)),
        );

        final unsignedRlp = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final unsignedBytes = Uint8List.fromList(encode(unsignedRlp));

        final signedBytes = signTransactionBytes(unsignedBytes, credentials);
        expect(signedBytes, isNot(equals(unsignedBytes)));
        expect(signedBytes.length, greaterThan(unsignedBytes.length));
      });
    });

    group('Edge Case Boundary Tests', () {
      test('sign transaction with empty data field', () {
        final transaction = Transaction(
          nonce: 1,
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.zero(),
          data: Uint8List(0),
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(1000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(20000000000)),
        );

        final unsignedRlp = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final unsignedBytes = Uint8List.fromList(encode(unsignedRlp));

        final signedBytes = signTransactionBytes(unsignedBytes, credentials);
        expect(signedBytes, isNot(equals(unsignedBytes)));
        expect(signedBytes.length, greaterThan(unsignedBytes.length));
      });

      test('sign transaction with single byte data', () {
        final transaction = Transaction(
          nonce: 1,
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.zero(),
          data: Uint8List.fromList([0x42]),
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(1000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(20000000000)),
        );

        final unsignedRlp = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final unsignedBytes = Uint8List.fromList(encode(unsignedRlp));

        final signedBytes = signTransactionBytes(unsignedBytes, credentials);
        expect(signedBytes, isNot(equals(unsignedBytes)));
        expect(signedBytes.length, greaterThan(unsignedBytes.length));
      });

      test('sign transaction with all zero addresses', () {
        final transaction = Transaction(
          nonce: 1,
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'),
          value: EtherAmount.zero(),
          data: Uint8List(0),
          maxPriorityFeePerGas: EtherAmount.zero(),
          maxFeePerGas: EtherAmount.zero(),
        );

        final unsignedRlp = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final unsignedBytes = Uint8List.fromList(encode(unsignedRlp));

        final signedBytes = signTransactionBytes(unsignedBytes, credentials);
        expect(signedBytes, isNot(equals(unsignedBytes)));
        expect(signedBytes.length, greaterThan(unsignedBytes.length));
      });

      test('sign transaction with maximum address', () {
        final transaction = Transaction(
          nonce: 1,
          maxGas: 21000,
          to: EthereumAddress.fromHex('0xffffffffffffffffffffffffffffffffffffffff'),
          value: EtherAmount.zero(),
          data: Uint8List(0),
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(1000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(20000000000)),
        );

        final unsignedRlp = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final unsignedBytes = Uint8List.fromList(encode(unsignedRlp));

        final signedBytes = signTransactionBytes(unsignedBytes, credentials);
        expect(signedBytes, isNot(equals(unsignedBytes)));
        expect(signedBytes.length, greaterThan(unsignedBytes.length));
      });
    });

    group('Advanced Error Handling Tests', () {
      test('sign throws on corrupted RLP with valid structure', () {
        // Create valid RLP structure but with corrupted data
        final corruptedData = [
          1, // chainId
          1, // nonce
          2000000000, // maxPriorityFeePerGas
          30000000000, // maxFeePerGas
          21000, // gasLimit
          [0x74, 0x2d, 0x35, 0xcc, 0x66, 0x34, 0xc0, 0x53, 0x29, 0x25, 0xa3, 0xb8, 0xd4, 0xc9, 0xdb, 0x96, 0xc4, 0xb4, 0xd8, 0xb6], // to
          1000000000000000000, // value
          [], // data
          [], // accessList
        ];
        
        final bytes = Uint8List.fromList(encode(corruptedData));
        
        // This should either succeed or throw a specific error, not crash
        try {
          final signedBytes = signTransactionBytes(bytes, credentials);
          expect(signedBytes, isNot(equals(bytes)));
        } catch (e) {
          expect(e, isA<ArgumentError>());
        }
      });

      test('sign handles malformed address gracefully', () {
        // Create transaction with malformed address (wrong length)
        final malformedAddress = [0x74, 0x2d, 0x35]; // Too short
        final transaction = Transaction(
          nonce: 1,
          maxGas: 21000,
          to: null, // Will be set manually in RLP
          value: EtherAmount.zero(),
          data: Uint8List(0),
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(1000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(20000000000)),
        );

        // Manually create RLP with malformed address
        final rlpData = [
          1, // chainId
          1, // nonce
          1000000000, // maxPriorityFeePerGas
          20000000000, // maxFeePerGas
          21000, // gasLimit
          malformedAddress, // malformed to address
          0, // value
          [], // data
          [], // accessList
        ];
        
        final bytes = Uint8List.fromList(encode(rlpData));
        
        expect(
          () => signTransactionBytes(bytes, credentials),
          throwsArgumentError,
        );
      });

      test('sign handles extremely large nonce values', () {
        final transaction = Transaction(
          nonce: 0x7FFFFFFF, // Max int32
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.zero(),
          data: Uint8List(0),
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(1000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(20000000000)),
        );

        final unsignedRlp = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final unsignedBytes = Uint8List.fromList(encode(unsignedRlp));

        final signedBytes = signTransactionBytes(unsignedBytes, credentials);
        expect(signedBytes, isNot(equals(unsignedBytes)));
        expect(signedBytes.length, greaterThan(unsignedBytes.length));
      });

      test('sign handles zero chain ID gracefully', () {
        final transaction = Transaction(
          nonce: 1,
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.zero(),
          data: Uint8List(0),
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(1000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(20000000000)),
        );

        // Create RLP with zero chain ID using proper encoding
        final unsignedRlp = _encodeEIP1559ToRlp(transaction, null, BigInt.zero);
        final unsignedBytes = Uint8List.fromList(encode(unsignedRlp));
        
        // Zero chain ID should be handled gracefully
        final signedBytes = signTransactionBytes(unsignedBytes, credentials);
        expect(signedBytes, isNot(equals(unsignedBytes)));
        expect(signedBytes.length, greaterThan(unsignedBytes.length));
      });
    });

    group('Default Parameter Tests', () {
      test('sign uses EIP-1559 as default', () {
        final transaction = Transaction(
          nonce: 1,
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.zero(),
          data: Uint8List(0),
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(1000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(20000000000)),
        );

        final unsignedRlp = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final unsignedBytes = Uint8List.fromList(encode(unsignedRlp));

        // Test default behavior (should use EIP-1559)
        final signedBytes = signTransactionBytes(unsignedBytes, credentials);
        expect(signedBytes, isNot(equals(unsignedBytes)));
        expect(signedBytes.length, greaterThan(unsignedBytes.length));
      });

      test('sign explicitly uses legacy when specified', () {
        final transaction = Transaction(
          nonce: 1,
          gasPrice: EtherAmount.inWei(BigInt.from(20000000000)),
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.zero(),
          data: Uint8List(0),
        );

        final unsignedRlp = _encodeToRlp(transaction, null);
        final unsignedBytes = Uint8List.fromList(encode(unsignedRlp));

        // Test explicit legacy mode
        final signedBytes = signTransactionBytes(
          unsignedBytes, 
          credentials, 
          isEIP1559: false,
        );
        expect(signedBytes, isNot(equals(unsignedBytes)));
        expect(signedBytes.length, greaterThan(unsignedBytes.length));
      });
    });

    group('Performance Tests', () {
      test('sign large transaction efficiently', () {
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

        final unsignedRlp = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
        final unsignedBytes = Uint8List.fromList(encode(unsignedRlp));

        final stopwatch = Stopwatch()..start();
        final signedBytes = signTransactionBytes(unsignedBytes, credentials);
        stopwatch.stop();

        expect(signedBytes, isNot(equals(unsignedBytes)));
        expect(signedBytes.length, greaterThan(unsignedBytes.length));
        expect(stopwatch.elapsedMilliseconds, lessThan(200)); // Should be fast
      });

      test('sign multiple transactions in batch', () {
        final transactions = List.generate(10, (i) => Transaction(
          nonce: i + 1,
          maxGas: 21000,
          to: EthereumAddress.fromHex('0x742d35cc6634c0532925a3b8d4c9db96c4b4d8b6'),
          value: EtherAmount.inWei(BigInt.from(1000000000000000000)),
          data: Uint8List(0),
          maxPriorityFeePerGas: EtherAmount.inWei(BigInt.from(1000000000)),
          maxFeePerGas: EtherAmount.inWei(BigInt.from(20000000000)),
        ));

        final stopwatch = Stopwatch()..start();
        
        for (final transaction in transactions) {
          final unsignedRlp = _encodeEIP1559ToRlp(transaction, null, BigInt.from(1));
          final unsignedBytes = Uint8List.fromList(encode(unsignedRlp));
          final signedBytes = signTransactionBytes(unsignedBytes, credentials);
          
          expect(signedBytes, isNot(equals(unsignedBytes)));
          expect(signedBytes.length, greaterThan(unsignedBytes.length));
        }
        
        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(500)); // Should be fast for batch
      });
    });
  });
}

// Helper functions
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

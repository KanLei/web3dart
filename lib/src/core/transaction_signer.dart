part of 'package:web3dart/web3dart.dart';

class _SigningInput {
  _SigningInput({
    required this.transaction,
    required this.credentials,
    this.chainId,
  });

  final Transaction transaction;
  final Credentials credentials;
  final int? chainId;
}

Future<_SigningInput> _fillMissingData({
  required Credentials credentials,
  required Transaction transaction,
  int? chainId,
  bool loadChainIdFromNetwork = false,
  Web3Client? client,
}) async {
  if (loadChainIdFromNetwork && chainId != null) {
    throw ArgumentError(
      "You can't specify loadChainIdFromNetwork and specify a custom chain id!",
    );
  }

  final sender = transaction.from ?? credentials.address;
  var gasPrice = transaction.gasPrice;

  if (client == null &&
      (transaction.nonce == null ||
          transaction.maxGas == null ||
          loadChainIdFromNetwork ||
          (!transaction.isEIP1559 && gasPrice == null))) {
    throw ArgumentError('Client is required to perform network actions');
  }

  if (!transaction.isEIP1559 && gasPrice == null) {
    gasPrice = await client!.getGasPrice();
  }

  var maxFeePerGas = transaction.maxFeePerGas;
  var maxPriorityFeePerGas = transaction.maxPriorityFeePerGas;

  if (transaction.isEIP1559) {
    maxPriorityFeePerGas ??= await _getMaxPriorityFeePerGas();
    maxFeePerGas ??= await _getMaxFeePerGas(
      client!,
      maxPriorityFeePerGas.getInWei,
    );
  }

  final nonce = transaction.nonce ??
      await client!
          .getTransactionCount(sender, atBlock: const BlockNum.pending());

  final maxGas = transaction.maxGas ??
      await client!
          .estimateGas(
            sender: sender,
            to: transaction.to,
            data: transaction.data,
            value: transaction.value,
            gasPrice: gasPrice,
            maxPriorityFeePerGas: maxPriorityFeePerGas,
            maxFeePerGas: maxFeePerGas,
          )
          .then((bigInt) => bigInt.toInt());

  // apply default values to null fields
  final modifiedTransaction = transaction.copyWith(
    value: transaction.value ?? EtherAmount.zero(),
    maxGas: maxGas,
    from: sender,
    data: transaction.data ?? Uint8List(0),
    gasPrice: gasPrice,
    nonce: nonce,
    maxPriorityFeePerGas: maxPriorityFeePerGas,
    maxFeePerGas: maxFeePerGas,
  );

  int resolvedChainId;
  if (!loadChainIdFromNetwork) {
    resolvedChainId = chainId!;
  } else {
    resolvedChainId = await client!.getNetworkId();
  }

  return _SigningInput(
    transaction: modifiedTransaction,
    credentials: credentials,
    chainId: resolvedChainId,
  );
}

Uint8List prependTransactionType(int type, Uint8List transaction) {
  return Uint8List(transaction.length + 1)
    ..[0] = type
    ..setAll(1, transaction);
}

Uint8List signTransactionRaw(
  Transaction transaction,
  Credentials c, {
  int? chainId = 1,
}) {
  final encoded = transaction.getUnsignedSerialized(chainId: chainId);
  final signature = c.signToEcSignature(encoded, chainId: chainId, isEIP1559: transaction.isEIP1559);

  if (transaction.isEIP1559 && chainId != null) {
    return uint8ListFromList(
      rlp.encode(
        _encodeEIP1559ToRlp(transaction, signature, BigInt.from(chainId)),
      ),
    );
  }
  return uint8ListFromList(rlp.encode(_encodeToRlp(transaction, signature)));
}

/// Signs a transaction from raw bytes and returns the signed transaction bytes
/// 
/// This method takes raw transaction bytes (RLP-encoded unsigned transaction)
/// and signs them using the provided credentials. It supports both legacy
/// transactions and EIP-1559 transactions.
/// 
/// [transactionBytes] - Raw RLP-encoded unsigned transaction bytes
/// [credentials] - The credentials to use for signing
/// [chainId] - The chain ID for the transaction (default: 1)
/// [isEIP1559] - Whether this is an EIP-1559 transaction (default: true)
/// 
/// Returns the signed transaction bytes ready for broadcast.
/// Throws [ArgumentError] if the transaction bytes are invalid.
Uint8List signTransactionBytes(
  Uint8List transactionBytes,
  Credentials credentials, {
  int? chainId = 1,
  bool isEIP1559 = true,
}) {
  try {
    // Detect typed transaction prefix for EIP-1559 (0x02)
    Uint8List bytesToDecode = transactionBytes;
    bool typedEip1559 = false;
    if (transactionBytes.isNotEmpty && transactionBytes[0] == 0x02) {
      typedEip1559 = true;
      bytesToDecode = Uint8List.sublistView(transactionBytes, 1);
    }

    // Decode the unsigned transaction bytes to get the transaction data
    final decoded = rlp.decode(bytesToDecode);
    
    if (decoded is! List) {
      throw ArgumentError('Invalid transaction bytes: expected RLP list');
    }
    
    final list = decoded;
    
    if (isEIP1559 || typedEip1559) {
      return _signEIP1559FromBytes(list, credentials, chainId);
    } else {
      return _signLegacyFromBytes(list, credentials, chainId);
    }
    
  } catch (e) {
    throw ArgumentError('Failed to sign transaction bytes: $e');
  }
}

/// Signs an EIP-1559 transaction from decoded RLP data
Uint8List _signEIP1559FromBytes(List<dynamic> rlpData, Credentials credentials, int? chainId) {
  if (rlpData.length < 9) {
    throw ArgumentError('Invalid EIP-1559 transaction: insufficient fields');
  }
  
  // Extract transaction fields from RLP data
  final nonce = _extractBigInt(rlpData[1]);
  final maxPriorityFeePerGas = _extractBigInt(rlpData[2]);
  final maxFeePerGas = _extractBigInt(rlpData[3]);
  final gasLimit = _extractBigInt(rlpData[4]);
  
  // Extract recipient address
  EthereumAddress? to;
  if (rlpData[5] is List && rlpData[5].isNotEmpty) {
    final addressBytes = _extractBytes(rlpData[5]);
    if (addressBytes.isNotEmpty) {
      to = EthereumAddress(addressBytes);
    }
  }
  
  // Extract value and data
  final value = _extractBigInt(rlpData[6]);
  final data = _extractBytes(rlpData[7]);
  
  // Create transaction object
  final transaction = Transaction(
    nonce: nonce?.toInt(),
    maxGas: gasLimit?.toInt(),
    to: to,
    value: value != null ? EtherAmount.inWei(value) : EtherAmount.zero(),
    data: data,
    maxPriorityFeePerGas: maxPriorityFeePerGas != null 
        ? EtherAmount.inWei(maxPriorityFeePerGas) 
        : null,
    maxFeePerGas: maxFeePerGas != null 
        ? EtherAmount.inWei(maxFeePerGas) 
        : null,
  );
  
  // Get the unsigned serialized transaction for signing
  final unsignedSerialized = transaction.getUnsignedSerialized(chainId: chainId);
  
  // Sign the transaction
  final signature = credentials.signToEcSignature(
    unsignedSerialized, 
    chainId: chainId, 
    isEIP1559: true,
  );
  
  // Encode the signed transaction
  final signedRlp = _encodeEIP1559ToRlp(transaction, signature, BigInt.from(chainId ?? 1));
  return uint8ListFromList(rlp.encode(signedRlp));
}

/// Signs a legacy transaction from decoded RLP data
Uint8List _signLegacyFromBytes(List<dynamic> rlpData, Credentials credentials, int? chainId) {
  if (rlpData.length < 6) {
    throw ArgumentError('Invalid legacy transaction: insufficient fields');
  }
  
  // Extract transaction fields from RLP data
  final nonce = _extractBigInt(rlpData[0]);
  final gasPrice = _extractBigInt(rlpData[1]);
  final gasLimit = _extractBigInt(rlpData[2]);
  
  // Extract recipient address
  EthereumAddress? to;
  if (rlpData[3] is List && rlpData[3].isNotEmpty) {
    final addressBytes = _extractBytes(rlpData[3]);
    if (addressBytes.isNotEmpty) {
      to = EthereumAddress(addressBytes);
    }
  }
  
  // Extract value and data
  final value = _extractBigInt(rlpData[4]);
  final data = _extractBytes(rlpData[5]);
  
  // Create transaction object
  final transaction = Transaction(
    nonce: nonce?.toInt(),
    gasPrice: gasPrice != null ? EtherAmount.inWei(gasPrice) : null,
    maxGas: gasLimit?.toInt(),
    to: to,
    value: value != null ? EtherAmount.inWei(value) : EtherAmount.zero(),
    data: data,
  );
  
  // Get the unsigned serialized transaction for signing
  final unsignedSerialized = transaction.getUnsignedSerialized(chainId: chainId);
  
  // Sign the transaction
  final signature = credentials.signToEcSignature(
    unsignedSerialized, 
    chainId: chainId, 
    isEIP1559: false,
  );
  
  // Encode the signed transaction
  final signedRlp = _encodeToRlp(transaction, signature);
  return uint8ListFromList(rlp.encode(signedRlp));
}

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

Future<EtherAmount> _getMaxPriorityFeePerGas() {
  // We may want to compute this more accurately in the future,
  // using the formula "check if the base fee is correct".
  // See: https://eips.ethereum.org/EIPS/eip-1559
  return Future.value(EtherAmount.inWei(BigInt.from(1000000000)));
}

// Max Fee = (2 * Base Fee) + Max Priority Fee
Future<EtherAmount> _getMaxFeePerGas(
  Web3Client client,
  BigInt maxPriorityFeePerGas,
) async {
  final blockInformation = await client.getBlockInformation();
  final baseFeePerGas = blockInformation.baseFeePerGas;

  if (baseFeePerGas == null) {
    return EtherAmount.zero();
  }

  return EtherAmount.inWei(
    baseFeePerGas.getInWei * BigInt.from(2) + maxPriorityFeePerGas,
  );
}

/// Decodes RLP-encoded EIP-1559 transaction data back to a Transaction object
/// 
/// This function parses the RLP-encoded transaction data and reconstructs
/// the original Transaction object with all its fields populated.
/// 
/// The RLP structure for EIP-1559 transactions is:
/// [chainId, nonce, maxPriorityFeePerGas, maxFeePerGas, gasLimit, to, value, data, accessList, v, r, s]
/// 
/// Returns a [Transaction] object with all fields populated from the RLP data.
/// Throws [ArgumentError] if the RLP data is invalid or malformed.
Transaction decodeRlpToEIP1559(List<int> rlpData) {
  try {
    // Handle typed EIP-1559 (0x02) prefix if present
    List<int> toDecode = rlpData;
    if (rlpData.isNotEmpty && rlpData[0] == 0x02) {
      toDecode = rlpData.sublist(1);
    }
    // Decode the RLP data
    final decoded = rlp.decode(toDecode);
    
    if (decoded is! List || decoded.length < 9) {
      throw ArgumentError('Invalid RLP data: expected list with at least 9 elements');
    }
    
    final list = decoded;
    
    // Extract basic transaction fields
    final nonce = _extractBigInt(list[1]);
    final maxPriorityFeePerGas = _extractBigInt(list[2]);
    final maxFeePerGas = _extractBigInt(list[3]);
    final gasLimit = _extractBigInt(list[4]);
    
    // Extract recipient address
    EthereumAddress? to;
    if (list[5] is List && list[5].isNotEmpty) {
      final addressBytes = _extractBytes(list[5]);
      if (addressBytes.isNotEmpty) {
        to = EthereumAddress(addressBytes);
      }
    }
    
    // Extract value
    final value = _extractBigInt(list[6]);
    
    // Extract data
    final data = _extractBytes(list[7]);
    
    // Extract access list (currently not used in Transaction class)
    // final accessList = list[8] as List;
    
    // Extract signature if present (currently not used in return value)
    if (list.length >= 12) {
      final v = _extractBigInt(list[9]);
      final r = _extractBigInt(list[10]);
      final s = _extractBigInt(list[11]);
      
      if (v != null && r != null && s != null) {
        // Signature is available but not stored in Transaction object
        // Could be used for signature verification in the future
      }
    }
    
    // Create and return the transaction
    return Transaction(
      nonce: nonce?.toInt(),
      maxGas: gasLimit?.toInt(),
      to: to,
      value: value != null ? EtherAmount.inWei(value) : EtherAmount.zero(),
      data: data,
      maxPriorityFeePerGas: maxPriorityFeePerGas != null 
          ? EtherAmount.inWei(maxPriorityFeePerGas) 
          : null,
      maxFeePerGas: maxFeePerGas != null 
          ? EtherAmount.inWei(maxFeePerGas) 
          : null,
    );
    
  } catch (e) {
    throw ArgumentError('Failed to decode RLP data: $e');
  }
}

/// Extracts a BigInt from RLP decoded data
BigInt? _extractBigInt(dynamic data) {
  if (data == null) return null;
  
  if (data is List) {
    if (data.isEmpty) return BigInt.zero;
    // Convert bytes to BigInt
    return _bytesToBigInt(data.cast<int>());
  }
  
  if (data is int) {
    return BigInt.from(data);
  }
  
  return null;
}

/// Extracts bytes from RLP decoded data
Uint8List _extractBytes(dynamic data) {
  if (data == null) return Uint8List(0);
  
  if (data is List) {
    return Uint8List.fromList(data.cast<int>());
  }
  
  if (data is int) {
    return Uint8List.fromList([data]);
  }
  
  return Uint8List(0);
}

/// Converts a byte array to BigInt
BigInt _bytesToBigInt(List<int> bytes) {
  if (bytes.isEmpty) return BigInt.zero;
  
  BigInt result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) + BigInt.from(byte);
  }
  return result;
}

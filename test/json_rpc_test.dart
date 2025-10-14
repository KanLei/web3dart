
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:web3dart/json_rpc.dart';

final uri = Uri.parse('url');

void main() {
  late Dio dio;

  setUp(() {
    dio = Dio();
  });

  test('query gas price', () async {
    final resp = await JsonRPC('url', dio).call('eth_gasPrice', []);
    print(resp.result);
  });

  test('query block number', () async {
    final resp = await JsonRPC('url', dio).call('eth_blockNumber', []);
    print(resp.result);
  });

  test('query balance', () async {
    final resp = await JsonRPC('url', dio).call('eth_getBalance', ['0x0000000000000000000000000000000000000000', 'latest']);
    print(resp.result);
  });
  
}

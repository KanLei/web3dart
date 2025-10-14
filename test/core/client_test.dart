import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:web3dart/web3dart.dart';

void main() {
  test('getClientVersion', () async {
    final web3 = Web3Client('', Dio());
    addTearDown(web3.dispose);

    expect(web3.getClientVersion(), completion('dart-web3dart-test'));
  });
}

import 'package:clashmiao/features/proxy/application/row_order.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _order(List<String> sorted, List<String>? shown, bool frozen) =>
    stableRowOrder(
      sorted: sorted,
      keyOf: (s) => s,
      shown: shown,
      frozen: frozen,
    );

void main() {
  test('不冻结：直接按排序结果', () {
    expect(_order(['b', 'a', 'c'], ['a', 'b', 'c'], false), ['b', 'a', 'c']);
  });

  test('第一次展示（没有上次的顺序）：即使冻结也按排序结果', () {
    expect(_order(['b', 'a'], null, true), ['b', 'a']);
  });

  test('冻结：保持上次的相对顺序', () {
    expect(_order(['c', 'b', 'a'], ['a', 'b', 'c'], true), ['a', 'b', 'c']);
  });

  test('冻结：新出现的接在后面（按排序结果的顺序），已经不在的去掉', () {
    expect(_order(['e', 'c', 'd', 'a'], ['a', 'b', 'c'], true), [
      'a',
      'c',
      'e',
      'd',
    ]);
  });

  test('不改动入参', () {
    final sorted = ['b', 'a'];
    final shown = ['a', 'b'];
    _order(sorted, shown, true);
    expect(sorted, ['b', 'a']);
    expect(shown, ['a', 'b']);
  });
}

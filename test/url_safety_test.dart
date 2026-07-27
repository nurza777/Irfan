import 'package:flutter_test/flutter_test.dart';
import 'package:irfan/services/url_safety.dart';

void main() {
  test('разрешены только http/https', () {
    expect(isSafeMediaUrl('https://cdn.example.com/a.mp4'), isTrue);
    expect(isSafeMediaUrl('http://178.104.206.100:8090/hls/x.m3u8'), isTrue);

    // Опасные/произвольные схемы — запрещены.
    expect(isSafeMediaUrl('tel:+996700000000'), isFalse);
    expect(isSafeMediaUrl('mailto:a@b.kg'), isFalse);
    expect(isSafeMediaUrl('file:///etc/passwd'), isFalse);
    expect(isSafeMediaUrl('javascript:alert(1)'), isFalse);
    expect(isSafeMediaUrl('myapp://open?x=1'), isFalse);
    expect(isSafeMediaUrl(''), isFalse);
    expect(isSafeMediaUrl('   '), isFalse);
    expect(isSafeMediaUrl('/relative/path.mp4'), isFalse);
    expect(isSafeMediaUrl('https://'), isFalse); // нет хоста
  });
}

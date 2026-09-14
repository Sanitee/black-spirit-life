import 'package:bdo_craft_planner_flutter/data/market/market_session_cookies.dart';
import 'package:flutter_test/flutter_test.dart';

// Synthetic headers only; no client, socket, browser, profile, or live cookie.
void main() {
  final eu = Uri.parse('https://eu.market.example.test/api/orders');
  final initial = DateTime.utc(2026, 9, 11, 12);
  late DateTime now;
  late MarketSessionCookies jar;

  setUp(() {
    now = initial;
    jar = MarketSessionCookies(utcNow: () => now);
  });

  void store(String value, {Uri? uri}) =>
      jar.store(uri ?? eu, {'set-cookie': value});

  test('starts empty and returns only cookie pairs, never attributes', () {
    expect(jar.cookieHeader(eu), isNull);
    store('session=first; Path=/; Secure; HttpOnly; SameSite=Lax');
    expect(jar.cookieHeader(eu), 'session=first');
  });

  test('combined headers preserve Expires commas and equals in values', () {
    store(
      'session=base64==; Expires=Sat, 12 Sep 2026 12:00:00 GMT; Path=/, '
      'visitor=opaque=a=b; Path=/; HttpOnly, region=eu; Path=/',
    );
    expect(
      jar.cookieHeader(eu),
      'session=base64==; visitor=opaque=a=b; region=eu',
    );
  });

  test('separates a new cookie immediately after an Expires date', () {
    store('first=one; Expires=Sat, 12 Sep 2026 12:00:00 GMT,next=two');
    expect(jar.cookieHeader(eu), 'first=one; next=two');
  });

  test(
    'accepts mixed-case headers, attributes, host and explicit default port',
    () {
      jar.store(Uri.parse('https://EU.MARKET.EXAMPLE.TEST:443/api/orders'), {
        'Set-Cookie': 'one=1; pAtH=/; dOmAiN=.MARKET.EXAMPLE.TEST',
        'SET-COOKIE': 'two=2; PATH=/',
        'cookie': 'untrusted=not-a-response-cookie',
      });
      expect(jar.cookieHeader(eu), 'one=1; two=2');
    },
  );

  test('cookies never cross region, subdomain, scheme or port', () {
    store('session=eu; Domain=.market.example.test; Path=/');
    for (final other in [
      'https://na.market.example.test/api/orders',
      'https://child.eu.market.example.test/api/orders',
      'http://eu.market.example.test/api/orders',
      'https://eu.market.example.test:8443/api/orders',
      'https://market.example.test/api/orders',
    ]) {
      expect(jar.cookieHeader(Uri.parse(other)), isNull, reason: other);
    }
    store(
      'session=na; Domain=.market.example.test; Path=/',
      uri: Uri.parse('https://na.market.example.test/api/orders'),
    );
    expect(jar.cookieHeader(eu), 'session=eu');
    expect(
      jar.cookieHeader(Uri.parse('https://na.market.example.test/api/orders')),
      'session=na',
    );
  });

  test('rejects foreign, child, label-suffix and malformed domains', () {
    for (final domain in [
      'other.test',
      'na.market.example.test',
      'child.eu.market.example.test',
      'arket.example.test',
      'test',
      '..market.example.test',
      'market.example.test.',
      '*.example.test',
    ]) {
      store('session=no; Domain=$domain; Path=/');
      expect(jar.cookieHeader(eu), isNull, reason: domain);
    }
  });

  test('host-only and explicit same-host updates replace the same key', () {
    store('session=one; Path=/');
    store('session=two; Domain=eu.market.example.test; Path=/');
    expect(jar.cookieHeader(eu), 'session=two');
  });

  test(
    'parent-domain and host-only cookies can coexist but stay first-party',
    () {
      store(
        'session=host; Path=/, session=parent; Domain=market.example.test; Path=/',
      );
      expect(jar.cookieHeader(eu), 'session=host; session=parent');
      expect(
        jar.cookieHeader(Uri.parse('https://na.market.example.test/')),
        isNull,
      );
    },
  );

  test('default path is the response directory, with segment boundaries', () {
    store('session=value');
    expect(
      jar.cookieHeader(Uri.parse('https://eu.market.example.test/api')),
      'session=value',
    );
    expect(
      jar.cookieHeader(Uri.parse('https://eu.market.example.test/api/more')),
      'session=value',
    );
    expect(
      jar.cookieHeader(Uri.parse('https://eu.market.example.test/apis')),
      isNull,
    );
    expect(
      jar.cookieHeader(Uri.parse('https://eu.market.example.test/')),
      isNull,
    );
  });

  test('missing and invalid Path default correctly; root path covers all', () {
    store('invalid=one; Path=relative, blank=two; Path=');
    expect(jar.cookieHeader(eu), 'invalid=one; blank=two');
    expect(
      jar.cookieHeader(Uri.parse('https://eu.market.example.test/else')),
      isNull,
    );
    store('root=three', uri: Uri.parse('https://eu.market.example.test'));
    expect(
      jar.cookieHeader(Uri.parse('https://eu.market.example.test/else')),
      'root=three',
    );
  });

  test(
    'longer paths are first, equal paths retain original creation order',
    () {
      store(
        'same=root; Path=/, peer=first; Path=/api, same=deep; Path=/api/orders',
      );
      store('same=updated; Path=/');
      expect(jar.cookieHeader(eu), 'same=deep; peer=first; same=updated');
      store('later=second; Path=/api');
      store('peer=updated; Path=/api');
      expect(
        jar.cookieHeader(eu),
        'same=deep; peer=updated; later=second; same=updated',
      );
    },
  );

  test(
    'a trailing cookie path slash does not match the parent without slash',
    () {
      store('session=yes; Path=/api/');
      expect(jar.cookieHeader(eu), 'session=yes');
      expect(
        jar.cookieHeader(Uri.parse('https://eu.market.example.test/api')),
        isNull,
      );
    },
  );

  test('Max-Age overrides past Expires and expires at the exact boundary', () {
    store(
      'session=one; Max-Age=10; Expires=Thu, 10 Sep 2026 12:00:00 GMT; Path=/',
    );
    now = initial.add(const Duration(seconds: 9, milliseconds: 999));
    expect(jar.cookieHeader(eu), 'session=one');
    now = initial.add(const Duration(seconds: 10));
    expect(jar.cookieHeader(eu), isNull);
  });

  test('Expires alone is honored and session cookies remain without expiry', () {
    store(
      'dated=one; Expires=Fri, 11 Sep 2026 12:00:01 GMT; Path=/, session=two; Path=/',
    );
    now = initial.add(const Duration(seconds: 1));
    expect(jar.cookieHeader(eu), 'session=two');
    now = DateTime.utc(2036);
    expect(jar.cookieHeader(eu), 'session=two');
  });

  test('zero and negative Max-Age delete despite future Expires', () {
    for (final age in ['0', '-1', '-999']) {
      store('session=value; Path=/');
      store(
        'session=; Max-Age=$age; Expires=Sat, 12 Sep 2026 12:00:00 GMT; Path=/',
      );
      expect(jar.cookieHeader(eu), isNull, reason: age);
    }
  });

  test(
    'expiry deletion removes only matching origin, name, domain and path',
    () {
      store('session=root; Path=/, session=api; Path=/api');
      store('session=; Expires=Thu, 10 Sep 2026 12:00:00 GMT; Path=/api');
      expect(jar.cookieHeader(eu), 'session=root');
      store('session=; Max-Age=0; Domain=market.example.test; Path=/');
      expect(jar.cookieHeader(eu), 'session=root');
    },
  );

  test('updating Max-Age restarts expiry from that response receipt', () {
    store('session=one; Max-Age=5; Path=/');
    now = initial.add(const Duration(seconds: 4));
    store('session=two; Max-Age=5; Path=/');
    now = initial.add(const Duration(seconds: 8));
    expect(jar.cookieHeader(eu), 'session=two');
    now = initial.add(const Duration(seconds: 9));
    expect(jar.cookieHeader(eu), isNull);
  });

  test(
    'huge valid Max-Age is bounded without integer or DateTime overflow',
    () {
      store('session=one; Max-Age=9223372036854775807; Path=/');
      expect(jar.cookieHeader(eu), 'session=one');
    },
  );

  test('Secure cookies cannot be acquired over HTTP', () {
    final http = Uri.parse('http://eu.market.example.test/api/orders');
    store('secure=no; Secure; Path=/', uri: http);
    expect(jar.cookieHeader(http), isNull);
    store('normal=yes; Path=/', uri: http);
    expect(jar.cookieHeader(http), 'normal=yes');
    expect(jar.cookieHeader(eu), isNull);
  });

  test('standard secure cookie prefixes retain their restrictions', () {
    for (final value in [
      '__Secure-id=no; Path=/',
      '__Host-id=no; Secure; Domain=eu.market.example.test; Path=/',
      '__Host-id=no; Secure; Path=/api',
      '__Host-id=no; Secure',
    ]) {
      store(value);
      expect(jar.cookieHeader(eu), isNull, reason: value);
    }
    store('__Host-id=yes; Secure; Path=/');
    expect(jar.cookieHeader(eu), '__Host-id=yes');
  });

  test(
    'empty headers and malformed cookies are ignored without losing valid state',
    () {
      store('good=retained; Path=/');
      for (final value in [
        '',
        '   ',
        'missing-equals',
        '=missing-name',
        'bad name=value',
        'bad=value; Expires=nonsense',
        'bad=value; Max-Age=no',
        'bad=value; Max-Age=+5',
        'bad=value; Max-Age=9223372036854775808',
        'bad=value; Secure=yes',
        'bad="unterminated',
        'bad=contains space',
        'bad=value\r\nCookie: injected=yes',
        'bad=nonasciié',
      ]) {
        expect(() => store(value), returnsNormally);
        expect(jar.cookieHeader(eu), 'good=retained', reason: value);
      }
    },
  );

  test('an RFC-valid empty value is retained without inventing deletion', () {
    store('empty=');
    expect(jar.cookieHeader(eu), 'empty=');
  });

  test(
    'malformed cookie beside a valid combined record cannot inject pairs',
    () {
      store('bad name=value, good=yes; Path=/');
      expect(jar.cookieHeader(eu), 'good=yes');
      jar.clear();
      store('bad="comma, injected=yes"; Path=/');
      expect(jar.cookieHeader(eu), isNull);
    },
  );

  test('cookie names and values keep their case and quoted value bytes', () {
    store('Session="opaque=="; Path=/, session=lower; Path=/');
    expect(jar.cookieHeader(eu), 'Session="opaque=="; session=lower');
  });

  test('non-HTTP, credentialed and invalid-port origins are ignored', () {
    for (final uri in [
      Uri.parse('file:///api/orders'),
      Uri.parse('ftp://eu.market.example.test/api/orders'),
      Uri.parse('https://user:password@eu.market.example.test/api/orders'),
      Uri.parse('https://eu.market.example.test:70000/api/orders'),
    ]) {
      store('session=no; Path=/', uri: uri);
      expect(jar.cookieHeader(uri), isNull);
    }
    expect(jar.cookieHeader(eu), isNull);
  });

  test(
    'IP hosts accept only their exact domain and remain origin-isolated',
    () {
      final ip = Uri.parse('https://127.0.0.1/api/orders');
      store('bad=no; Domain=0.0.1; Path=/', uri: ip);
      expect(jar.cookieHeader(ip), isNull);
      store('good=yes; Domain=127.0.0.1; Path=/', uri: ip);
      expect(jar.cookieHeader(ip), 'good=yes');
    },
  );

  test('one cookie cannot exceed 4096 bytes', () {
    store('good=yes; Path=/');
    store('large=${'x' * MarketSessionCookies.maxCookieLength}; Path=/');
    expect(jar.cookieHeader(eu), 'good=yes');
  });

  test('oversized combined headers are ignored, not partially applied', () {
    store('good=yes; Path=/');
    store(
      'injected=yes; Path=/, huge=${'x' * MarketSessionCookies.maxHeaderLength}',
    );
    expect(jar.cookieHeader(eu), 'good=yes');
    jar.store(eu, {
      'Set-Cookie': 'one=${'x' * 33000}',
      'SET-COOKIE': 'two=${'y' * 33000}',
    });
    expect(jar.cookieHeader(eu), 'good=yes');
  });

  test('at most 64 cookies are held, evicting the least recently used', () {
    for (var i = 0; i < 65; i++) {
      store('c$i=value; Path=/');
    }
    final header = jar.cookieHeader(eu)!;
    expect(header.split('; '), hasLength(64));
    expect(header, isNot(contains('c0=')));
    expect(header, contains('c64=value'));
  });

  test('all origins share the same bounded count', () {
    for (var i = 0; i < 65; i++) {
      store(
        'session=value; Path=/',
        uri: Uri.parse('https://h$i.example.test/'),
      );
    }
    expect(jar.cookieHeader(Uri.parse('https://h0.example.test/')), isNull);
    expect(
      jar.cookieHeader(Uri.parse('https://h64.example.test/')),
      'session=value',
    );
  });

  test('combined outbound Cookie header never exceeds 64 KiB', () {
    for (var i = 0; i < 64; i++) {
      store('c$i=${'x' * 4000}; Path=/');
    }
    expect(
      jar.cookieHeader(eu)!.length,
      lessThanOrEqualTo(MarketSessionCookies.maxHeaderLength),
    );
    expect(jar.cookieHeader(eu), contains('c63='));
  });

  test('clear ends session; a new jar never inherits any cookie', () {
    store('session=one; Path=/, persistent=two; Max-Age=86400; Path=/');
    expect(MarketSessionCookies().cookieHeader(eu), isNull);
    jar.clear();
    expect(jar.cookieHeader(eu), isNull);
    store('new=three; Path=/');
    expect(jar.cookieHeader(eu), 'new=three');
  });
}

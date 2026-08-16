import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

enum MarketBonusArtwork { valuePack, richMerchantsRing }

/// Bundled in-game item artwork for the two Central Market collection bonuses.
///
/// These small assets are embedded so the profile never needs a network
/// request merely to paint its saved settings.
class MarketBonusIcon extends StatelessWidget {
  const MarketBonusIcon({required this.artwork, this.size = 40, super.key});

  final MarketBonusArtwork artwork;
  final double size;

  @override
  Widget build(BuildContext context) {
    final label = switch (artwork) {
      MarketBonusArtwork.valuePack => 'Value Pack icon',
      MarketBonusArtwork.richMerchantsRing => 'Rich Merchant’s Ring icon',
    };
    return Semantics(
      image: true,
      label: label,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(
          _bytesFor(artwork),
          key: ValueKey<String>('market-bonus:${artwork.name}'),
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

Uint8List _bytesFor(MarketBonusArtwork artwork) => switch (artwork) {
  MarketBonusArtwork.valuePack => _valuePackBytes,
  MarketBonusArtwork.richMerchantsRing => _richMerchantsRingBytes,
};

final Uint8List _valuePackBytes = base64Decode(_valuePackBase64);
final Uint8List _richMerchantsRingBytes = base64Decode(
  _richMerchantsRingBase64,
);

// Black Desert item 17583, the standard Value Pack artwork.
const String _valuePackBase64 =
    'UklGRgYFAABXRUJQVlA4WAoAAAAQAAAAKwAAKwAAQUxQSLABAAABBjm3tR179Dyx7XTOGHHaSTuVbauzbdulbRuVbdv2vHFyX++XP3DdETEBrP3ZpC9Jf5K4YJKG9dusOE/2XKQ6vwc5oyHANtjH6csPq24j75byPL+e5tf3JF90BHj1OFf6+xmp77/+LxWuANimS87xWSl0RbaMbEoOeQbpbcCAfz9/n8/GNJ53wxFxT7+iQMy8T6XAPcUG2/U4hPPqgj6VQu92gHjPLwUPi0Vk7EYtzwNY3ME8xlrPGbZ8mJeo+a2/oPPK3qLghX9L0ee1t5VE7cVxRbYoYGGpC0Zqk9e7sFhE3eJJdXa50URim53C/exuxP2u4I70BLx1IUS2/R9ufkGIFaRuL8W/PtIz1tas93kHR+dBf1Pz7N57X7hwtJWA2VNwzoO1sRKucQh6wLWdjTRyfSn6vPbOtpKQ9f9QXNE720h9Fv5TWLYRh3mSbbSzFH2phZEVnYStqwNotBM22gATJpy8opeu3bpz98HjNz/fftL/JZVK/o6uA7DBKQ0Ksotbqg7m9O1zdftlVb1Obm7vBagc7EXSl2QQScO69G1IepEYVjKkr6mhL71MbQVWUDggMAMAABAPAJ0BKiwALAA+bSyTRyQiIaEuOAgAgA2JbACsM97QvlyCEfvwGttl5gMce9ADy2fZV/xs0JezZB/gh3gygeAHFt3qZlTOVqFdKr0QFcQFtrGSEag+FNscmJSLfoRNQOlD6a+sRgF5DNRE+dpmHXDSxDgxdQfSyW1bBbyj8MszoAD+9ofV7xEPq/0KPxu4Y0eh53xvMb/zhCJL/Op8jkvuJwAKftatFpbr6y4lbHJcxy+NyOqSCJKBGtI/9Ew99jk1IZ/o76UWzzFZbaSWf5aaBPSP+xQs8Xe/9NANGhpOZCNpn3yydqSM+t10t6wwSMNiIYYPSbewuAn00S1ET3ttOH9layLJ9uPagfGi510X+BQbkQDlyTlzsRWsv43orq9839Js3Ew+1BU57jmQLJF7Pv//se1aMjcfRYW2/R87N4BtTM3Kuae8Gxl3eb1zygl858QpmZe2mr6vqXaSVVDGzKyQWLo8oywKUFPh4/N5neUSfuoQbaauVnizaFggQ19nqBSvekwMILIc+8P0CgNwksmSr4PQOAiHabyOubUwvh/InsSPi5dyp6S1M2cxp8yrdcceVhiF52rP7/FsVJTaOBy4pHhBZqxq8EF6aYr+BwAkxO65enZcv4MdQ/aG22agt+NEvtIsr6E1plv7tugJUh753qyiEiIEH/6dIZfC8CpxDr/I2edkonFymdtYkTvtALhZlGzZLl3cFv8GVcWZI6mejI/83bGLN0jLDqMD5Px73bbClEt2oS8WVMDhoYIVCDqAb9ZJOvIJ3X/k64PZrwJwaH4r/O6MzCHubK9f/2/SEnlvf8/a8667/iv8KbodDO1vF9G7Ze5Kr+iRTqpr6hqUg1b3fY7Vm7tz+BTpv/cWD/w2L0X70N+62K5oC1JVea+uUPwcSHA7rbTAY5OrkJWmKqvp+PukxyjmKRBcr6ZyXrrnJj5+RCpfEpI2owT+BOtmj53eXgzwTmcwg2xTJvBQGpOdUyYI+z2vH4OlvX6HPvtHOY3gcFhvUP0Dt8/0lHxIUCRwIcVl4+0o2/GOCWMHyQwRLzXDf+J/75X3j/aTwTTBiWzwsGAjMXZAAA==';

// Black Desert item 12034, Rich Merchant's Ring artwork.
const String _richMerchantsRingBase64 =
    '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';

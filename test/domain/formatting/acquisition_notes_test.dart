import 'package:bdo_craft_planner_flutter/domain/formatting/acquisition_notes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('explicit vendor and exchange lists keep their heading context', () {
    const vendorList = 'Purchase from:\nSealus\nLebyos\nLylina';
    const exchangeList = 'Exchange 10. Choose one:\n30 Wild Grass\n20 Logs';
    expect(
      composeAcquisitionNotes(notes: const [vendorList, exchangeList]),
      [vendorList, exchangeList],
    );
  });

  test('multiline reviewed vendor note retains each fact only once', () {
    expect(
      composeAcquisitionNotes(
        notes: const [
          'Buy from an Old Moon Manager in major cities.\n'
              'Price: 50,000,000 Silver each.\n'
              'Cannot be registered on the Central Market.',
          'Buy from Old Moon Manager in major cities.',
          ' Price: 50,000,000 Silver each. ',
        ],
        vendor: 'Old Moon Manager',
        location: 'major cities',
      ),
      [
        'Buy from an Old Moon Manager in major cities.',
        'Price: 50,000,000 Silver each.',
        'Cannot be registered on the Central Market.',
      ],
    );
  });

  test('richer vendor note replaces fallback while keeping other sellers', () {
    final lines = composeAcquisitionNotes(
      notes: const [
        'Buy from Waida in Sand Grain Bazaar.',
        'Buy it for 5,000 Silver from Waida at Sand Grain Bazaar '
            '(the convenient option) or Yasum in Arehaza. '
            'Right-click Purified Water to show both vendors on the map.',
        'Filtering Bottle of River Water.',
        'I keep spare water in Heidel.',
      ],
      vendor: 'Waida',
      location: 'Sand Grain Bazaar',
    );
    expect(lines, hasLength(4));
    expect(lines.first, contains('5,000 Silver'));
    expect(lines.first, contains('Yasum in Arehaza'));
    expect(lines.join('\n'), contains('Filtering Bottle of River Water.'));
    expect(lines.last, 'I keep spare water in Heidel.');
    expect(lines, isNot(contains('Buy from Waida in Sand Grain Bazaar.')));
  });

  test('vendor fallback remains when no purchase note exists', () {
    expect(composeAcquisitionNotes(notes: const [], vendor: 'Cooking Vendor'), [
      'Buy from Cooking Vendor.',
    ]);
  });

  test('different seller locations and restrictions are not merged', () {
    final lines = composeAcquisitionNotes(
      notes: const [
        'Buy from Waida in Valencia.',
        'Buy from Waida in Valencia or Yasum in Sand Grain Bazaar.',
        'Buy from Waida in Sand Grain Bazaar only after the quest.',
        'Cannot buy from Waida in Sand Grain Bazaar.',
      ],
      vendor: 'Waida',
      location: 'Sand Grain Bazaar',
    );
    expect(lines, hasLength(4));
    expect(lines, contains('Buy from Waida in Valencia.'));
    expect(lines.last, 'Cannot buy from Waida in Sand Grain Bazaar.');
  });

  test('another NPC location cannot suppress this vendor fallback', () {
    final lines = composeAcquisitionNotes(
      notes: const [
        'Buy from Waida in Valencia or Yasum in Sand Grain Bazaar.',
      ],
      vendor: 'Waida',
      location: 'Sand Grain Bazaar',
    );
    expect(lines, hasLength(2));
    expect(lines.last, 'Buy from Waida in Sand Grain Bazaar.');
  });

  test('NPC mentions without purchase instructions retain fallback', () {
    for (final note in [
      'Speak to Waida in Sand Grain Bazaar.',
      'Right-click to find Waida in Sand Grain Bazaar.',
      'Cannot buy from Waida in Sand Grain Bazaar.',
      'Buy from Waida in Sand Grain Bazaar no longer available.',
    ]) {
      expect(
        composeAcquisitionNotes(
          notes: [note],
          vendor: 'Waida',
          location: 'Sand Grain Bazaar',
        ),
        [note, 'Buy from Waida in Sand Grain Bazaar.'],
      );
    }
  });

  test(
    'exchange identities, quantities and number-to-item relations survive',
    () {
      final lines = composeAcquisitionNotes(
        notes: const [
          'Exchange 10 Fairy\'s Breath for 30 Wild Grass.\n'
              'Exchange 10 Dormant Fairy\'s Breath for 2 Sharps.',
          'Exchange 10 Wild Grass for 30 Fairy\'s Breath.',
          'Exchange 10 Fairy\'s Breath for 20 Wild Grass.',
        ],
      );
      expect(lines, hasLength(4));
    },
  );

  test('decimal values and sentence ordering are preserved', () {
    expect(
      composeAcquisitionNotes(
        notes: const ['Weight: 0.10 LT. Price: 3.5 silver.'],
      ),
      ['Weight: 0.10 LT.', 'Price: 3.5 silver.'],
    );
  });
}

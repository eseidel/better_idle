import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  group('FarmingCategory.test', () {
    test('creates category with defaults', () {
      const categoryId = MelvorId('melvorD:Allotment');
      const category = FarmingCategory.test(id: categoryId);
      expect(category.id, categoryId);
      expect(category.returnSeeds, isTrue);
      expect(category.harvestMultiplier, 1);
    });
  });

  group('FarmingCrop.test', () {
    test('creates crop with defaults', () {
      const categoryId = MelvorId('melvorD:Allotment');
      const seedId = MelvorId('melvorD:Potato_Seed');
      const productId = MelvorId('melvorD:Potato');
      final crop = FarmingCrop.test(
        name: 'Potato',
        categoryId: categoryId,
        seedId: seedId,
        productId: productId,
      );
      expect(crop.name, 'Potato');
      expect(crop.categoryId, categoryId);
      expect(crop.seedId, seedId);
      expect(crop.productId, productId);
      expect(crop.baseQuantity, 5);
      expect(crop.level, 1);
    });
  });
}

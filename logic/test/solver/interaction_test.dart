import 'package:logic/logic.dart';
import 'package:logic/src/solver/interactions/interaction.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('SellPolicySpec.toString', () {
    test('SellAllSpec returns expected string', () {
      const spec = SellAllSpec();

      expect(spec.toString(), 'SellAllSpec()');
    });

    test('ReserveConsumingInputsSpec returns expected string', () {
      const spec = ReserveConsumingInputsSpec();

      expect(spec.toString(), 'ReserveConsumingInputsSpec()');
    });
  });

  group('SellPolicy.toString', () {
    test('SellAllPolicy returns expected string', () {
      const policy = SellAllPolicy();

      expect(policy.toString(), 'SellAllPolicy()');
    });

    test('SellExceptPolicy with empty keep set returns expected string', () {
      const policy = SellExceptPolicy({});

      expect(policy.toString(), 'SellExceptPolicy(keep: 0 items)');
    });

    test('SellExceptPolicy with one item returns expected string', () {
      final policy = SellExceptPolicy({MelvorId.fromJson('melvorD:Oak_Logs')});

      expect(policy.toString(), 'SellExceptPolicy(keep: 1 items)');
    });

    test('SellExceptPolicy with multiple items returns expected string', () {
      final policy = SellExceptPolicy({
        MelvorId.fromJson('melvorD:Oak_Logs'),
        MelvorId.fromJson('melvorD:Willow_Logs'),
        MelvorId.fromJson('melvorD:Maple_Logs'),
      });

      expect(policy.toString(), 'SellExceptPolicy(keep: 3 items)');
    });
  });

  group('Interaction.toString', () {
    test('SwitchActivity returns expected string', () {
      final interaction = SwitchActivity(
        ActionId(
          MelvorId.fromJson('melvorD:Woodcutting'),
          MelvorId.fromJson('melvorD:Oak_Tree'),
        ),
      );

      expect(
        interaction.toString(),
        'SwitchActivity(melvorD:Woodcutting/melvorD:Oak_Tree)',
      );
    });

    test('BuyShopItem returns expected string', () {
      final interaction = BuyShopItem(
        MelvorId.fromJson('melvorD:Extra_Bank_Slot'),
      );

      expect(interaction.toString(), 'BuyShopItem(melvorD:Extra_Bank_Slot)');
    });

    test('SellItems returns expected string', () {
      const interaction = SellItems(SellAllPolicy());

      expect(interaction.toString(), 'SellItems(SellAllPolicy())');
    });

    test('SellItems with SellExceptPolicy returns expected string', () {
      final interaction = SellItems(
        SellExceptPolicy({
          MelvorId.fromJson('melvorD:Oak_Logs'),
          MelvorId.fromJson('melvorD:Willow_Logs'),
        }),
      );

      expect(
        interaction.toString(),
        'SellItems(SellExceptPolicy(keep: 2 items))',
      );
    });
  });

  group('SellPolicySpec.instantiate', () {
    test('SellAllSpec instantiates to SellAllPolicy', () {
      const spec = SellAllSpec();
      final state = GlobalState.empty(testRegistries);

      final policy = spec.instantiate(state, {});

      expect(policy, isA<SellAllPolicy>());
    });

    test('ReserveConsumingInputsSpec with no skills returns SellAllPolicy', () {
      const spec = ReserveConsumingInputsSpec();
      final state = GlobalState.empty(testRegistries);

      final policy = spec.instantiate(state, {});

      expect(policy, isA<SellAllPolicy>());
    });

    test('ReserveConsumingInputsSpec with consuming skills '
        'returns SellExceptPolicy', () {
      const spec = ReserveConsumingInputsSpec();
      // Give firemaking level to unlock burning logs
      final xpForLevel5 = startXpForLevel(5);
      final state = GlobalState.empty(testRegistries).copyWith(
        skillStates: {
          Skill.firemaking: SkillState(xp: xpForLevel5, masteryPoolXp: 0),
        },
      );

      final policy = spec.instantiate(state, {Skill.firemaking});

      // Firemaking consumes logs, so should return SellExceptPolicy
      expect(policy, isA<SellExceptPolicy>());
      final exceptPolicy = policy as SellExceptPolicy;
      expect(exceptPolicy.keepItems, isNotEmpty);
    });
  });

  group('SellPolicySpec JSON serialization', () {
    test('SellAllSpec round-trips through JSON', () {
      const original = SellAllSpec();
      final json = original.toJson();
      final restored = SellPolicySpec.fromJson(json);

      expect(restored, isA<SellAllSpec>());
      expect(restored.toString(), original.toString());
    });

    test('ReserveConsumingInputsSpec round-trips through JSON', () {
      const original = ReserveConsumingInputsSpec();
      final json = original.toJson();
      final restored = SellPolicySpec.fromJson(json);

      expect(restored, isA<ReserveConsumingInputsSpec>());
      expect(restored.toString(), original.toString());
    });

    test('SellAllSpec toJson has correct structure', () {
      const spec = SellAllSpec();
      final json = spec.toJson();

      expect(json['type'], 'SellAllSpec');
    });

    test('ReserveConsumingInputsSpec toJson has correct structure', () {
      const spec = ReserveConsumingInputsSpec();
      final json = spec.toJson();

      expect(json['type'], 'ReserveConsumingInputsSpec');
    });

    test('fromJson throws for unknown type', () {
      final json = {'type': 'UnknownSpec'};

      expect(() => SellPolicySpec.fromJson(json), throwsArgumentError);
    });
  });

  group('SellPolicy JSON serialization', () {
    test('SellAllPolicy round-trips through JSON', () {
      const original = SellAllPolicy();
      final json = original.toJson();
      final restored = SellPolicy.fromJson(json);

      expect(restored, isA<SellAllPolicy>());
    });

    test('SellExceptPolicy round-trips through JSON', () {
      final original = SellExceptPolicy({
        MelvorId.fromJson('melvorD:Oak_Logs'),
        MelvorId.fromJson('melvorD:Willow_Logs'),
      });
      final json = original.toJson();
      final restored = SellPolicy.fromJson(json);

      expect(restored, isA<SellExceptPolicy>());
      final restoredExcept = restored as SellExceptPolicy;
      expect(restoredExcept.keepItems.length, 2);
      expect(
        restoredExcept.keepItems,
        contains(MelvorId.fromJson('melvorD:Oak_Logs')),
      );
      expect(
        restoredExcept.keepItems,
        contains(MelvorId.fromJson('melvorD:Willow_Logs')),
      );
    });

    test('fromJson throws for unknown type', () {
      final json = {'type': 'UnknownPolicy'};

      expect(() => SellPolicy.fromJson(json), throwsArgumentError);
    });
  });

  group('Interaction JSON serialization', () {
    test('SwitchActivity round-trips through JSON', () {
      final original = SwitchActivity(
        ActionId(
          MelvorId.fromJson('melvorD:Woodcutting'),
          MelvorId.fromJson('melvorD:Oak_Tree'),
        ),
      );
      final json = original.toJson();
      final restored = Interaction.fromJson(json);

      expect(restored, isA<SwitchActivity>());
      final restoredSwitch = restored as SwitchActivity;
      expect(restoredSwitch.actionId.toJson(), original.actionId.toJson());
    });

    test('BuyShopItem round-trips through JSON', () {
      final original = BuyShopItem(
        MelvorId.fromJson('melvorD:Extra_Bank_Slot'),
      );
      final json = original.toJson();
      final restored = Interaction.fromJson(json);

      expect(restored, isA<BuyShopItem>());
      final restoredBuy = restored as BuyShopItem;
      expect(restoredBuy.purchaseId.toJson(), original.purchaseId.toJson());
    });

    test('SellItems with SellAllPolicy round-trips through JSON', () {
      const original = SellItems(SellAllPolicy());
      final json = original.toJson();
      final restored = Interaction.fromJson(json);

      expect(restored, isA<SellItems>());
      final restoredSell = restored as SellItems;
      expect(restoredSell.policy, isA<SellAllPolicy>());
    });

    test('SellItems with SellExceptPolicy round-trips through JSON', () {
      final original = SellItems(
        SellExceptPolicy({MelvorId.fromJson('melvorD:Oak_Logs')}),
      );
      final json = original.toJson();
      final restored = Interaction.fromJson(json);

      expect(restored, isA<SellItems>());
      final restoredSell = restored as SellItems;
      expect(restoredSell.policy, isA<SellExceptPolicy>());
    });

    test('fromJson throws for unknown type', () {
      final json = {'type': 'UnknownInteraction'};

      expect(() => Interaction.fromJson(json), throwsArgumentError);
    });
  });
}

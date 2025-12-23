/// Equipment slot types from Melvor Idle.
/// These are the valid slots where items can be equipped.
enum EquipmentSlot {
  weapon('Weapon'),
  shield('Shield'),
  helmet('Helmet'),
  platebody('Platebody'),
  platelegs('Platelegs'),
  boots('Boots'),
  gloves('Gloves'),
  cape('Cape'),
  amulet('Amulet'),
  ring('Ring'),
  quiver('Quiver'),
  passive('Passive'),
  summon1('Summon1'),
  summon2('Summon2'),
  consumable('Consumable'),
  enhancement1('Enhancement1'),
  enhancement2('Enhancement2'),
  enhancement3('Enhancement3');

  const EquipmentSlot(this.displayName);

  /// The display name for this slot.
  final String displayName;

  /// Returns the EquipmentSlot for the given Melvor JSON slot name.
  /// Throws if the slot name is not recognized.
  static EquipmentSlot fromJson(String slotName) {
    return switch (slotName) {
      'Weapon' => EquipmentSlot.weapon,
      'Shield' => EquipmentSlot.shield,
      'Helmet' => EquipmentSlot.helmet,
      'Platebody' => EquipmentSlot.platebody,
      'Platelegs' => EquipmentSlot.platelegs,
      'Boots' => EquipmentSlot.boots,
      'Gloves' => EquipmentSlot.gloves,
      'Cape' => EquipmentSlot.cape,
      'Amulet' => EquipmentSlot.amulet,
      'Ring' => EquipmentSlot.ring,
      'Quiver' => EquipmentSlot.quiver,
      'Passive' => EquipmentSlot.passive,
      'Summon1' => EquipmentSlot.summon1,
      'Summon2' => EquipmentSlot.summon2,
      'Consumable' => EquipmentSlot.consumable,
      'Enhancement1' => EquipmentSlot.enhancement1,
      'Enhancement2' => EquipmentSlot.enhancement2,
      'Enhancement3' => EquipmentSlot.enhancement3,
      _ => throw ArgumentError('Unknown equipment slot: $slotName'),
    };
  }

  /// Returns the JSON representation of this slot.
  String toJson() => displayName;
}

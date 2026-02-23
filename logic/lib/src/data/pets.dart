import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

/// A pet that can be found/unlocked during gameplay.
@immutable
class Pet {
  const Pet({
    required this.id,
    required this.name,
    required this.media,
    required this.ignoreCompletion,
  });

  factory Pet.fromJson(Map<String, dynamic> json, {required String namespace}) {
    return Pet(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      name: json['name'] as String,
      media: json['media'] as String?,
      ignoreCompletion: json['ignoreCompletion'] as bool? ?? false,
    );
  }

  final MelvorId id;
  final String name;
  final String? media;
  final bool ignoreCompletion;
}

/// Registry of all pets in the game.
@immutable
class PetRegistry {
  PetRegistry(this.pets) : _byId = {for (final pet in pets) pet.id: pet};

  const PetRegistry.empty() : pets = const [], _byId = const {};

  final List<Pet> pets;
  final Map<MelvorId, Pet> _byId;

  /// Returns the pet with the given [id], or throws if not found.
  Pet byId(MelvorId id) {
    final pet = _byId[id];
    if (pet == null) {
      throw StateError('Missing pet with id: $id');
    }
    return pet;
  }

  /// Returns only the pets that count toward completion.
  List<Pet> get completionPets =>
      pets.where((p) => !p.ignoreCompletion).toList();
}

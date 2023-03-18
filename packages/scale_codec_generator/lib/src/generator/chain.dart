import 'dart:io' show File, Directory;
import 'package:recase/recase.dart' show ReCase;
import 'package:path/path.dart' as path;
import '../typegen/typegen.dart'
    show
        VariantBuilder,
        TupleBuilder,
        TypeDescriptor,
        TypeBuilder,
        GeneratedOutput;
import '../typegen/frame_metadata.dart' show RuntimeMetadataV14;
import './pallet.dart' show PalletGenerator;
import './polkadart.dart' show PolkadartGenerator;

class ChainGenerator {
  final String name;
  final Directory directory;
  PolkadartGenerator polkadart;
  final Map<int, TypeDescriptor> types;

  ChainGenerator(
      {required this.name,
      required this.directory,
      required this.polkadart,
      required this.types});

  factory ChainGenerator.fromMetadata(
      {required Directory basePath,
      required chainName,
      required RuntimeMetadataV14 metadata,
      bool verbose = true}) {
    if (!basePath.existsSync()) {
      throw Exception(
          '[ERROR] Provided directory doesn\'t exists: "${path.normalize(basePath.path)}"');
    }

    // Create pallets and types directory
    final typesPath = path.join(basePath.path, 'types');
    final palletsPath = path.join(basePath.path, 'pallets');
    Directory(path.join(basePath.path)).createSync(recursive: false);
    Directory(typesPath).createSync(recursive: false);
    Directory(palletsPath).createSync(recursive: false);

    // Get type generators
    final Map<int, TypeDescriptor> typeGenerators =
        TypeDescriptor.fromTypes(metadata.registry, typesPath);

    // Get pallet generators
    final List<PalletGenerator> palletGenerators = metadata.pallets
        // Remove Empty Pallets
        // TODO: remove this field once we support extrinsics
        .where(
            (pallet) => pallet.storage != null || pallet.constants.isNotEmpty)
        .map((pallet) => PalletGenerator.fromMetadata(
              filePath: path.join(
                  palletsPath, '${ReCase(pallet.name).snakeCase}.dart'),
              palletMetadata: pallet,
              registry: typeGenerators,
            ))
        .toList();

    // Group generators per file
    final Map<String, List<TypeBuilder>> generatorPerFile =
        _groupTypeBuilderPerFile(typeGenerators.values);

    // Rename ambiguous generators
    for (final entry in generatorPerFile.entries) {
      final generatorList = entry.value;
      if (generatorList.length > 1) {
        int index = 0;
        for (final builder in entry.value) {
          index++;
          if (builder is VariantBuilder) {
            final filename = path.basenameWithoutExtension(builder.filePath);
            builder.filePath = path.join(
                path.dirname(builder.filePath), '${filename}_$index.dart');
            for (final variant in builder.variants) {
              if (variant.name == builder.name) {
                variant.name = '${variant.name}Variant';
              }
            }
          } else {
            final filename = path.basenameWithoutExtension(builder.filePath);
            builder.filePath = path.join(
                path.dirname(builder.filePath), '${filename}_$index.dart');
          }
        }
      }
    }

    return ChainGenerator(
      name: chainName,
      directory: basePath,
      polkadart: PolkadartGenerator(
        filePath: path.setExtension(
            path.join(basePath.path, ReCase(chainName).snakeCase), '.dart'),
        name: ReCase(chainName).pascalCase,
        pallets: palletGenerators,
      ),
      types: typeGenerators,
    );
  }

  /// Write the Generated Files
  build({bool verbose = false}) {
    final builderPerFile = _groupTypeBuilderPerFile(types.values);
    for (final entry in builderPerFile.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      if (verbose) {
        print(path.relative(entry.key, from: directory.path));
      }
      final String code = entry.value
          .fold(GeneratedOutput(classes: [], enums: [], typedefs: []),
              (previousValue, builder) => previousValue.merge(builder.build()))
          .build();
      Directory(path.dirname(entry.key)).createSync(recursive: true);
      File(entry.key).writeAsStringSync(code);
    }

    // Write the Pallets Files
    for (final pallet in polkadart.pallets) {
      final String code = pallet.generated().build();
      Directory(path.dirname(pallet.filePath)).createSync(recursive: true);
      File(pallet.filePath).writeAsStringSync(code);
      if (verbose) {
        print(path.relative(pallet.filePath, from: directory.path));
      }
    }

    // Write the Polkadart File
    final polkadartCode = polkadart.generate().build();
    File(polkadart.filePath).writeAsStringSync(polkadartCode);
    if (verbose) {
      print(path.relative(polkadart.filePath, from: directory.path));
    }
  }
}

/// Group TypeBuilder per file
Map<String, List<TypeBuilder>> _groupTypeBuilderPerFile(
    Iterable<TypeDescriptor> typeGenerators) {
  final Map<String, List<TypeBuilder>> generatorPerFile = {};

  for (final generator in typeGenerators) {
    if (generator is! TypeBuilder) {
      continue;
    }
    if (!generatorPerFile.containsKey(generator.filePath)) {
      generatorPerFile[generator.filePath] = [generator];
    } else if (generator is TupleBuilder) {
      final builders = generatorPerFile[generator.filePath]!;
      final isDuplicated = builders.whereType<TupleBuilder>().any(
          (tupleBuilder) =>
              tupleBuilder.generators.length == generator.generators.length);
      if (!isDuplicated) {
        generatorPerFile[generator.filePath]!.add(generator);
      }
    } else {
      generatorPerFile[generator.filePath]!.add(generator);
    }
  }
  return generatorPerFile;
}

// Copyright 2022 Amazon.com, Inc. or its affiliates. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:convert';
import 'dart:io';

import 'package:aft/aft.dart';
import 'package:aws_common/aws_common.dart';
import 'package:collection/collection.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:yaml_edit/yaml_edit.dart';

enum _DepsAction {
  check(
    'Checks whether all dependency constraints in the repo match '
        'the global dependency config',
    'All dependencies matched!',
  ),
  update(
    'Updates dependency constraints in aft.yaml to match the latest in pub',
    'Dependencies successfully updated!',
  ),
  apply(
    'Applies dependency constraints throughout the repo to match those '
        'in the global dependency config',
    'Dependencies successfully applied!',
  );

  const _DepsAction(this.description, this.successMessage);

  final String description;
  final String successMessage;
}

/// Command to manage dependencies across all Dart/Flutter packages in the repo.
class DepsCommand extends AmplifyCommand {
  DepsCommand() {
    addSubcommand(_DepsSubcommand(_DepsAction.check));
    addSubcommand(_DepsSubcommand(_DepsAction.apply));
    addSubcommand(_DepsUpdateCommand());
  }

  @override
  String get description =>
      'Manage dependencies across all packages in the Amplify Flutter repo';

  @override
  String get name => 'deps';
}

class _DepsSubcommand extends AmplifyCommand {
  _DepsSubcommand(this.action);

  final _DepsAction action;

  @override
  String get description => action.description;

  @override
  String get name => action.name;

  final _mismatchedDependencies = <String>[];

  void _checkDependency(
    PackageInfo package,
    Map<String, Dependency> dependencies,
    DependencyType dependencyType,
    MapEntry<String, VersionConstraint> globalDep,
  ) {
    final dependencyName = globalDep.key;
    final localDep = dependencies[dependencyName];
    if (localDep is! HostedDependency) {
      return;
    }
    bool satisfiesGlobalConstraint;
    final globalConstraint = globalDep.value;
    if (globalConstraint is Version) {
      satisfiesGlobalConstraint = globalDep.value == localDep.version;
    } else {
      final localConstraint = localDep.version;
      // Packages are not allowed to diverge from `aft.yaml`, even to specify
      // more precise constraints.
      satisfiesGlobalConstraint =
          globalConstraint.difference(localConstraint).isEmpty;
    }
    if (!satisfiesGlobalConstraint) {
      switch (action) {
        case _DepsAction.check:
          _mismatchedDependencies.add(
            '${package.path}\n'
            'Mismatched ${dependencyType.description} ($dependencyName):\n'
            'Expected ${globalDep.value}\n'
            'Found ${localDep.version}\n',
          );
          break;
        case _DepsAction.apply:
        case _DepsAction.update:
          package.pubspecInfo.pubspecYamlEditor.update(
            [dependencyType.key, dependencyName],
            '${globalDep.value}',
          );
          break;
      }
    }
  }

  Future<void> _run(_DepsAction action) async {
    final globalDependencyConfig = (await aftConfig).dependencies;
    for (final package in (await allPackages).values) {
      for (final globalDep in globalDependencyConfig.entries) {
        _checkDependency(
          package,
          package.pubspecInfo.pubspec.dependencies,
          DependencyType.dependency,
          globalDep,
        );
        _checkDependency(
          package,
          package.pubspecInfo.pubspec.dependencyOverrides,
          DependencyType.dependencyOverride,
          globalDep,
        );
        _checkDependency(
          package,
          package.pubspecInfo.pubspec.devDependencies,
          DependencyType.devDependency,
          globalDep,
        );
      }

      if (package.pubspecInfo.pubspecYamlEditor.edits.isNotEmpty) {
        File.fromUri(package.pubspecInfo.uri).writeAsStringSync(
          package.pubspecInfo.pubspecYamlEditor.toString(),
        );
      }
    }
    if (_mismatchedDependencies.isNotEmpty) {
      for (final mismatched in _mismatchedDependencies) {
        logger.stderr(mismatched);
      }
      exit(1);
    }
    logger.stdout(action.successMessage);
  }

  @override
  Future<void> run() async {
    return _run(action);
  }
}

class _DepsUpdateCommand extends _DepsSubcommand {
  _DepsUpdateCommand() : super(_DepsAction.update);

  @override
  Future<void> run() async {
    final globalDependencyConfig = (await aftConfig).dependencies;

    final aftEditor = YamlEditor(await aftConfigYaml);
    final failedUpdates = <String>[];
    for (final entry in globalDependencyConfig.entries) {
      final package = entry.key;
      final versionConstraint = entry.value;
      VersionConstraint? newVersionConstraint;

      // TODO(dnys1): Merge with publish logic
      // Get the currently published version of the package.
      final uri = Uri.parse('https://pub.dev/api/packages/$package');
      logger.trace('GET $uri');
      try {
        final resp = await httpClient.get(
          uri,
          headers: {AWSHeaders.accept: 'application/vnd.pub.v2+json'},
        );
        if (resp.statusCode != 200) {
          failedUpdates.add('$package: Could not reach server');
          continue;
        }
        final respJson = jsonDecode(resp.body) as Map<String, Object?>;
        final latestVersionStr =
            (respJson['latest'] as Map?)?['version'] as String?;
        if (latestVersionStr == null) {
          failedUpdates.add('$package: No versions found for package');
          continue;
        }
        final latestVersion = Version.parse(latestVersionStr);

        // Update the constraint to include `latestVersion` as its new upper
        // bound.
        if (versionConstraint is Version) {
          // For pinned versions, update them to the latest version (do not
          // create a range).
          if (latestVersion != versionConstraint) {
            newVersionConstraint = maxBy(
              [versionConstraint, latestVersion],
              (v) => v,
            );
          }
        } else {
          // For ranged versions, bump the upper bound to the latest version,
          // keeping the lower bound valid.
          versionConstraint as VersionRange;
          final lowerBound = versionConstraint.min;
          final includeLowerBound = versionConstraint.includeMin;
          final upperBound = versionConstraint.max;
          final includeUpperBound = upperBound == null || upperBound.includeMax;
          final newUpperBound = maxBy(
            [if (upperBound != null) upperBound, latestVersion],
            (v) => v,
          )!;
          final updateVersion = newUpperBound != lowerBound &&
              (upperBound == null || upperBound.compareTo(newUpperBound) < 0);
          if (updateVersion) {
            newVersionConstraint = VersionRange(
              min: lowerBound,
              includeMin: includeLowerBound,
              max: newUpperBound,
              includeMax: includeUpperBound,
            );
          }
        }
      } on Exception catch (e) {
        failedUpdates.add('$package: $e');
        continue;
      }

      if (newVersionConstraint != null) {
        aftEditor.update(
          ['dependencies', package],
          newVersionConstraint.toString(),
        );
      }
    }

    if (aftEditor.edits.isNotEmpty) {
      File(await aftConfigPath).writeAsStringSync(
        aftEditor.toString(),
        flush: true,
      );
      logger.stdout(action.successMessage);
    } else {
      logger.stderr('No dependencies updated');
    }

    for (final failedUpdate in failedUpdates) {
      logger.stderr('Could not update $failedUpdate');
      exitCode = 1;
    }

    await _run(_DepsAction.apply);
  }
}
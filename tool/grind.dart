// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dart_pad.grind;

import 'dart:async';
import 'dart:io';

import 'package:git/git.dart';
import 'package:grinder/grinder.dart';
import 'package:librato/librato.dart';
import 'package:yaml/yaml.dart' as yaml;

final FilePath _buildDir = new FilePath('build');
final FilePath _webDir = new FilePath('web');

Map get _env => Platform.environment;

main(List args) => grind(args);

@Task()
analyze() {
  new PubApp.global('tuneup')..run(['check']);
}

@Task()
testCli() => Tests.runCliTests();

// This task require a frame buffer to run.
@Task()
testWeb() => Tests.runWebTests(directory: 'build/test', htmlFile: 'web.html');

@Task('Run bower')
bower() => run('bower', arguments: ['install']);

@Task('Build the `web/index.html` entrypoint')
@Depends(bower)
build() {
  // Copy our third party python code into web/.
  new FilePath('third_party/mdetect/mdetect.py').copy(_webDir);

  Pub.build(directories: ['web', 'test']);

  FilePath mainFile = _buildDir.join('web', 'main.dart.js');
  log('${mainFile} compiled to ${_printSize(mainFile)}');

  FilePath mobileFile = _buildDir.join('web', 'mobile.dart.js');
  log('${mobileFile.path} compiled to ${_printSize(mobileFile)}');

  FilePath testFile = _buildDir.join('test', 'web.dart.js');
  log('${testFile.path} compiled to ${_printSize(testFile)}');

  // Delete the build/web/packages directory.
  delete(getDir('build/web/packages'));

  // Reify the symlinks.
  // cp -R -L packages build/web/packages
  run('cp', arguments: ['-R', '-L', 'packages', 'build/web/packages']);

  // Run vulcanize.
  FilePath mobileHtmlFile = _buildDir.join('web', 'mobile.html');
  log('${mobileHtmlFile.path} original: ${_printSize(mobileHtmlFile)}');
  run('vulcanize', // '--csp', '--inline',
      arguments: ['--strip', '--output', 'mobile.html', 'mobile.html'],
      workingDirectory: 'build/web');
  log('${mobileHtmlFile.path} vulcanize: ${_printSize(mobileHtmlFile)}');

  return _uploadCompiledStats(
      mainFile.asFile.lengthSync(),
      mobileFile.asFile.lengthSync());
}

@Task()
coverage() {
  if (!_env.containsKey('COVERAGE_TOKEN')) {
    log("env var 'COVERAGE_TOKEN' not found");
    return;
  }

  PubApp coveralls = new PubApp.global('dart_coveralls');
  coveralls.run([
    'report',
    '--token', _env['COVERAGE_TOKEN'],
    '--retry', '2',
    '--exclude-test-files',
    'test/all.dart']);
}

@DefaultTask()
@Depends(analyze, testCli, coverage, build)
void buildbot() => null;

@Task('Prepare the app for deployment')
@Depends(buildbot)
deploy() {
  // Validate the deploy. This means that we're using version `dev` on the
  // master branch and version `prod` on the prod branch. We only deploy prod
  // from the prod branch. Other versions are possible but not verified.

  // `dev` is served from dev.dart-pad.appspot.com
  // `prod` is served from prod.dart-pad.appspot.com and from dartpad.dartlang.org.

  Map app = yaml.loadYaml(new File('web/app.yaml').readAsStringSync());

  final String version = app['version'];
  List handlers = app['handlers'];
  bool isSecure = false;

  for (Map m in handlers) {
    if (m['url'] == '.*') {
      isSecure = m['secure'] == 'always';
    }
  }

  return GitDir.fromExisting('.').then((GitDir dir) {
    return dir.getCurrentBranch();
  }).then((BranchReference branchRef) {
    final String branch = branchRef.branchName;

    log('branch: ${branch}');
    log('version: ${version}');

    if (branch == 'prod') {
      if (version != 'prod') {
        fail('Trying to deploy non-prod version from the prod branch');
      }

      if (!isSecure) {
        fail('The prod branch must have `secure: always`.');
      }
    }

    if (branch == 'master') {
      if (version != 'dev') {
        fail('Trying to deploy non-dev version from the master branch');
      }
    }

    if (version == 'prod') {
      if (branch != 'prod') {
        fail('The prod version can only be deployed from the prod branch');
      }
    }

    if (version != 'prod') {
      if (isSecure) {
        fail('The ${version} version should not have `secure: always` set');
      }
    }

    log('\nexecute: `appcfg.py update build/web`');
  });
}

@Task()
clean() => defaultClean();

Future _uploadCompiledStats(num mainLength, int mobileLength) {
  Map env = Platform.environment;

  if (env.containsKey('LIBRATO_USER') && env.containsKey('TRAVIS_COMMIT')) {
    Librato librato = new Librato.fromEnvVars();
    log('Uploading stats to ${librato.baseUrl}');
    LibratoStat mainSize = new LibratoStat('main.dart.js', mainLength);
    LibratoStat mobileSize = new LibratoStat('mobileSize.dart.js', mobileLength);
    return librato.postStats([mainSize, mobileSize]).then((_) {
      String commit = env['TRAVIS_COMMIT'];
      LibratoLink link = new LibratoLink(
          'github',
          'https://github.com/dart-lang/dart-pad/commit/${commit}');
      LibratoAnnotation annotation = new LibratoAnnotation(
          commit,
          description: 'Commit ${commit}',
          links: [link]);
      return librato.createAnnotation('build_ui', annotation);
    });
  } else {
    return new Future.value();
  }
}

String _printSize(FilePath file) =>
    '${(file.asFile.lengthSync() + 1023) ~/ 1024}k';
